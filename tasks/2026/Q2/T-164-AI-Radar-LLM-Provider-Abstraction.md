# T-164: AI Radar — LLM Provider Abstraction

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Trait `LlmProvider` desacoplando o sistema do provedor concreto. Default = **OpenRouter** (OpenAI-compatible, free tier disponível). Trocável via `LLM_BASE_URL` para Ollama, vLLM, ou qualquer endpoint OpenAI-compatible.

**Decisão explícita**: NÃO usar LiteLLM (recente supply-chain attack). Sistema deve operar com `LLM_ENABLED=false` em modo deterministic-only — LLM nunca é dependência rígida.

Modelos free OpenRouter sugeridos: `meta-llama/llama-3.3-70b-instruct:free`, `google/gemini-2.0-flash-exp:free`. Selecionar via `LLM_MODEL`.

## Tasks

- [ ] Trait `LlmProvider` async-trait em `ai-radar-core::llm` com `complete(req: CompletionRequest) -> Result<CompletionResponse>`
- [ ] Tipos: `CompletionRequest { system, user, max_tokens, temperature, json_mode }`, `CompletionResponse { content, prompt_tokens, completion_tokens, model, latency_ms }`
- [ ] `MockLlmProvider` retornando respostas pré-programadas por hash do prompt (testes)
- [ ] `OpenRouterProvider` falando com `https://openrouter.ai/api/v1/chat/completions`
- [ ] Headers OpenRouter: `Authorization: Bearer`, `HTTP-Referer`, `X-Title: ai-radar`
- [ ] Mapear erros HTTP → `LlmError::{Auth, RateLimited, Server, Timeout, Parse}`
- [ ] Suporte a `json_mode=true` (OpenAI `response_format: json_object`)
- [ ] `build_provider(cfg) -> Arc<dyn LlmProvider>` em `factory.rs` decidindo Mock/Real conforme `LLM_ENABLED`
- [ ] Wrapper retry com backoff exponencial (3 tries, 1/2/4s + jitter ±20%) apenas em `RateLimited`/`Server`
- [ ] Tracing span por request com `model`, `prompt_tokens`, `completion_tokens`, `latency_ms`
- [ ] Cálculo aproximado de custo (tabela hardcoded $/1M tokens) em log estruturado
- [ ] Testes: mock HTTP com `wiremock` cobrindo 200/401/429/500/timeout
- [ ] Documentar modelos free-tier OpenRouter no README com trade-offs

## DoD

- Com `LLM_ENABLED=true` + chave OpenRouter válida, chamada real funciona.
- Com `LLM_ENABLED=false`, factory retorna `NoOpProvider` que falha rápido com mensagem clara se `complete()` for chamada.
- Mock provider testável e determinístico.
- Retry funciona em 429/500 transientes; não retenta 4xx.
- Build com `LLM_BASE_URL=http://localhost:11434/v1` (Ollama) também funciona.
- Coverage testes ≥80%.

## Validação

```bash
cd apps/ai-radar
export LLM_ENABLED=true
export LLM_BASE_URL=https://openrouter.ai/api/v1
export LLM_API_KEY=sk-or-...
export LLM_MODEL=meta-llama/llama-3.3-70b-instruct:free

cargo test -p ai-radar-core --test llm_provider

# Smoke test manual (script ou repl)
cargo run -p ai-radar-cli -- llm-ping --prompt "say ok"
```

## References

- `docs/AI-RADAR-DECISIONS.md` — política LLM, modelos free
- `docs/AI-RADAR-ROADMAP.md` — Fase 6
- Depende de: **T-159**
- Branch sugerida: `feat/T-164-ai-radar-llm-provider`
