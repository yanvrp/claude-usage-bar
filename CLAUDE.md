# Limites — instruções locais deste repo

App de barra do topo do macOS em SwiftUI (Swift Package, sem projeto do Xcode). Complementa o `~/.claude/CLAUDE.md` global.

- Fonte dos dados: `api/oauth/usage` (a mesma do `/usage` do Claude Code). Não documentada: conferir os nomes dos campos
  no binário do Claude Code (`grep -a five_hour`) antes de mudar `Uso.swift`.
- Token: só o login do Claude Code no Chaveiro, via `/usr/bin/security`, só em memória, nunca logado. **Não implementar
  renovação de token** (rotacionar o refresh token por fora derruba o login do Claude Code): quando vence, o app roda um
  `claude -p` mínimo (Haiku, sem sessão, pasta temporária) e o próprio Claude Code renova. O app de desktop do Claude
  NÃO renova esse item. O token de `claude setup-token` é recusado pela consulta de uso (21/10/2026): não voltar a ele.
- Validar antes de entregar: `swift build -c release` sem avisos e `swift test`. Instalar com `scripts/empacotar.sh`.
- Commits terminam com `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
