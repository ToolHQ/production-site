//! Rough USD estimates for structured logs (not billing).

/// Return an approximate total USD cost for a completion, if we know the model.
///
/// Free-tier `OpenRouter` models are tracked as `0.0`. Unknown models also return
/// `0.0` so logs never invent a non-zero price for unlisted tiers.
#[must_use]
pub fn approx_cost_usd(
    model: &str,
    prompt_tokens: Option<u32>,
    completion_tokens: Option<u32>,
) -> f64 {
    let Some(pt) = prompt_tokens else {
        return 0.0;
    };
    let ct = completion_tokens.unwrap_or(0);

    // Hardcoded list (T-164): adjust when pricing changes. `:free` models → 0.
    let (in_per_m, out_per_m): (Option<f64>, Option<f64>) = if model.contains(":free")
        || model.contains("llama-3.3-70b-instruct:free")
        || model.contains("gemini-2.0-flash-exp:free")
    {
        (Some(0.0), Some(0.0))
    } else if model.contains("gpt-4o-mini") {
        (Some(0.15), Some(0.60))
    } else {
        (None, None)
    };

    let Some(in_rate) = in_per_m else {
        return 0.0;
    };
    let out_rate = out_per_m.unwrap_or(in_rate);

    let pin = f64::from(pt) * in_rate / 1_000_000.0;
    let pout = f64::from(ct) * out_rate / 1_000_000.0;
    pin + pout
}
