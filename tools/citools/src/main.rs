mod deploy;
mod jenkins;
mod paths;
mod pipeline;

use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Instant;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use deploy::{apps_for_changed_paths, find_app, git_changed_paths, load_catalog, DeployCatalog};
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

    /// Path to deploy-catalog.yaml (deploy subcommand)
    #[arg(
        long,
        env = "CITOOLS_DEPLOY_CATALOG",
        default_value = "tools/citools/deploy-catalog.yaml"
    )]
    deploy_catalog: PathBuf,

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
    /// App deploy catalog (T-346)
    Deploy {
        #[command(subcommand)]
        action: DeployCommands,
    },
}

#[derive(Subcommand)]
enum DeployCommands {
    /// List apps in deploy-catalog.yaml
    List,
    /// JSON plan for build + deploy
    Plan {
        #[arg(long)]
        app: String,
        #[arg(long, default_value = "oci")]
        target: String,
    },
    /// Run deploy.sh for app (wraps existing script)
    Run {
        #[arg(long, conflicts_with = "changed")]
        app: Option<String>,
        #[arg(long, default_value = "oci")]
        target: String,
        #[arg(long)]
        dry_run: bool,
        /// Deploy apps whose whenPaths intersect git diff vs base branch
        #[arg(long, conflicts_with = "app")]
        changed: bool,
        #[arg(long, default_value = "main")]
        base: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let repo_root = cli
        .repo_root
        .unwrap_or_else(|| std::env::current_dir().expect("cwd"));

    if let Commands::Deploy { action } = cli.command {
        let catalog = load_catalog(&cli.deploy_catalog)?;
        return match action {
            DeployCommands::List => cmd_deploy_list(&catalog),
            DeployCommands::Plan { app, target } => cmd_deploy_plan(&catalog, &app, &target),
            DeployCommands::Run {
                app,
                target,
                dry_run,
                changed,
                base,
            } => cmd_deploy_run(&catalog, &repo_root, app, &target, dry_run, changed, &base),
        };
    }

    let pipeline = load_pipeline(&cli.pipeline)?;

    match cli.command {
        Commands::List => cmd_list(&pipeline, &repo_root),
        Commands::Plan => cmd_plan(&pipeline, &repo_root),
        Commands::ExportJson => cmd_export_json(&pipeline, &repo_root),
        Commands::Next { json, after } => cmd_next(&pipeline, &repo_root, json, after.as_deref()),
        Commands::Run { stage_id } => cmd_run(&pipeline, &repo_root, &stage_id),
        Commands::RunAll { keep_going } => cmd_run_all(&pipeline, &repo_root, keep_going),
        Commands::Deploy { .. } => unreachable!(),
    }
}

fn jenkins_stages(p: &Pipeline) -> Vec<&Stage> {
    p.stages.iter().filter(|s| s.jenkins).collect()
}

fn enabled_stages<'a>(stages: &[&'a Stage], repo_root: &Path) -> Vec<&'a Stage> {
    stages
        .iter()
        .copied()
        .filter(|s| stage_enabled(s, repo_root))
        .collect()
}

