# Monitor — checagem via TOTVS Broker + dashboard web + config Ortobom

**Data:** 2026-09-30
**Status:** aprovado em brainstorming, pronto para `writing-plans`

## Objetivo

Repaginar o monitor pra:

1. Trocar a origem da lista de unidades — hoje vem de um `.ini` do
   SmartClient (`iniPath` + `GetPvProfString`) — por uma lista 100%
   parametrizável em `config.json` (nome + host + porta por unidade,
   sem depender de nenhum arquivo externo do Windows).
2. Trocar a checagem HTTP genérica (`GET /`) pelo endpoint real do
   TOTVS Broker (`GET /totvs_broker_query`), que devolve uma página
   HTML com sessões ativas, conexões ativas e a tabela de servers do
   broker — e **interpretar** esse HTML em vez de só olhar o status
   code.
3. Adicionar um novo tipo de alerta: server individual da tabela do
   broker entrando/saindo de quarentena/desabilitado/bloqueado por
   escalabilidade — além do alerta já existente de broker inteiro
   cair/voltar.
4. Consolidar tudo (broker de cada unidade + dbaccess + license
   server) num **dashboard web local**, servido pelo próprio
   `MonitorService` (mesmo processo de fundo que já faz as
   checagens), acessível de qualquer navegador na rede.
5. `config.example.json` do repositório passa a vir pré-preenchido
   com o ambiente real da Ortobom (as 13 unidades de produção
   extraídas do bookmarks fornecido) — o código continua genérico e
   reutilizável por qualquer cliente, só o exemplo de configuração
   muda.

Roda em Linux e Windows (o binário já é cross-platform desde o plano
anterior, `docs/superpowers/plans/2026-09-05-monitor-multiplataforma.md`,
já implementado — esta spec não mexe nisso).

## Fora de escopo (decidido em brainstorming)

- Ambiente de Homologação (porta 1201) — só Produção entra no
  `config.example.json` desta rodada. Formato já é 100% parametrizável,
  então adicionar Homologação depois é só editar o JSON, sem mudança
  de código.
- dbaccess / license server: lógica de checagem **sem mudança** —
  só passam a aparecer também no dashboard consolidado, e dbaccess
  passa a pegar o host direto do objeto da unidade (não mais do
  `.ini`, que deixa de existir).
- GUI desktop nativa (Fyne) e mudanças no `MonitorTUI`/painel de
  console — ficam como estão. O dashboard novo é web, servido pelo
  `MonitorService`.
- Fork/branch dedicado pra Ortobom — não existe; é o mesmo repositório
  genérico, só o `config.example.json` reflete o ambiente Ortobom.

## Decisão de dependência: bump do `ADVPP_VERSION`

O dashboard depende de `WSRestServer` devolver HTML cru (via
`Return {"__RAW_HTTP__", cContentType, cBody}`), recurso que só existe
a partir da tag `v4.2.0` do compilador AdvPP — o projeto está pinado em
`v3.0.4` hoje. **Decisão (confirmada com o operador): bump de
`ADVPP_VERSION` para `v4.2.1`** (última tag estável, um ajuste
incremental sobre `v4.2.0` que não afeta este projeto). Isso muda
`ADVPP_VERSION` (usado pela CI pra fazer checkout do compilador certo)
e não deve quebrar nada do código existente — `FWHttpGet`/`FWHttpBody`/
`WSRestServer`/`StartJob` já existiam antes de `v3.0.4`.

## Config — schema novo

`config.example.json` (Ortobom, produção):

