# T-287: Rust 3D Game — Mês 3: Otimizações de Performance, Pacote CI/CD & Playtest Steam Deck

- **Status**: Backlog
- **Priority**: 🔵 Medium
- **Owner**: Antigravity
- **Epic**: Rust 3D Steam Game
- **Est**: 4w

## Context

Terceiro mês de desenvolvimento focado em estabilidade, empacotamento, compatibilidade e preparação para playtest. Otimização de renderização para garantir 60 FPS estáveis no Steam Deck (Linux/Proton), conteinerização do build para pipeline de CI/CD local e distribuição de uma build jogável fechada (Playtest Steam).

## Tasks

- [ ] Perfilamento de CPU/GPU com Tracy/cargo-flamegraph e otimizações de draw calls
- [ ] Validar compatibilidade nativa Linux/Proton e desempenho no Steam Deck (framerates estáveis)
- [ ] Criar Dockerfile de compilação multi-stage e pipeline no cluster para builds automatizados
- [ ] Empacotar instalador desktop executável final para Windows e Linux
- [ ] Configurar repositório e ramificações de build (beta branches) no painel Steamworks
- [ ] Lançar a primeira build fechada (Steam Playtest) e coletar telemetria inicial
