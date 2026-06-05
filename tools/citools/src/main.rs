mod pipeline;

use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::Instant;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use pipeline::{load_pipeline, Pipeline, Stage};

#[derive(Parser)]
#[command(
    name = "citools",
    about = "CI stage runner — pipeline YAML, agnostic to Jenkins/GHA",
    long_about = "Define stages in pipeline.yaml; Jenkins/GHA/shell only orchestrate `citools run-all`."
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
    /// Print execution plan (dry-run)
    Plan,
    /// Run a single stage by id
    Run {
        stage_id: String,
    },
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
        Commands::Run { stage_id } => cmd_run(&pipeline, &repo_root, &stage_id),
        Commands::RunAll { keep_going } => cmd_run_all(&pipeline, &repo_root, keep_going),
    }
}

fn cmd_list(p: &Pipeline) -> Result<()> {
    println!("pipeline: {} ({} stages)", p.name, p.stages.len());
    for s in &p.stages {
        let when = s
            .when
            .as_deref()
            .map(|w| format!(" when={w}"))
            .unwrap_or_default();
        println!("  - {}: {}{}", s.id, s.description.as_deref().unwrap_or(""), when);
    }
    Ok(())
}

fn cmd_plan(p: &Pipeline) -> Result<()> {
    println!("# citools plan — {}", p.name);
    for (i, s) in p.stages.iter().enumerate() {
        println!("{}. [{}] {}", i + 1, s.id, s.run);
        if let Some(w) = &s.when {
            println!("   when: {w}");
        }
    }
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
            eprintln!("⏭  skip {} (when={})", stage.id, stage.when.as_deref().unwrap_or("-"));
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
        Some(_) => true, // future: branch/path expressions
    }
}

fn run_stage(stage: &Stage, repo_root: &PathBuf) -> Result<()> {
    eprintln!("→  {} — {}", stage.id, stage.run);
    let start = Instant::now();
    // bash -c (not -lc): login shell reseta PATH e quebra stages que invocam citools
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
