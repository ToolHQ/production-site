//! Defensive HTML sanitization for collected content (**T-173**).
//!
//! Not a full HTML parser — strips obvious XSS vectors before persistence.

/// Strip dangerous URL schemes and inline event handlers from HTML-ish text.
#[must_use]
pub fn sanitize_html_fragment(input: &str) -> String {
    let without_scripts = strip_script_blocks(input);
    strip_dangerous_urls(&strip_event_handlers(&without_scripts))
}

fn strip_script_blocks(s: &str) -> String {
    let lower = s.to_ascii_lowercase();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if lower[i..].starts_with("<script") {
            if let Some(end) = lower[i..].find("</script>") {
                i += end + "</script>".len();
                continue;
            }
        }
        // SAFETY: we only advance `i` on UTF-8 char boundaries via `chars`.
        let ch = s[i..].chars().next().expect("char");
        let len = ch.len_utf8();
        out.push(ch);
        i += len;
    }
    out
}

fn strip_event_handlers(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_whitespace() || bytes[i] == b'>' {
            let start = i;
            i += 1;
            while i < bytes.len() && (bytes[i].is_ascii_whitespace() || bytes[i] == b'>') {
                i += 1;
            }
            if i + 2 < bytes.len() && bytes[i] == b'o' && bytes[i + 1] == b'n' {
                let name_end = s[i..]
                    .find(|c: char| c.is_whitespace() || c == '=' || c == '>')
                    .unwrap_or(s[i..].len());
                let name = &s[i..i + name_end];
                if name.chars().all(|c| c.is_ascii_alphanumeric()) && name.len() > 2 {
                    // skip `on*` attribute name
                    i += name_end;
                    while i < bytes.len() && bytes[i].is_ascii_whitespace() {
                        i += 1;
                    }
                    if i < bytes.len() && bytes[i] == b'=' {
                        i += 1;
                        while i < bytes.len() && bytes[i].is_ascii_whitespace() {
                            i += 1;
                        }
                        if i < bytes.len() {
                            let quote = bytes[i];
                            if quote == b'"' || quote == b'\'' {
                                i += 1;
                                while i < bytes.len() && bytes[i] != quote {
                                    i += 1;
                                }
                                if i < bytes.len() {
                                    i += 1;
                                }
                            } else {
                                while i < bytes.len()
                                    && !bytes[i].is_ascii_whitespace()
                                    && bytes[i] != b'>'
                                {
                                    i += 1;
                                }
                            }
                        }
                        continue;
                    }
                }
            }
            out.push_str(&s[start..i]);
        } else {
            let ch = s[i..].chars().next().expect("char");
            out.push(ch);
            i += ch.len_utf8();
        }
    }
    out
}

fn strip_dangerous_urls(s: &str) -> String {
    let mut out = s.to_string();
    for scheme in ["javascript:", "vbscript:", "data:text/html"] {
        out = replace_case_insensitive(&out, scheme, "");
    }
    out
}

fn replace_case_insensitive(haystack: &str, needle: &str, replacement: &str) -> String {
    let lower_hay = haystack.to_ascii_lowercase();
    let lower_needle = needle.to_ascii_lowercase();
    let mut result = String::with_capacity(haystack.len());
    let mut start = 0;
    while let Some(pos) = lower_hay[start..].find(&lower_needle) {
        let at = start + pos;
        result.push_str(&haystack[start..at]);
        result.push_str(replacement);
        start = at + needle.len();
    }
    result.push_str(&haystack[start..]);
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_script_tags() {
        let s = sanitize_html_fragment("<p>ok</p><script>alert(1)</script><p>x</p>");
        assert!(!s.to_ascii_lowercase().contains("<script"));
        assert!(s.contains("ok"));
    }

    #[test]
    fn strips_onclick_and_javascript_urls() {
        let s = sanitize_html_fragment(
            r#"<a href="javascript:alert(1)" onclick="evil()">x</a>"#,
        );
        assert!(!s.to_ascii_lowercase().contains("javascript:"));
        assert!(!s.contains("onclick"));
    }
}
