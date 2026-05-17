-- 0007_item_embeddings.up.sql — semantic vectors per extracted item (**T-247**).

CREATE TABLE IF NOT EXISTS ai_radar.item_embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    extracted_item_id UUID NOT NULL REFERENCES ai_radar.extracted_items (id) ON DELETE CASCADE,
    model TEXT NOT NULL,
    dimensions INT NOT NULL CHECK (dimensions > 0),
    vector JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT item_embeddings_extracted_model_uniq UNIQUE (extracted_item_id, model)
);

CREATE INDEX IF NOT EXISTS item_embeddings_extracted_idx
    ON ai_radar.item_embeddings (extracted_item_id);
