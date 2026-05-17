//! LLM extractor: prompt, schema, JSON parsing (**T-165**).

mod extract_once;
mod parse;
mod prompt;
mod quality;
mod schema;

pub use extract_once::{audit_entry, build_primary_user_message, llm_extract_with_retry};
pub use parse::{parse_extracted_fields, strip_json_fences};
pub use prompt::{extractor_id, EXTRACTOR_PROMPT_V1, EXTRACTOR_VERSION};
pub use quality::{assess_extract_quality, QualityReport, QualityTier};
pub use schema::ExtractedFields;
