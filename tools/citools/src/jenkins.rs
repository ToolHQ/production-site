use serde::Serialize;

use crate::pipeline::Stage;

/// Resposta de `citools export-json` — manifesto completo para readJSON (Blue Ocean / plano).
#[derive(Debug, Serialize)]
pub struct ExportManifest {
    pub pipeline: String,
    pub version: u32,
    pub stages: Vec<ExportStage>,
}

#[derive(Debug, Serialize)]
pub struct ExportStage {
    pub id: String,
    #[serde(rename = "stageName")]
    pub stage_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub run: String,
    pub index: usize,
}

/// Resposta de `citools next --json` — um stage por chamada (Groovy: readJSON → stage(stageName)).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NextStage {
    pub done: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total: Option<usize>,
}

pub fn stage_display_name(stage: &Stage) -> String {
    if let Some(name) = &stage.stage_name {
        return name.clone();
    }
    humanize_id(&stage.id)
}

fn humanize_id(id: &str) -> String {
    id.split('-')
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                None => String::new(),
                Some(first) => {
                    let mut out = first.to_uppercase().to_string();
                    out.push_str(chars.as_str());
                    out
                }
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn export_stage(stage: &Stage, index: usize) -> ExportStage {
    ExportStage {
        id: stage.id.clone(),
        stage_name: stage_display_name(stage),
        description: stage.description.clone(),
        run: stage.run.clone(),
        index,
    }
}

pub fn next_done() -> NextStage {
    NextStage {
        done: true,
        id: None,
        stage_name: None,
        description: None,
        index: None,
        total: None,
    }
}

pub fn next_stage(stage: &Stage, index: usize, total: usize) -> NextStage {
    NextStage {
        done: false,
        id: Some(stage.id.clone()),
        stage_name: Some(stage_display_name(stage)),
        description: stage.description.clone(),
        index: Some(index),
        total: Some(total),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn humanize_id_dashes() {
        assert_eq!(humanize_id("verify-branch"), "Verify Branch");
    }
}
