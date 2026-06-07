use std::path::Path;

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Pipeline {
    pub version: u32,
    pub name: String,
    pub stages: Vec<Stage>,
}

#[derive(Debug, Deserialize)]
pub struct Stage {
    pub id: String,
    #[serde(default)]
    pub description: Option<String>,
    /// Nome exibido no Jenkins Blue Ocean (`stage(stageName)`).
    #[serde(default, rename = "stageName")]
    pub stage_name: Option<String>,
    pub run: String,
    #[serde(default)]
    pub when: Option<String>,
    /// Filtro path-aware (AND com `when`) — globs separados por vírgula.
    #[serde(default, rename = "whenPaths")]
    pub when_paths: Option<String>,
    /// false = só run-all local; não entra em export-json / next (Jenkins).
    #[serde(default = "default_jenkins")]
    pub jenkins: bool,
}

fn default_jenkins() -> bool {
    true
}

pub fn load_pipeline(path: &Path) -> Result<Pipeline> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("read pipeline: {}", path.display()))?;
    let pipeline: Pipeline = serde_yaml::from_str(&raw)
        .with_context(|| format!("parse pipeline YAML: {}", path.display()))?;
    if pipeline.version != 1 {
        anyhow::bail!("unsupported pipeline version: {}", pipeline.version);
    }
    Ok(pipeline)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_pipeline() {
        let yaml = r#"
version: 1
name: test
stages:
  - id: echo
    run: echo ok
"#;
        let p: Pipeline = serde_yaml::from_str(yaml).unwrap();
        assert_eq!(p.stages.len(), 1);
        assert_eq!(p.stages[0].id, "echo");
    }
}
