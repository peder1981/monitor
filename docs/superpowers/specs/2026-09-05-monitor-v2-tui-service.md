# Monitor v2 — checagem via webapp, latência, TUI e serviço de fundo

## Contexto

A v1 (já em produção, commits até `d97d099`) monitora appserver via TCP
puro na porta do broker SmartClient (lida de um `.ini` de conexão),
mais dbaccess e license server, com alerta no Telegram só na borda
(mudança de estado). Roda como um único loop (`monitor.prw`), sem
interface, disparado via Task Scheduler.

Isso muda porque o ambiente está migrando: a grande maioria das
unidades passa a rodar Protheus 12.1.2510 acessado só via navegador,
numa porta HTTP fixa (8090/webapp) — o broker TCP do SmartClient deixa
de ser o jeito certo de checar se o appserver está de pé. Ao mesmo
tempo, surgiram três requisitos novos: medir não só se está no ar mas
**quanto tempo demora pra responder**; ter uma interface que qualquer
usuário logado por RDP consiga operar sem terminal aberto no colo;  e
o monitoramento não pode parar quando a interface fecha.

Duas alternativas foram exploradas e descartadas ao longo da
conversa que gerou esta spec — registradas aqui porque a decisão em si
é informação, não só o resultado:

- **GUI desktop (Fyne)**: tecnicamente viável (o `advplc build --gui`
  gera uma janela nativa de verdade, como o projeto irmão `GesCon` já
  prova), mas o operador decidiu que o ganho não compensava a
  dependência extra (Fyne mesmo não usado em runtime ainda pesa no
  binário) frente ao valor entregue.
- **Windows Service registrado no SCM** (via NSSM ou wrapper próprio):
  descartado por ora como complexidade desnecessária. Vira item de
  roadmap do **compilador** (não deste projeto) — ver
  `~/Projetos/AdvPP/ROADMAP.md`, seção "Suporte nativo a Windows
  Service" — pra quando fizer sentido investir nisso. Por enquanto, um
  processo em segundo plano disparado no boot (Task Scheduler) e/ou
  por um comando da TUI já resolve.

## Decisão de arquitetura

Dois programas AdvPL, compilados via CI (GitHub Actions, runner
`windows-latest`, mesmo pipeline do `GesCon`) em dois `.exe`
autocontidos — a máquina que roda o monitor nunca precisa instalar
MinGW nem nenhum toolchain, só baixar os `.exe` já prontos do release:

- **`MonitorService.exe`** (de `src/monitor.prw`): o loop de checagem,
  sem interface nenhuma. Continua sendo disparado pelo Task Scheduler
  ("ao iniciar o sistema") — isso já garante que sobrevive a reboot e
  a troca de sessão RDP, sem precisar de um Windows Service de verdade
  registrado no SCM.
- **`MonitorTUI.exe`** (de `src/monitor_tui.prw`): painel interativo em
  ASCII, rodado dentro de um console (cmd/PowerShell) sempre que um
  usuário RDP quiser configurar, ver status, ou ligar/desligar o
  `MonitorService`.

Os dois só se comunicam por arquivo compartilhado
(`config.json`/`state.json`/`monitor.log`) — sem porta nova, sem API
nova entre eles. Isso é uma continuação direta do que já existia: a
v1 já usava esses três arquivos, a v2 só adiciona um segundo programa
que também os lê/escreve.

**Por que TUI, não GUI**: o AdvPP já expõe primitivas de terminal reais
(`UiBox`, `UiStreamBox`/`UiStreamReset` para redesenhar por cima sem
piscar, `UiMarkdown`, `ConOutRaw`) construídas sobre bibliotecas Go
puras (`lipgloss`/`glamour`, sem cgo), e o modo `run`/`build` já anexa
um provider de terminal real para `FWGetText`/`FWMenuSelect`
(confirmado lendo `cmd/advplc/main.go`). Ou seja: dá pra ter uma
interface interativa de verdade — caixas, tabela de status ao vivo,
formulário de configuração — inteiramente em ASCII, sem precisar de
Fyne/cgo em lugar nenhum do runtime (só o `stub_template.go` do
`advplc build` embute Fyne por padrão, no binário, mas ele nunca é
exercitado se o bytecode não chama nenhuma função de UI gráfica — o que
é o caso aqui).

**Pegadinha documentada**: como `MonitorTUI.exe` chama
`FWGetText`/`FWMenuSelect`, ele só renderiza como console se for
aberto **de dentro de um terminal de verdade** (stdin é um TTY). Aberto
por duplo-clique no Explorer (sem console anexado), o AdvPP entende que
deve abrir uma janela Fyne por trás — comportamento correto do
compilador, mas indesejado aqui. Mitigação: o release inclui um atalho
(`.bat` ou `.lnk`) que abre um `cmd.exe` e chama `MonitorTUI.exe` de
dentro dele, e o `README` documenta "nunca abra o `.exe` direto".
`MonitorService.exe` não usa nenhuma dessas funções — não corre esse
risco, roda console sempre, com ou sem TTY.

