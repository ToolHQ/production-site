use std::path::Path;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

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
        self.deploy.clone().unwrap_or_else(|| defaults.deploy.clone())
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

#[cfg(test)]
mod tests {
    use super::*;

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
}
