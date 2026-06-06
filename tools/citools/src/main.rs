mod jenkins;
mod pipeline;

use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Instant;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use jenkins::{export_stage, next_done, next_stage, ExportManifest};
use pipeline::{load_pipeline, Pipeline, Stage};

#[derive(Parser)]
#[command(
    name = "citools",
    about = "CI stage runner — pipeline YAML, agnostic to Jenkins/GHA",
    long_about = "Stages in pipeline.yaml. Jenkins: `citools next --json` + readJSON + stage(stageName)."
)]
struct Cli {
    /// Path to pipeline.yaml (or CITOOLS_PIPELINE env)
    #[arg(
        long,
        global = true,
        env = "CITOOLS_PIPELINE",
        default_value = "components/ssdnodes/jenkins/pipeline.yaml"
    )]
    pipeline: PathBuf,

    /// Repo root for relative commands
    #[arg(long, global = true, env = "CITOOLS_REPO_ROOT")]
    repo_root: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// List stages defined in pipeline.yaml
    List,
    /// Print execution plan (dry-run, human text)
    Plan,
    /// Manifest JSON — todos os stages habilitados (readJSON / preview)
    ExportJson,
    /// Próximo stage habilitado — um JSON por chamada (loop Groovy)
    Next {
        /// Emitir JSON (stdout). Sem flag: texto humano.
        #[arg(long)]
        json: bool,
        /// Retomar após este stage id (exclusive)
        #[arg(long)]
        after: Option<String>,
    },
    /// Run a single stage by id
    Run { stage_id: String },
    /// Run all stages sequentially (fail-fast)
    RunAll {
        /// Continue after stage failure
        #[arg(long)]
        keep_going: bool,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let repo_root = cli
        .repo_root
        .unwrap_or_else(|| std::env::current_dir().expect("cwd"));
    let pipeline = load_pipeline(&cli.pipeline)?;

    match cli.command {
        Commands::List => cmd_list(&pipeline),
        Commands::Plan => cmd_plan(&pipeline),
        Commands::ExportJson => cmd_export_json(&pipeline),
        Commands::Next { json, after } => cmd_next(&pipeline, json, after.as_deref()),
        Commands::Run { stage_id } => cmd_run(&pipeline, &repo_root, &stage_id),
        Commands::RunAll { keep_going } => cmd_run_all(&pipeline, &repo_root, keep_going),
    }
}

fn jenkins_stages(p: &Pipeline) -> Vec<&Stage> {
    p.stages.iter().filter(|s| s.jenkins).collect()
}

fn enabled_stages<'a>(stages: &[&'a Stage]) -> Vec<&'a Stage> {
    stages
        .iter()
        .copied()
        .filter(|s| stage_enabled(s))
        .collect()
}

fn cmd_list(p: &Pipeline) -> Result<()> {
    println!("pipeline: {} ({} stages)", p.name, p.stages.len());
    for s in &p.stages {
        let when = s
            .when
            .as_deref()
            .map(|w| format!(" when={w}"))
            .unwrap_or_default();
        let jenkins = if s.jenkins { "" } else { " jenkins=false" };
        println!(
            "  - {}: {}{}{}",
            s.id,
            s.description.as_deref().unwrap_or(""),
            when,
            jenkins
        );
    }
    Ok(())
}

fn cmd_plan(p: &Pipeline) -> Result<()> {
    println!("# citools plan — {}", p.name);
    for (i, s) in p.stages.iter().enumerate() {
        if !stage_enabled(s) {
            println!(
                "{}. [{}] (skip when={})",
                i + 1,
                s.id,
                s.when.as_deref().unwrap_or("-")
            );
            continue;
        }
        println!("{}. [{}] {}", i + 1, s.id, s.run);
        if let Some(w) = &s.when {
            println!("   when: {w}");
        }
    }
    Ok(())
}

fn cmd_export_json(p: &Pipeline) -> Result<()> {
    let candidates = jenkins_stages(p);
    let enabled = enabled_stages(&candidates);
    let stages: Vec<_> = enabled
        .iter()
        .enumerate()
        .map(|(i, s)| export_stage(s, i + 1))
        .collect();
    let manifest = ExportManifest {
        pipeline: p.name.clone(),
        version: p.version,
        stages,
    };
    emit_json(&manifest)
}

