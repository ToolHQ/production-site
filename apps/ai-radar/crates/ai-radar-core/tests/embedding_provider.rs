//! Embedding provider and cosine tests (**T-247**).

use ai_radar_core::embedding::{
    cosine_similarity, build_embedding_provider, EmbedRequest, EmbeddingProvider, MockEmbeddingProvider,
};
use ai_radar_core::config::AppConfig;
use figment::Jail;

#[tokio::test]
async fn mock_embed_is_deterministic() {
    let p = MockEmbeddingProvider::new(8);
    let a = p
        .embed(EmbedRequest {
            input: "kubernetes observability".into(),
        })
        .await
        .unwrap();
    let b = p
        .embed(EmbedRequest {
            input: "kubernetes observability".into(),
        })
        .await
        .unwrap();
    assert_eq!(a.vector, b.vector);
    assert_eq!(a.dimensions, 8);
}

#[tokio::test]
async fn similar_text_has_higher_cosine_than_unrelated() {
    let p = MockEmbeddingProvider::new(16);
    let a = p
        .embed(EmbedRequest {
            input: "vector database for logs".into(),
        })
        .await
        .unwrap();
    let near = p
        .embed(EmbedRequest {
            input: "vector database logging".into(),
        })
        .await
        .unwrap();
    let far = p
        .embed(EmbedRequest {
            input: "chocolate cake recipe".into(),
        })
        .await
        .unwrap();
    let sim_near = cosine_similarity(&a.vector, &near.vector).unwrap();
    let sim_far = cosine_similarity(&a.vector, &far.vector).unwrap();
    assert!(sim_near > sim_far);
}

#[test]
fn factory_returns_noop_when_disabled() {
    Jail::expect_with(|jail| {
        jail.clear_env();
        jail.set_env("EMBEDDINGS_ENABLED", "false");
        let cfg = AppConfig::from_env().unwrap();
        let p = build_embedding_provider(&cfg);
        let rt = tokio::runtime::Runtime::new().unwrap();
        let err = rt
            .block_on(p.embed(EmbedRequest {
                input: "x".into(),
            }))
            .unwrap_err();
        assert!(err.to_string().contains("disabled"));
        Ok(())
    });
}