```json
{
  "unidades": [
    {"nome": "ORTOSP", "host": "10.0.100.62", "porta": 8090},
    {"nome": "ORTORJ", "host": "10.0.100.53", "porta": 8090},
    {"nome": "ORTOMG", "host": "10.0.100.64", "porta": 8090},
    {"nome": "ORTOGO", "host": "10.0.100.85", "porta": 8090},
    {"nome": "ORTOMT", "host": "10.0.100.26", "porta": 8090},
    {"nome": "ORTOBA", "host": "10.0.100.67", "porta": 8090},
    {"nome": "ORTOPE", "host": "10.0.100.58", "porta": 8090},
    {"nome": "ORTOCE", "host": "10.0.100.59", "porta": 8090},
    {"nome": "ORTOPR", "host": "10.0.100.60", "porta": 8090},
    {"nome": "ORTOPA", "host": "10.0.100.61", "porta": 8090},
    {"nome": "ORTORS", "host": "10.0.100.115", "porta": 8090},
    {"nome": "ORTOAF", "host": "10.0.100.54", "porta": 8090},
    {"nome": "ORTOAM", "host": "10.0.100.36", "porta": 8090}
  ],
  "intervaloSegundos": 60,
  "timeoutMs": 3000,
  "dashboardPorta": 9099,
  "telegramBotToken": "COLOQUE_O_TOKEN_DO_BOT_AQUI",
  "telegramChatId": "COLOQUE_O_CHAT_ID_AQUI",
  "portaDbaccess": 1234,
  "licenseServer": {"host": "10.0.200.98", "port": 5555}
}
```

Mudanças de contrato vs. hoje:

- **Removido:** `iniPath`, `portaWebapp` (globais).
- **`unidades`** deixa de ser array de strings (nome de seção `.ini`)
  e vira array de objetos `{nome, host, porta}`. Adicionar/remover uma
  unidade, ou mudar IP/porta de uma existente, é só editar essa lista
  — sem tocar em código nem em `.ini`.
- **Novo:** `dashboardPorta` (porta HTTP local do dashboard web,
  obrigatória — sem ela o `MonitorService` não sobe o dashboard, loga
  aviso e segue rodando só as checagens, não é fatal).
- `intervaloSegundos`, `timeoutMs`, `telegramBotToken`,
  `telegramChatId`, `portaDbaccess`, `licenseServer` — sem mudança.

## Checagem do broker — parser do HTML

Endpoint: `GET http://<host>:<porta>/totvs_broker_query`. `UP` continua
sendo "HTTP respondeu com status < 500" (mesma regra de hoje), mais uma
checagem de sanidade: o corpo contém a string `"TOTVS Broker para
HTTP"` (se o host responder algo mas não for realmente o broker,
conta como erro de parse, não como UP silencioso com dados zerados).

Sem nativa de regex disponível no AdvPP — extração via `At()`/`SubStr()`
sobre âncoras de texto fixas que o broker sempre gera (mesmo raciocínio
de scraping usado em `advpl-specialist`, mas aqui é o único caminho
disponível). Fixture real (colada pelo operador, broker v24.3.1.9,
5 servers, nenhum fora do estado normal) vira o teste de referência:

```
Existem 59 sessões ativas no momento.
Existem 175 conexões ativas no momento.
Versão 24.3.1.9 guapor lin64 rel 0b4bfda  Jul 15 2026 13:29:54
Servers (5)
<tr><td>(   1) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1236">10.0.100.115:1236</a></td><td>    11</td>...
```

`MonParseBrokerHtml(cHtml)` devolve um `JsonObject`:

```json
{
  "SESSOESATIVAS": 59,
  "CONEXOESATIVAS": 175,
  "VERSAO": "24.3.1.9 guapor lin64 rel 0b4bfda",
  "SERVERS": [
    {"HOSTPORTA": "10.0.100.115:1236", "SESSOES": 11, "CONEXOES": 33,
     "USUARIOS": 25, "THREADS": 65, "MEMORIAKB": 4087092, "CPU": 37,
     "UPTIME": "2026/09/30 03:10:02", "PID": 3259754, "STATUS": "OK"}
  ]
}
```

`STATUS` de cada server: `"OK"` por padrão; vira `"DESABILITADO"`,
`"QUARENTENA"` ou `"BLOQUEADO_ESCALABILIDADE"` se a linha da tabela
(`<tr>`) contiver, em qualquer `<td>`, a classe CSS `isDisabled`,
`inQuarantine` ou `isBlockedByScalability` respectivamente (nomes das
classes documentados no `<style>` da própria página do broker).

**Gap conhecido, não verificado (marcar como 🟡 INFERIDO na
implementação):** a fixture colada não tem nenhum exemplo real de
server em quarentena/desabilitado/bloqueado — a lógica de detecção da
classe CSS é uma inferência razoável a partir do stylesheet, mas só
fica confirmada contra o comportamento real do broker quando alguém
observar (ou provocar) esse estado num ambiente de verdade. Documentar
isso no README como limitação conhecida até validação.