fn cmd_next(p: &Pipeline, json: bool, after: Option<&str>) -> Result<()> {
    let candidates = jenkins_stages(p);
    let enabled = enabled_stages(&candidates);
    let total = enabled.len();

    let mut past_cursor = after.is_none();
    for (idx, stage) in enabled.iter().enumerate() {
        if !past_cursor {
            if Some(stage.id.as_str()) == after {
                past_cursor = true;
            }
            continue;
        }
        let response = next_stage(stage, idx + 1, total);
        if json {
            return emit_json(&response);
        }
        println!(
            "next: [{}] {} ({}/{})",
            stage.id,
            jenkins::stage_display_name(stage),
            idx + 1,
            total
        );
        return Ok(());
    }

    if json {
        return emit_json(&next_done());
    }
    println!("next: done");
    Ok(())
}

fn emit_json<T: serde::Serialize>(value: &T) -> Result<()> {
    let mut stdout = io::stdout().lock();
    serde_json::to_writer(&mut stdout, value)?;
    stdout.write_all(b"\n")?;
    Ok(())
}

fn cmd_run(p: &Pipeline, repo_root: &PathBuf, stage_id: &str) -> Result<()> {
    let stage = p
        .stages
        .iter()
        .find(|s| s.id == stage_id)
        .with_context(|| format!("stage not found: {stage_id}"))?;
    run_stage(stage, repo_root)?;
    Ok(())
}

fn cmd_run_all(p: &Pipeline, repo_root: &PathBuf, keep_going: bool) -> Result<()> {
    let mut failed = Vec::new();
    for stage in &p.stages {
        if !stage_enabled(stage) {
            eprintln!(
                "⏭  skip {} (when={})",
                stage.id,
                stage.when.as_deref().unwrap_or("-")
            );
            continue;
        }
        match run_stage(stage, repo_root) {
            Ok(()) => eprintln!("✓  {}", stage.id),
            Err(e) => {
                eprintln!("✗  {} — {:#}", stage.id, e);
                failed.push(stage.id.clone());
                if !keep_going {
                    bail!("stage {} failed", stage.id);
                }
            }
        }
    }
    if !failed.is_empty() {
        bail!("failed stages: {}", failed.join(", "));
    }
    Ok(())
}

fn stage_enabled(stage: &Stage) -> bool {
    match stage.when.as_deref() {
        None | Some("") | Some("always") => true,
        Some("never") => false,
        Some(expr) if expr.starts_with("env:") => {
            let key = expr.trim_start_matches("env:");
            std::env::var(key).is_ok_and(|v| !v.is_empty() && v != "0" && v != "false")
        }
        Some(expr) if expr.starts_with("branch:") => branch_matches(expr.trim_start_matches("branch:")),
        Some(_) => true,
    }
}

fn branch_matches(want: &str) -> bool {
    let branch = std::env::var("CITOOLS_BRANCH")
        .or_else(|_| std::env::var("BRANCH_NAME"))
        .or_else(|_| std::env::var("CHANGE_BRANCH"))
        .unwrap_or_default();
    if want.starts_with('!') {
        branch != want.trim_start_matches('!')
    } else {
        branch == want || branch.ends_with(&format!("/{want}"))
    }
}

#[cfg(test)]
mod branch_tests {
    use super::*;

    #[test]
    fn branch_main_exact() {
        std::env::set_var("CITOOLS_BRANCH", "main");
        assert!(branch_matches("main"));
        std::env::remove_var("CITOOLS_BRANCH");
    }

    #[test]
    fn branch_not_main() {
        std::env::set_var("CITOOLS_BRANCH", "feat/foo");
        assert!(branch_matches("!main"));
        std::env::remove_var("CITOOLS_BRANCH");
    }
}

fn run_stage(stage: &Stage, repo_root: &PathBuf) -> Result<()> {
    eprintln!("→  {} — {}", stage.id, stage.run);
    let start = Instant::now();
    let status = Command::new("bash")
        .arg("-c")
        .arg(&stage.run)
        .current_dir(repo_root)
        .envs(std::env::vars())
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("failed to spawn stage {}", stage.id))?;
    let elapsed = start.elapsed();
    if status.success() {
        eprintln!("   done in {:.1}s", elapsed.as_secs_f64());
        Ok(())
    } else {
        bail!(
            "exit code {:?} after {:.1}s",
            status.code(),
            elapsed.as_secs_f64()
        )
    }
}
