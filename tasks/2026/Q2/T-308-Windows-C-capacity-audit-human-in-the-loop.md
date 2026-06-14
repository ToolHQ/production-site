# T-308: Windows C capacity audit human-in-the-loop

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

A máquina local mostrou `C:\` com **95%** de uso (`881G/931G`). O usuário deixou explícito que esta task deve ser feita com ele no loop antes de qualquer ação: primeiro analisar, depois sugerir, e só executar qualquer limpeza com confirmação explícita.

Esta task é deliberadamente diferente das remediações de cluster: não deve apagar, mover ou limpar nada automaticamente.

## Guardrail Obrigatório

Nenhuma ação destrutiva no Windows C sem confirmação humana específica. O agente pode coletar inventário e propor opções, mas o usuário decide o que mexer.

## Tasks

- [ ] Coletar inventário somente leitura de diretórios grandes (`Users`, `Windows`, `ProgramData`, caches de Docker/WSL se aplicável).
- [ ] Identificar candidatos por categoria: seguro limpar, precisa confirmar, não mexer.
- [ ] Checar consumo de WSL distributions, Docker Desktop, Cursor/VSCode caches, Downloads e backups locais.
- [ ] Apresentar plano com impacto estimado e risco de cada opção.
- [ ] Solicitar confirmação explícita antes de qualquer remoção.
- [ ] Documentar checklist local para recorrência futura.

## Validação

Somente leitura até aprovação:

```powershell
Get-PSDrive C
# inventário por diretório com Get-ChildItem/robocopy/listagem, sem Remove-Item
```

Critério de aceite: relatório de causas e plano aprovado pelo usuário antes de qualquer ação.