## Alerta granular por server

Chave de estado: `<UNIDADE>_SERVER_<hostporta>` (ex:
`ORTOSP_SERVER_10.0.100.62:1236`), mesmo mecanismo de
`MonProcessarResultado` já existente (só dispara Telegram quando o
status muda, evita spam a cada ciclo). Mensagem:

- Entrou em quarentena/desabilitado/bloqueado: `[ALERTA] ORTOSP
  server 10.0.100.62:1236 entrou em <STATUS>`
- Voltou a `OK`: `[OK] ORTOSP server 10.0.100.62:1236 voltou a OK`

## Dashboard web

- `MonitorService` inicia, via `StartJob("MonServirDashboard", .F.,
  {oConfig["dashboardPorta"]})` (assíncrono — não bloqueia o loop de
  checagem), um `WSRestServer` com uma rota `GET /` que lê
  `dashboard.json` (escrito pelo loop principal a cada ciclo,
  caminho relativo igual a `state.json`/`monitor.log`) e devolve HTML
  puro via `Return {"__RAW_HTTP__", "text/html", cHtml}`.
- `dashboard.json`: snapshot do último ciclo — timestamp, e por
  unidade: nome, host:porta, up/down, latência, sessões ativas,
  conexões ativas, lista de servers com status; mais dbaccess (se
  configurado) e license server (se configurado). Sobrescrito
  inteiro a cada ciclo (mesmo padrão de `MonSaveState`).
- Página HTML: uma tabela por unidade — sem framework JS, sem CSS
  externo (uma tag `<style>` inline básica, verde/vermelho por
  status) — recarrega via `<meta http-equiv="refresh"
  content="<intervaloSegundos>">` (polling simples do navegador, sem
  WebSocket/JS de fetch — YAGNI: é um dashboard de operação interna,
  não precisa de tempo real).
- Se `dashboardPorta` não estiver no config: loga aviso e não sobe o
  dashboard — resto do monitor funciona normalmente (checagens +
  Telegram), igual já acontece hoje com `portaDbaccess`/`licenseServer`
  ausentes.

## Testes

- `tests/monitor_lib_test.prw`: novos testes de `MonParseBrokerHtml`
  usando a fixture real colada nesta spec como string literal
  (broker saudável, 5 servers, todos `OK`) — assere
  `SESSOESATIVAS=59`, `CONEXOESATIVAS=175`, `Len(SERVERS)=5`,
  primeiro server `HOSTPORTA="10.0.100.115:1236"`, `STATUS="OK"`.
  Sem fixture real de server em quarentena/desabilitado disponível —
  a lógica de detecção de classe CSS ganha um teste com HTML
  sintético (`<tr><td class='inQuarantine'>...`) construído à mão,
  marcado no comentário do teste como cobertura da lógica de parsing,
  não como validação contra o broker real.
- Testes existentes de `MonCheckWebapp`/fluxo `.ini` são removidos ou
  adaptados pro novo `MonCheckBroker` (host/porta direto, sem
  `GetPvProfString`).
- `MonServirDashboard`/geração de `dashboard.json` e do HTML: teste
  de que o JSON é escrito com as chaves esperadas após um ciclo, e
  que a função que monta o HTML (separada da que sobe o servidor,
  testável sem rede) produz uma tabela com uma linha por unidade.

## Self-review

- **Placeholders:** nenhum. Todas as decisões (endpoint, schema,
  dependência, escopo) vêm de respostas explícitas do operador nesta
  sessão.
- **Consistência:** `dashboardPorta` é a única chave nova
  verdadeiramente obrigatória-mas-não-fatal (mesmo padrão de
  `portaDbaccess`/`licenseServer` — ausência não impede o resto de
  funcionar). `unidades` muda de tipo (string → objeto) de forma
  consistente em todos os consumidores (`MonitorMain`, dbaccess,
  dashboard).
- **Gap explícito:** detecção de status de server individual
  (quarentena/desabilitado/bloqueado) é 🟡 INFERIDA do CSS, não
  confirmada contra um caso real — documentado acima e no README como
  limitação conhecida, não escondido.
