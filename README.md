# Limites do Claude

App de barra do topo do macOS (SwiftUI) que mostra quanto da assinatura do Claude já foi usado: janela de 5 horas,
semana e os limites por modelo que a Anthropic devolver, com o horário de cada reset.

- **Na barra:** só um medidor colorido pela pior janela: verde abaixo de 80%, laranja de 80% a 94%, vermelho a partir
  de 95%, cinza sem dado.
- **Ao clicar:** cada janela com barra, porcentagem e "reseta sáb 23:00"; botão Atualizar (⌘R), "Abrir ao iniciar" e Sair (⌘Q).
- **Avisos:** uma notificação por janela ao cruzar 80% e outra em 95%, sem repetir até o reset.
- Atualiza a cada 2 minutos e ao acordar o Mac. Se a consulta falhar, mantém o último dado e explica o que houve.

## De onde vêm os números

Da mesma consulta que o `/usage` do Claude Code faz (`GET https://api.anthropic.com/api/oauth/usage`), com o login
do Claude Code deste Mac. **Não é uma API documentada**: se a Anthropic mudar, o app mostra o erro em vez de números
errados. A conta exibida é a que o Claude Code de terminal está logado; o subtítulo do painel mostra o plano dela
("Pessoal · Max", "Pessoal · Pro", "Team · nome da organização"), lido do `~/.claude.json`.

O token é o login que o Claude Code de terminal guarda no Chaveiro (`Claude Code-credentials`), lido por
`/usr/bin/security` a cada consulta, só em memória, nunca gravado nem registrado.

**Renovação:** o app de desktop do Claude não renova esse login; só o Claude Code de terminal renova, quando é usado.
Por isso, quando o login vence, o app roda `claude -p "Responda só: ok" --model haiku --no-session-persistence`
numa pasta temporária: o próprio Claude Code renova e grava no Chaveiro, do jeito oficial. Custa uma resposta mínima
do Haiku a cada poucas horas. O app nunca mexe em token.

O token de longa duração (`claude setup-token`) **não serve**: a Anthropic o recusa nesta consulta (testado em 21/10/2026).

Se a Anthropic responder "muitas consultas" (429), o app espera 10 minutos antes de tentar de novo.

## Instalar em outro Mac

Pré-requisitos:

1. **macOS 15** ou mais novo.
2. **Ferramentas de desenvolvedor da Apple**: `swift --version` precisa responder. Se não, rode `xcode-select --install`.
3. **Claude Code de terminal instalado e logado**: rode `claude` uma vez e entre na conta. O app de desktop do Claude
   sozinho não basta: o app lê o login do Claude Code de terminal e é ele que renova quando vence.
4. O app do Claude instalado é opcional (é de onde vem o asterisco do ícone).

Depois, clone o repositório (`git clone https://github.com/yanvrp/claude-usage-bar`) e rode o `scripts/empacotar.sh` **de onde clonou** (pelo GitHub Desktop, o padrão é
`<pasta do clone>/scripts/empacotar.sh`). Não passe o `.app` pronto por arquivo: o macOS bloqueia app não
assinado vindo de outro Mac; compilar no próprio Mac evita isso.

A renovação automática do login gasta uma resposta mínima do Haiku da cota da própria pessoa a cada poucas horas.
Testado com conta Max; com conta Team a consulta deve funcionar igual, mas não foi comprovado.

## Instalar ou atualizar

```bash
scripts/empacotar.sh
```

Compila em release, monta `build/Limites.app`, assina localmente (ad-hoc) e instala em `~/Applications`. Na primeira
consulta o macOS pergunta se `security` pode ler o item do Claude Code no Chaveiro: **Sempre permitir**. Ele também
pede permissão para notificações.

Testes da leitura da resposta: `swift test`. Log de cada consulta (`[limites] Xms status= janelas=`):
`log stream --predicate 'subsystem == "dev.yanrockenback.limites"'`.
