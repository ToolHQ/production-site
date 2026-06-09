use std::path::Path;
use std::process::Command;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

use crate::paths::any_path_matches;

#[derive(Debug, Deserialize)]
pub struct DeployCatalog {
    pub version: u32,
    #[serde(default)]
    pub defaults: DeployDefaults,
    pub apps: Vec<DeployApp>,
}

#[derive(Debug, Default, Deserialize)]
pub struct DeployDefaults {
    #[serde(default)]
    pub build: BuildSpec,
    #[serde(default)]
    pub deploy: DeploySpec,
}

#[derive(Debug, Deserialize, Clone)]
pub struct DeployApp {
    pub id: String,
    pub path: String,
    pub script: String,
    #[serde(default)]
    pub build: Option<BuildSpec>,
    #[serde(default)]
    pub deploy: Option<DeploySpec>,
    #[serde(default, rename = "whenPaths")]
    pub when_paths: Option<String>,
}

#[derive(Debug, Default, Deserialize, Clone)]
pub struct BuildSpec {
    #[serde(default = "default_worker")]
    pub worker: String,
    #[serde(default = "default_platform")]
    pub platform: String,
}

#[derive(Debug, Default, Deserialize, Clone)]
pub struct DeploySpec {
    #[serde(default = "default_target")]
    pub target: String,
    #[serde(default = "default_kubeconfig_env")]
    pub kubeconfig_env: String,
    /// Targets permitidos (default: oci, ssdnodes)
    #[serde(default = "default_targets")]
    pub targets: Vec<String>,
}

fn default_targets() -> Vec<String> {
    vec!["oci".into(), "ssdnodes".into()]
}

fn default_worker() -> String {
    "hetzner".into()
}
fn default_platform() -> String {
    "linux/arm64".into()
}
fn default_target() -> String {
    "oci".into()
}
fn default_kubeconfig_env() -> String {
    "KUBECONFIG".into()
}

impl DeployApp {
    pub fn effective_build<'a>(&'a self, defaults: &'a DeployDefaults) -> BuildSpec {
        self.build.clone().unwrap_or_else(|| defaults.build.clone())
    }

    pub fn effective_deploy<'a>(&'a self, defaults: &'a DeployDefaults) -> DeploySpec {
        self.deploy
            .clone()
            .unwrap_or_else(|| defaults.deploy.clone())
    }
}

pub fn load_catalog(path: &Path) -> Result<DeployCatalog> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("read deploy catalog: {}", path.display()))?;
    let catalog: DeployCatalog = serde_yaml::from_str(&raw)
        .with_context(|| format!("parse deploy catalog: {}", path.display()))?;
    if catalog.version != 1 {
        bail!("unsupported deploy catalog version: {}", catalog.version);
    }
    Ok(catalog)
}

pub fn find_app<'a>(catalog: &'a DeployCatalog, id: &str) -> Result<&'a DeployApp> {
    catalog
        .apps
        .iter()
        .find(|a| a.id == id)
        .with_context(|| format!("app not found in catalog: {id}"))
}

pub fn when_paths_patterns(app: &DeployApp) -> Vec<String> {
    app.when_paths
        .as_deref()
        .map(|s| {
            s.split(',')
                .map(str::trim)
                .filter(|p| !p.is_empty())
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

pub fn app_matches_changed_paths(app: &DeployApp, changed: &[String]) -> bool {
    let patterns = when_paths_patterns(app);
    if patterns.is_empty() {
        return false;
    }
    let pattern_refs: Vec<&str> = patterns.iter().map(String::as_str).collect();
    any_path_matches(&pattern_refs, changed)
}

pub fn git_changed_paths(repo_root: &Path, base: &str) -> Result<Vec<String>> {
    let output = Command::new("git")
        .args(["diff", "--name-only", &format!("origin/{base}...HEAD")])
        .current_dir(repo_root)
        .output()
        .context("git diff for deploy --changed")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("git diff failed: {stderr}");
    }
    let paths: Vec<String> = String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(String::from)
        .collect();
    Ok(paths)
}

pub fn apps_for_changed_paths<'a>(
    catalog: &'a DeployCatalog,
    changed: &[String],
) -> Vec<&'a DeployApp> {
    catalog
        .apps
        .iter()
        .filter(|app| app_matches_changed_paths(app, changed))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::paths::path_matches_pattern;

    #[test]
    fn parses_catalog() {
        let yaml = r#"
version: 1
apps:
  - id: demo
    path: apps/demo
    script: ./apps/demo/deploy.sh
"#;
        let c: DeployCatalog = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(c.apps[0].id, "demo");
    }

    #[test]
    fn when_paths_match_changed() {
        let app = DeployApp {
            id: "ai-radar".into(),
            path: "apps/ai-radar".into(),
            script: "./apps/ai-radar/deploy.sh".into(),
            build: None,
            deploy: None,
            when_paths: Some("apps/ai-radar/**".into()),
        };
        let changed = vec!["apps/ai-radar/api/src/main.rs".into()];
        assert!(app_matches_changed_paths(&app, &changed));
        assert!(!app_matches_changed_paths(
            &app,
            &["tools/citools/src/main.rs".into()]
        ));
    }

    #[test]
    fn path_pattern_exact() {
        assert!(path_matches_pattern("apps/foo/x", "apps/foo/x"));
    }
}
