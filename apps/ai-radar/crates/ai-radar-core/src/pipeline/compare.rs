//! Category comparison pipeline (**T-168**).

use crate::comparator::{CompareResult, Comparator};
use crate::db::Database;

/// Build, persist, and return a category comparison matrix.
///
/// # Errors
///
/// Propagates validation and repository failures from [`Comparator::compare`].
pub async fn run_compare(
    db: &Database,
    category: &str,
    top_n: usize,
) -> anyhow::Result<CompareResult> {
    Comparator.compare(db, category, top_n).await
}