fn cmd_list(p: &Pipeline, _repo_root: &Path) -> Result<()> {
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

fn cmd_deploy_list(catalog: &DeployCatalog) -> Result<()> {
    println!("deploy catalog ({} apps)", catalog.apps.len());
    for app in &catalog.apps {
        let build = app.effective_build(&catalog.defaults);
        let deploy = app.effective_deploy(&catalog.defaults);
        println!(
            "  - {} worker={} platform={} target={} script={}",
            app.id, build.worker, build.platform, deploy.target, app.script
        );
    }
    Ok(())
}

fn cmd_deploy_plan(catalog: &DeployCatalog, app_id: &str, target: &str) -> Result<()> {
    let app = find_app(catalog, app_id)?;
    let build = app.effective_build(&catalog.defaults);
    let mut deploy = app.effective_deploy(&catalog.defaults);
    if !deploy.targets.iter().any(|t| t == target) {
        bail!(
            "target {target} não permitido para {} (targets: {:?})",
            app.id,
            deploy.targets
        );
    }
    deploy.target = target.to_string();
    let plan = serde_json::json!({
        "app": app.id,
        "path": app.path,
        "script": app.script,
        "build": { "worker": build.worker, "platform": build.platform },
        "deploy": { "target": deploy.target, "kubeconfig_env": deploy.kubeconfig_env },
        "steps": [
            format!("build via {} ({})", build.worker, build.platform),
            "push registry (deploy.sh / deploy-buildx.sh)",
            format!("kubectl apply target={}", deploy.target),
        ],
    });
    emit_json(&plan)
}

fn cmd_deploy_run(
    catalog: &DeployCatalog,
    repo_root: &PathBuf,
    app_id: Option<String>,
    target: &str,
    dry_run: bool,
    changed: bool,
    base: &str,
) -> Result<()> {
    if changed {
        let paths = git_changed_paths(repo_root, base)?;
        if paths.is_empty() {
            eprintln!("deploy --changed: nenhum arquivo alterado vs origin/{base}");
            return Ok(());
        }
        let apps = apps_for_changed_paths(catalog, &paths);
        if apps.is_empty() {
            eprintln!(
                "deploy --changed: {} paths alterados, nenhum app no catálogo",
                paths.len()
            );
            return Ok(());
        }
        eprintln!(
            "deploy --changed: {} app(s) — {}",
            apps.len(),
            apps.iter()
                .map(|a| a.id.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        );
        for app in apps {
            run_one_deploy(catalog, repo_root, app, target, dry_run)?;
        }
        return Ok(());
    }
    let app_id = app_id.context("--app obrigatório sem --changed")?;
    let app = find_app(catalog, &app_id)?;
    run_one_deploy(catalog, repo_root, app, target, dry_run)
}

fn run_one_deploy(
    catalog: &DeployCatalog,
    repo_root: &PathBuf,
    app: &deploy::DeployApp,
    target: &str,
    dry_run: bool,
) -> Result<()> {
    let build = app.effective_build(&catalog.defaults);
    let deploy = app.effective_deploy(&catalog.defaults);
    if !deploy.targets.iter().any(|t| t == target) {
        bail!(
            "target {target} não permitido para {} (targets: {:?})",
            app.id,
            deploy.targets
        );
    }
    eprintln!(
        "→ deploy {} target={} worker={} script={}",
        app.id, target, build.worker, app.script
    );
    if dry_run {
        eprintln!("   (dry-run — não executa deploy.sh)");
        return Ok(());
    }
    let wrapper = repo_root.join("tools/citools/scripts/deploy-run.sh");
    let status = Command::new("bash")
        .arg(&wrapper)
        .arg(&app.script)
        .current_dir(repo_root)
        .env("CITOOLS_REPO_ROOT", repo_root)
        .env("CITOOLS_DEPLOY_APP", &app.id)
        .env("CITOOLS_BUILD_WORKER", &build.worker)
        .env("CITOOLS_DEPLOY_TARGET", target)
        .envs(std::env::vars())
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("failed to run deploy wrapper for {}", app.id))?;
    if status.success() {
        Ok(())
    } else {
        bail!("deploy {} exit {:?}", app.id, status.code());
    }
}

fn cmd_plan(p: &Pipeline, repo_root: &Path) -> Result<()> {
    println!("# citools plan — {}", p.name);
    for (i, s) in p.stages.iter().enumerate() {
        if !stage_enabled(s, repo_root) {
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

fn cmd_export_json(p: &Pipeline, repo_root: &Path) -> Result<()> {
    let candidates = jenkins_stages(p);
    let enabled = enabled_stages(&candidates, repo_root);
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

fn cmd_next(p: &Pipeline, repo_root: &Path, json: bool, after: Option<&str>) -> Result<()> {
    let candidates = jenkins_stages(p);
    let enabled = enabled_stages(&candidates, repo_root);
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
        if !stage_enabled(stage, repo_root) {
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

fn stage_enabled(stage: &Stage, repo_root: &Path) -> bool {
    if !matches_when_expr(stage.when.as_deref(), repo_root) {
        return false;
    }
    if let Some(ref paths) = stage.when_paths {
        return paths::paths_when_enabled(&format!("paths:{paths}"), repo_root);
    }
    true
}

fn matches_when_expr(expr: Option<&str>, repo_root: &Path) -> bool {
    match expr {
        None | Some("") | Some("always") => true,
        Some("never") => false,
        Some(e) if e.starts_with("env:") => {
            let key = e.trim_start_matches("env:");
            std::env::var(key).is_ok_and(|v| !v.is_empty() && v != "0" && v != "false")
        }
        Some(e) if e.starts_with("branch:") => branch_matches(e.trim_start_matches("branch:")),
        Some(e) if e.starts_with("paths:") => paths::paths_when_enabled(e, repo_root),
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
