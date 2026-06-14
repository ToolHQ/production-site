use std::path::Path;

/// Glob mínimo: prefix `foo/**`, suffix `**/.py`, ou match exato.
pub fn path_matches_pattern(path: &str, pattern: &str) -> bool {
    let pattern = pattern.trim();
    if pattern.is_empty() {
        return false;
    }
    if let Some(prefix) = pattern.strip_suffix("/**") {
        return path == prefix || path.starts_with(&format!("{prefix}/"));
    }
    if let Some(suffix) = pattern.strip_prefix("**/") {
        return path.ends_with(suffix) || path.contains(&format!("/{suffix}"));
    }
    path == pattern
}

pub fn any_path_matches(patterns: &[&str], paths: &[String]) -> bool {
    paths
        .iter()
        .any(|p| patterns.iter().any(|pat| path_matches_pattern(p, pat)))
}

pub fn load_changed_paths(repo_root: &Path) -> Vec<String> {
    let file = repo_root.join(".citools-changed-paths");
    let Ok(raw) = std::fs::read_to_string(&file) else {
        return Vec::new();
    };
    raw.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(String::from)
        .collect()
}

pub fn paths_when_enabled(expr: &str, repo_root: &Path) -> bool {
    let patterns: Vec<&str> = expr
        .trim_start_matches("paths:")
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    if patterns.is_empty() {
        return true;
    }
    let file = repo_root.join(".citools-changed-paths");
    if !file.is_file() {
        return true;
    }
    let changed = load_changed_paths(repo_root);
    if changed.is_empty() {
        return false;
    }
    any_path_matches(&patterns, &changed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefix_glob() {
        assert!(path_matches_pattern("apps/foo/x.py", "apps/**"));
        assert!(!path_matches_pattern("tools/x", "apps/**"));
    }

    #[test]
    fn suffix_glob() {
        assert!(path_matches_pattern("apps/x.py", "**/.py"));
        assert!(path_matches_pattern("x.py", "**/.py"));
    }
}
