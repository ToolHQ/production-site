---
name: git-history-redaction
description: Procedimentos de segurança para remoção de chaves e segredos vazados no histórico do Git.
---

# Git History Redaction (Saneamento de Histórico)

Este documento define a Skill padrão para reescrever o histórico do Git com o objetivo de dar `redact` (mascarar) chaves, tokens, senhas ou arquivos sensíveis expostos em commits anteriores, sem corromper metadados importantes como data, autor e mensagens dos commits.

---

## ⚠️ Pre-Flight & Riscos

1. **Reescrita de Hashes**: A execução desta ferramenta alterará o identificador único (hash SHA) de todos os commits a partir do primeiro ponto de alteração.
2. **Branches Ativos**: Todo trabalho local pendente e não-commitado em qualquer worktree local do projeto **deve** ser enviado ao GitHub (`git push`) antes de iniciar.
3. **Bloqueio de Redação Local**: O `git-filter-repo` se recusa a rodar se houver worktrees ativas vinculadas ao diretório atual ou se o repositório não for um clone limpo. Por segurança, use o **Método de Clone Temporário**.

---

## 🚀 Método Recomendado: Clone Temporário (Seguro)

### 1. Preparação
Crie um clone fresco do repositório em uma pasta temporária (fora do workspace de trabalho ativo para não interferir nas worktrees):
```bash
git clone git@github.com:ToolHQ/production-site.git /home/dnorio/production-site-redact-temp
cd /home/dnorio/production-site-redact-temp
```

### 2. Instalação do git-filter-repo
Instale o utilitário através do pip local:
```bash
pip install --user git-filter-repo
```
*(Certifique-se de que `~/.local/bin` está no seu `$PATH` ou chame como `python3 -m git_filter_repo`)*.

### 3. Configuração das Substituições
Crie um arquivo de texto simples chamado `expressions.txt` contendo os segredos a serem substituídos, no formato:
```text
valor_sensivel_original==>[SUBSTITUTO_DESEJADO]
```

Exemplo:
```text
[REDACTED_GOOGLE_API_KEY]==>[REDACTED_GOOGLE_API_KEY]
[REDACTED_MAXMIND_LICENSE_KEY]==>[REDACTED_MAXMIND_LICENSE_KEY]
```

### 4. Execução do Saneamento
Rode o comando especificando o arquivo de expressões:
```bash
git-filter-repo --replace-text expressions.txt --force
```
O `git-filter-repo` varrerá recursivamente cada branch, tag, arquivo e commit histórico substituindo as chaves correspondentes pelo texto mascarado.

### 5. Force-Push para o GitHub
Após a reescrita local ser concluída com sucesso, reconecte o remote do GitHub e envie as novas referências:
```bash
git remote add origin git@github.com:ToolHQ/production-site.git
git push origin --force --all
git push origin --force --tags
```

### 6. Limpeza do Ambiente Temporário
```bash
cd ~
rm -rf /home/dnorio/production-site-redact-temp
```

---

## 🔄 Re-sincronização de Workspaces Locais

Após o force-push do novo histórico, as worktrees e repositórios locais antigos estarão apontando para commits cujos hashes não batem com a `main` do remoto.

Execute as seguintes etapas no workspace principal (`/home/dnorio/production-site-antigravity`):

1. **Remover Worktrees antigas**:
   ```bash
   git worktree remove /home/dnorio/production-site-copilot
   git worktree remove /home/dnorio/production-site-cursor
   git worktree remove /home/dnorio/production-site-opencode
   git worktree remove /home/dnorio/production-site-rust-rover-claude
   ```
2. **Atualizar Repositório Base**:
   ```bash
   git fetch origin
   git reset --hard origin/main
   ```
3. **Recriar as Worktrees** apontando para as branches remotas atualizadas:
   ```bash
   git worktree add /home/dnorio/production-site-copilot origin/feat/copilot-self-hosted-runners-migration
   git worktree add /home/dnorio/production-site-cursor origin/feat/T-270-llm-models-pricing-monitor
   git worktree add /home/dnorio/production-site-opencode origin/feat/opencode-agent-3
   ```
