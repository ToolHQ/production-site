//! Strip markdown fences and deserialize [`super::schema::ExtractedFields`].

use super::schema::ExtractedFields;

/// Remove optional ``` / ```json wrappers and trim whitespace.
#[must_use]
pub fn strip_json_fences(text: &str) -> String {
    let t = text.trim();
    if !t.starts_with("```") {
        return t.to_string();
    }
    let without_first = t
        .strip_prefix("```json")
        .or_else(|| t.strip_prefix("```JSON"))
        .unwrap_or_else(|| t.strip_prefix("```").unwrap_or(t));
    let body = without_first.trim_start();
    // Drop closing fence line if present.
    if let Some(pos) = body.rfind("```") {
        body[..pos].trim().to_string()
    } else {
        body.to_string()
    }
}

/// Parse model output into [`ExtractedFields`].
///
/// # Errors
///
/// Returns a short diagnostic when JSON is missing or does not match the schema.
pub fn parse_extracted_fields(text: &str) -> Result<ExtractedFields, String> {
    let cleaned = strip_json_fences(text);
    serde_json::from_str::<ExtractedFields>(&cleaned).map_err(|e| format!("serde_json: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_object() {
        let j = r#"{"tool_name":"curl","category":"cli"}"#;
        let f = parse_extracted_fields(j).expect("ok");
        assert_eq!(f.tool_name.as_deref(), Some("curl"));
        assert_eq!(f.category.as_deref(), Some("cli"));
    }

    #[test]
    fn strips_json_fence() {
        let j = "```json\n{\"tool_name\":\"x\"}\n```";
        let f = parse_extracted_fields(j).expect("fence");
        assert_eq!(f.tool_name.as_deref(), Some("x"));
    }

    #[test]
    fn rejects_plain_text() {
        let err = parse_extracted_fields("not json").expect_err("fail");
        assert!(err.contains("serde_json"), "{err}");
    }
}
