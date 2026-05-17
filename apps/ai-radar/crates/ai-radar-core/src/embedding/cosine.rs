//! Cosine similarity helpers (**T-247**).

/// Cosine similarity in \[0, 1\] when vectors are non-zero; `None` if either norm is zero.
#[must_use]
pub fn cosine_similarity(a: &[f32], b: &[f32]) -> Option<f32> {
    if a.len() != b.len() || a.is_empty() {
        return None;
    }
    let mut dot = 0.0_f64;
    let mut na = 0.0_f64;
    let mut nb = 0.0_f64;
    for (x, y) in a.iter().zip(b) {
        let x = f64::from(*x);
        let y = f64::from(*y);
        dot += x * y;
        na += x * x;
        nb += y * y;
    }
    if na <= f64::EPSILON || nb <= f64::EPSILON {
        return None;
    }
    Some((dot / na.sqrt() / nb.sqrt()) as f32)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_vectors_score_one() {
        let v = vec![1.0, 0.0, 0.0];
        let s = cosine_similarity(&v, &v).unwrap();
        assert!((s - 1.0).abs() < 1e-5);
    }

    #[test]
    fn orthogonal_vectors_score_zero() {
        let a = vec![1.0, 0.0];
        let b = vec![0.0, 1.0];
        let s = cosine_similarity(&a, &b).unwrap();
        assert!(s.abs() < 1e-5);
    }
}
