//! Orchestration glue between collectors, repositories and CLI/CronJobs.

pub mod collect;
pub mod compare;
pub mod digest;
pub mod embed;
pub mod extract;
pub mod reprocess;
pub mod score;
pub mod search;
