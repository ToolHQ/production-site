# T-156: Dependabot Residual Cleanup (Tech Debt)

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Security / Tech Debt
- **Estimation**: 1d

## Context

Após a conclusão da mega-operação T-154, o repositório teve seu número de alertas no Dependabot reduzido em ~92%. No entanto, sobraram 13 vulnerabilidades de severidade média ou baixa (além do `arrow2` que foi documentado como high mas deprecado/restrito). 

Estas vulnerabilidades requerem atualizações majors, refatorações pesadas (ex: migrar de `arrow2` para `arrow`) ou têm impacto funcional que inviabilizou uma atualização rápida de minor/patch sem quebra de compatibilidade durante a T-154. Esta tarefa agrupa esses débitos técnicos residuais para serem trabalhados de forma pontual no backlog.

## Escopo Residual

- HIGH: `arrow2` (rust) - Arrow2 allows out of bounds access in public safe API. *Requer refatoração massiva de `parquet_convert.rs`.*
- MEDIUM: `vite` (npm) - Vite Vulnerable to Path Traversal in Optimized Deps `.map` Handling
- MEDIUM: `esbuild` (npm) - esbuild enables any website to send any requests to the development server and read the response
- MEDIUM: `uuid` (npm) - uuid: Missing buffer bounds check in v3/v5/v6 when buf is provided
- MEDIUM: `python-dotenv` (pip) - python-dotenv: Symlink following in set_key allows arbitrary file overwrite via cross-device rename fallback
- MEDIUM: `brace-expansion` (npm) - brace-expansion: Zero-step sequence causes process hang and memory exhaustion
- MEDIUM: `bytes` (rust) - bytes has integer overflow in BytesMut::reserve
- MEDIUM: `sqlx` (rust) - SQLx Binary Protocol Misinterpretation caused by Truncating or Overflowing Casts
- LOW: `rand` (rust) - Rand is unsound with a custom logger using rand::rng()
- LOW: `rand` (rust) - Rand is unsound with a custom logger using rand::rng()
- LOW: `brace-expansion` (npm) - brace-expansion Regular Expression Denial of Service vulnerability
- LOW: `tracing-subscriber` (rust) - Tracing logging user input may result in poisoning logs with ANSI escape sequences
- LOW: `lexical-core` (rust) - lexical-core has multiple soundness issues

## Tasks

- [ ] Analisar esforço para migração de `arrow2` para Apache `arrow`
- [ ] Atualizar dependências `vite` e `esbuild` no projeto `react-static` (T-155 já converteu pra Vite, revisar upgrades major disponíveis)
- [ ] Atualizar stack `rust` (sqlx, bytes, rand, tracing-subscriber) com bump seguro de cargo
- [ ] Revisar as exceções pip e utilitários npm menores