## Checagens (o que muda por tipo de serviço)

- **Appserver**: `HTTP GET` no host da unidade (continua lido do
  `.ini` do SmartClient, seção `TCP<UF>`, campo `Server=` — esse
  arquivo continua existindo e sendo a fonte do host mesmo com o
  cliente migrando pra navegador) na porta fixa `portaWebapp` (nova
  chave do `config.json`, ex. `8090`). Mede status (responde ou não,
  status HTTP < 500 conta como "up") **e o tempo de resposta em ms**.
  Substitui por completo a checagem TCP antiga (porta do broker
  SmartClient, tipicamente 4000) — não fica como opção paralela.
- **Dbaccess**: sem mudança — TCP puro, mesmo host do appserver
  (lido do mesmo jeito), porta de `portaDbaccess` no config.
- **License Server**: sem mudança — TCP puro, centralizado
  (`licenseServer.host`/`licenseServer.port`), uma checagem por ciclo.
- Não existe endpoint de "health" nativo no Protheus (confirmado via
  pesquisa na base RAG local) — por isso o HTTP GET do appserver é
  deliberadamente simples (só "respondeu ou não, e em quanto tempo"),
  sem tentar interpretar o conteúdo da resposta.
- Métricas internas de verdade do AppServer (conexões ativas, threads)
  exigiriam uma rotina AdvPL rodando **dentro** de um ambiente real
  (via `GetUserInfoArray()`) — fora do escopo desta v2, registrado
  como ideia futura na memória cross-agent (mem0), não nesta spec.

## Config e estado

`config.json` ganha `portaWebapp` (número, porta HTTP fixa do webapp,
aplicada a todas as unidades). As demais chaves (`iniPath`,
`intervaloSegundos`, `timeoutMs`, `telegramBotToken`,
`telegramChatId`, `unidades`, `portaDbaccess`, `licenseServer`)
continuam como estão.

`state.json` ganha a latência ao lado do status, mas **sem aninhar
objeto** — testado e confirmado que `JsonObject:ToJson()` não serializa
um `JsonObject` aninhado como valor (vira a string literal
`"Object:JsonObject"`, perdendo os dados; achado durante a escrita do
plano, antes de qualquer código ser escrito). Formato real: uma
segunda chave paralela por unidade, `"<CHAVE>_LATENCIA"`, guardando o
número de ms:

```json
{"TCPSP": "UP", "TCPSP_LATENCIA": 842, "LICENSE_SERVER": "DOWN", "LICENSE_SERVER_LATENCIA": 3000}
```

`MonGetStatusAnterior`/o formato de status em si não mudam. Sem
migração de formato antigo — é gerado pelo próprio monitor, o próximo
ciclo já escreve a chave de latência que ainda não existir.

## Interface (`MonitorTUI.exe`)

Tela principal: uma tabela em ASCII (via `UiBox`/`UiStreamBox`,
redesenhada no lugar a cada N segundos, sem piscar) com uma linha por
unidade/serviço — nome, status (UP/DOWN com cor), última latência,
horário da última mudança de estado. Um rodapé com atalhos de teclado
para: **C**onfigurar (formulário via `FWGetText`/`FWMenuSelect` editando
o `config.json`), **I**niciar `MonitorService.exe` (processo
desanexado — ver adiante), **P**arar (`taskkill`), **L**og (últimas
linhas de `monitor.log`), **Q**uit.

**Iniciar/Parar sem travar a TUI**: nem `WaitRun` nem `ProcRun` do
AdvPP suportam disparar um processo e devolver o controle na hora — os
dois bloqueiam até o processo filho terminar, o que travaria a TUI
para sempre num loop infinito. Solução: invocar
`WaitRun("cmd /c start MonitorService.exe")` — o `start` do `cmd.exe`
é quem cria o processo desanexado e devolve o controle imediatamente;
o `WaitRun` só espera o `cmd.exe` (que retorna na hora), não o processo
filho. Parar usa `WaitRun("taskkill /IM MonitorService.exe /F")`, pelo
mesmo motivo (retorna assim que o pedido de término é aceito). Status
("está rodando?") é checado listando processos (`tasklist`) redirecionado
a um arquivo temporário e lido de volta com `MemoRead` — evita precisar
de qualquer native nova no AdvPP.

## Fora de escopo desta v2

- Suporte a unidades ainda no SmartClient/2310 (checagem TCP antiga) —
  o operador confirmou que todas migram, então esse caminho é
  removido, não mantido como fallback configurável.
- Windows Service real (SCM) — vira item de roadmap do AdvPP.
- Métricas internas do AppServer (conexões, threads, memória) via
  `GetUserInfoArray()` — precisaria de uma rotina publicada dentro do
  RPO real; registrado como ideia futura, não implementado agora.
- Gráfico de linha/série temporal de latência — a TUI mostra o valor
  atual e (se fizer sentido depois) uma média simples, não uma série
  histórica plotada.
