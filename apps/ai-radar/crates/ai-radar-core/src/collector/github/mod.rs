//! GitHub REST collectors (`github_releases`, `github_repo`).

mod client;
mod collector;

pub use client::GitHubClient;
pub use collector::GithubCollector;
