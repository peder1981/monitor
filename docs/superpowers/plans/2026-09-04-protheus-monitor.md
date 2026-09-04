# Monitor de Disponibilidade das Unidades Protheus — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir `monitor.exe` — um executável AdvPL standalone (compilado com o AdvPP) que roda numa máquina Windows separada, vigia o broker TCP de cada unidade Protheus listada num `.ini` de SmartClient já existente, e avisa no Telegram só quando uma unidade cai ou volta.

**Architecture:** Um arquivo de lógica reutilizável (`monitor_lib.prw`, sem loop, sem I/O bloqueante além do necessário) incluído via `#include` tanto pelo programa principal (`monitor.prw`, que só faz o loop `Sleep`/chamada) quanto pelo arquivo de teste (`monitor_lib_test.prw`), seguindo o padrão já usado nos testes do próprio AdvPP (arquivos `.prw` chamados com `advplc run`, saída lida via `ConOut`).

**Tech Stack:** AdvPL rodando no interpretador/compilador AdvPP (`~/Projetos/AdvPP`, binário `advplc`). Nativas usadas: `GetPvProfString` (ler `.ini`), `PING` (TCP connect real), `JsonObject` (`FromJson`/`ToJson`/acesso por colchete), `MemoRead`/`MemoWrite` (arquivos pequenos), `FOpen`/`FCreate`/`FSeek`/`FWrite`/`FClose` (append de log), `FWHttpPost` (Telegram), `Sleep`, `Try/Catch/Throw`.

**Spec:** `docs/superpowers/specs/2026-09-04-protheus-monitor-design.md`

## Global Constraints

- Nenhuma dependência nova além do que o AdvPP já embute nativamente (sem libs externas, sem outro compilador).
- Lista de unidades a vigiar fica em `config.json`, editável à mão — nunca hardcoded no `.prw` e nunca via regex tentando adivinhar UF.
- Alerta no Telegram só na borda (mudança de estado), nunca a cada ciclo — ver spec, seção "Alertas: só na borda".
- Escopo desta v1: só o broker TCP (`appserver`) de cada unidade. Dbaccess e License Server ficam fora (ver spec, "Fora de escopo").
- Todo arquivo `.prw` de teste roda com `advplc run <arquivo>.prw` (a partir de `~/Projetos/AdvPP`, usando `--include` para achar os arquivos do projeto monitor) e a verificação é lida via `ConOut` (mesma convenção dos testes existentes em `AdvPP/tests/*.prw`) — sem framework de asserção, sem mock de rede real.

---

## Arquivos deste projeto

```
monitor/
  src/
    monitor_lib.prw       # funções puras: ler ini, checar unidade, estado, log, notificar
    monitor.prw           # entry point: loop infinito, usa monitor_lib.prw
  tests/
    monitor_lib_test.prw  # self-check das funções de monitor_lib.prw
  config.example.json     # modelo de config.json para copiar na máquina Windows
  README.md               # como compilar e rodar
```

---

### Task 1: Checagem de unidade via `.ini` do SmartClient + PING TCP

**Files:**
- Create: `src/monitor_lib.prw` (só a função desta task por enquanto)
- Test: `tests/monitor_lib_test.prw`

**Interfaces:**
- Produces: `User Function MonCheckUnidade(cUnidade, cIniPath, nTimeoutMs) -> oResultado`
  onde `oResultado` é um `JsonObject` com as chaves `UNIDADE` (string), `HOST` (string), `PORT` (numeric), `UP` (logical), `ERRO` (string, `""` se sem erro).

- [ ] **Step 1: Escrever o teste (self-check) com um `.ini` fake e um listener TCP real**

Criar `tests/monitor_lib_test.prw`:

```advpl
#include "../src/monitor_lib.prw"

User Function MonitorLibTest()
    Local cIniPath := "test_units.ini"
    Local oRes

    // .ini de teste: TCPOK aponta pra uma porta que sobe (127.0.0.1:19191,
    // aberta pelo harness do teste antes de rodar este .prw), TCPDOWN
    // aponta pra uma porta que ninguém escuta, TCPGHOST não existe no .ini.
    MemoWrite(cIniPath, "[TCPOK]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                        "Port=19191" + Chr(13) + Chr(10) + ;
                        "[TCPDOWN]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                        "Port=19192" + Chr(13) + Chr(10))

    oRes := MonCheckUnidade("TCPOK", cIniPath, 1000)
    ConOut("teste1_unidade=" + oRes["UNIDADE"])
    ConOut("teste1_host=" + oRes["HOST"])
    ConOut("teste1_port=" + Str(oRes["PORT"]))
    ConOut("teste1_up=" + IIF(oRes["UP"], "SIM", "NAO"))

    oRes := MonCheckUnidade("TCPDOWN", cIniPath, 1000)
    ConOut("teste2_up=" + IIF(oRes["UP"], "SIM", "NAO"))

    oRes := MonCheckUnidade("TCPGHOST", cIniPath, 1000)
    ConOut("teste3_up=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste3_erro=" + oRes["ERRO"])

    FErase(cIniPath)
    ConOut("MONITOR_LIB_TEST_FIM")
Return
```

- [ ] **Step 2: Rodar o teste e confirmar que falha (função ainda não existe)**

Antes de implementar, subir um listener TCP na porta 19191 (para o teste ter algo "up" pra achar) e rodar:

```bash
python3 -c "
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 19191)); s.listen(1); time.sleep(15)
" &
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: falha de compilação/execução, algo como `unknown function MONCHECKUNIDADE` ou erro de `#include` (arquivo `monitor_lib.prw` ainda vazio/inexistente).

- [ ] **Step 3: Implementar `MonCheckUnidade` em `src/monitor_lib.prw`**

```advpl
User Function MonCheckUnidade(cUnidade, cIniPath, nTimeoutMs)
    Local oRes    := JsonObject():New()
    Local cHost   := GetPvProfString(cUnidade, "Server", "", cIniPath)
    Local cPortas := GetPvProfString(cUnidade, "Port", "", cIniPath)
    Local nPort   := Val(cPortas)

    oRes["UNIDADE"] := cUnidade
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPort

    If cHost == "" .Or. cPortas == ""
        oRes["UP"]   := .F.
        oRes["ERRO"] := "secao_nao_encontrada_no_ini"
        Return oRes
    EndIf

    oRes["UP"]   := PING(cHost, nPort, nTimeoutMs)
    oRes["ERRO"] := ""
Return oRes
```

- [ ] **Step 4: Rodar o teste de novo e confirmar que passa**

Com o mesmo listener em 19191 ainda de pé (repita o comando python do Step 2 se já tiver caído), rode:

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (saída exata):
```
teste1_unidade=TCPOK
teste1_host=127.0.0.1
teste1_port=19191
teste1_up=SIM
teste2_up=NAO
teste3_up=NAO
teste3_erro=secao_nao_encontrada_no_ini
MONITOR_LIB_TEST_FIM
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: checagem de unidade via ini + PING TCP"
```

---

### Task 2: Estado anterior (up/down por unidade) persistido em `state.json`

**Files:**
- Modify: `src/monitor_lib.prw` (adicionar funções, sem tocar na de Task 1)
- Modify: `tests/monitor_lib_test.prw` (adicionar novos testes ao final, antes do `ConOut("MONITOR_LIB_TEST_FIM")`)

**Interfaces:**
- Consumes: nada de Task 1 diretamente (função independente).
- Produces:
  - `User Function MonLoadState(cStatePath) -> oState` (`JsonObject`; vazio se arquivo não existir ou estiver vazio)
  - `User Function MonGetStatusAnterior(oState, cUnidade) -> cStatus` (`"UP"`, `"DOWN"` ou `"DESCONHECIDO"`)
  - `User Function MonSetStatus(oState, cUnidade, cStatus) -> Nil` (muta `oState` in-place)
  - `User Function MonSaveState(cStatePath, oState) -> lOk`

- [ ] **Step 1: Escrever os testes**

Adicionar em `tests/monitor_lib_test.prw`, antes de `ConOut("MONITOR_LIB_TEST_FIM")`:

```advpl
    Local cStatePath := "test_state.json"
    Local oState

    FErase(cStatePath)
    oState := MonLoadState(cStatePath)
    ConOut("teste4_status_novo=" + MonGetStatusAnterior(oState, "TCPSP"))

    MonSetStatus(oState, "TCPSP", "UP")
    ConOut("teste5_status_apos_set=" + MonGetStatusAnterior(oState, "TCPSP"))

    ConOut("teste6_save=" + IIF(MonSaveState(cStatePath, oState), "SIM", "NAO"))

    oState := MonLoadState(cStatePath)
    ConOut("teste7_status_apos_reload=" + MonGetStatusAnterior(oState, "TCPSP"))
    ConOut("teste8_status_outra_unidade=" + MonGetStatusAnterior(oState, "TCPRJ"))

    FErase(cStatePath)
```

- [ ] **Step 2: Rodar e confirmar falha** (funções ainda não existem)

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function MONLOADSTATE` (ou similar) — o teste para no primeiro `Local cStatePath`/chamada nova.

- [ ] **Step 3: Implementar em `src/monitor_lib.prw`**

```advpl
User Function MonLoadState(cStatePath)
    Local oState := JsonObject():New()
    Local cTxt   := MemoRead(cStatePath)

    If cTxt != ""
        oState:FromJson(cTxt)
    EndIf
Return oState

User Function MonGetStatusAnterior(oState, cUnidade)
    If !oState:HasProperty(cUnidade)
        Return "DESCONHECIDO"
    EndIf
Return oState[cUnidade]

User Function MonSetStatus(oState, cUnidade, cStatus)
    oState[cUnidade] := cStatus
Return Nil

User Function MonSaveState(cStatePath, oState)
Return MemoWrite(cStatePath, oState:ToJson())
```

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas, além das da Task 1):
```
teste4_status_novo=DESCONHECIDO
teste5_status_apos_set=UP
teste6_save=SIM
teste7_status_apos_reload=UP
teste8_status_outra_unidade=DESCONHECIDO
MONITOR_LIB_TEST_FIM
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: persistencia de estado anterior por unidade"
```

---

### Task 3: Log em arquivo (append) e leitura de `config.json`

**Files:**
- Modify: `src/monitor_lib.prw`
- Modify: `tests/monitor_lib_test.prw`
- Create: `config.example.json`

**Interfaces:**
- Produces:
  - `User Function MonLog(cLogPath, cTexto) -> Nil` (append de uma linha com timestamp `DD/MM/AAAA HH:MM:SS - <texto>`)
  - `User Function MonLoadConfig(cConfigPath) -> oConfig` (`JsonObject`; `NIL` se arquivo não existir/não parsear)
  - `User Function MonGetUnidades(oConfig) -> aUnidades` (array de strings; array vazio se chave ausente)

- [ ] **Step 1: Escrever os testes**

Adicionar em `tests/monitor_lib_test.prw`, antes do `ConOut("MONITOR_LIB_TEST_FIM")`:

```advpl
    Local cLogPath := "test_monitor.log"
    Local cConfigPath := "test_config.json"
    Local oConfig
    Local aUnidades
    Local cConteudoLog

    FErase(cLogPath)
    MonLog(cLogPath, "linha um")
    MonLog(cLogPath, "linha dois")
    cConteudoLog := MemoRead(cLogPath)
    ConOut("teste9_log_tem_linha_um=" + IIF("linha um" $ cConteudoLog, "SIM", "NAO"))
    ConOut("teste10_log_tem_linha_dois=" + IIF("linha dois" $ cConteudoLog, "SIM", "NAO"))
    FErase(cLogPath)

    MemoWrite(cConfigPath, '{"iniPath":"C:\\totvs\\appserver.ini","intervaloSegundos":60,' + ;
                           '"timeoutMs":3000,"telegramBotToken":"TOKEN123",' + ;
                           '"telegramChatId":"CHAT123","unidades":["TCPSP","TCPRJ"]}')
    oConfig := MonLoadConfig(cConfigPath)
    ConOut("teste11_inipath=" + oConfig["iniPath"])
    ConOut("teste12_intervalo=" + Str(oConfig["intervaloSegundos"]))

    aUnidades := MonGetUnidades(oConfig)
    ConOut("teste13_qtd_unidades=" + Str(Len(aUnidades)))
    ConOut("teste14_unidade1=" + aUnidades[1])
    ConOut("teste15_unidade2=" + aUnidades[2])
    FErase(cConfigPath)

    ConOut("teste16_config_ausente=" + IIF(MonLoadConfig("nao_existe.json") == Nil, "SIM", "NAO"))
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function MONLOG` (ou similar).

- [ ] **Step 3: Implementar em `src/monitor_lib.prw`**

```advpl
User Function MonLog(cLogPath, cTexto)
    Local cLinha := DTOC(Date()) + " " + Time() + " - " + cTexto + Chr(13) + Chr(10)
    Local nH := FOpen(cLogPath, 1)

    If nH < 0
        nH := FCreate(cLogPath)
    EndIf
    If nH >= 0
        FSeek(nH, 0, 2)
        FWrite(nH, cLinha)
        FClose(nH)
    EndIf
Return Nil

User Function MonLoadConfig(cConfigPath)
    Local oConfig := JsonObject():New()
    Local cTxt := MemoRead(cConfigPath)

    If cTxt == ""
        Return Nil
    EndIf
    If !oConfig:FromJson(cTxt)
        Return Nil
    EndIf
Return oConfig

User Function MonGetUnidades(oConfig)
    If !oConfig:HasProperty("unidades")
        Return {}
    EndIf
Return oConfig["unidades"]
```

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas):
```
teste9_log_tem_linha_um=SIM
teste10_log_tem_linha_dois=SIM
teste11_inipath=C:\totvs\appserver.ini
teste12_intervalo=60
teste13_qtd_unidades=2
teste14_unidade1=TCPSP
teste15_unidade2=TCPRJ
teste16_config_ausente=SIM
MONITOR_LIB_TEST_FIM
```

- [ ] **Step 5: Criar `config.example.json`**

```json
{
  "iniPath": "C:\\totvs\\appserver.ini",
  "intervaloSegundos": 60,
  "timeoutMs": 3000,
  "telegramBotToken": "COLOQUE_O_TOKEN_DO_BOT_AQUI",
  "telegramChatId": "COLOQUE_O_CHAT_ID_AQUI",
  "unidades": ["TCPSP", "TCPRJ", "TCPMG", "TCPGO", "TCPMT", "TCPBA",
               "TCPPE", "TCPCE", "TCPPR", "TCPPA", "TCPRS", "TCPAM",
               "TCPFB", "TCPAF", "TCPOF"]
}
```

- [ ] **Step 6: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw config.example.json
git commit -m "feat: log em arquivo e leitura de config.json"
```

---

### Task 4: Notificação Telegram e montagem da mensagem de alerta

**Files:**
- Modify: `src/monitor_lib.prw`
- Modify: `tests/monitor_lib_test.prw`

**Interfaces:**
- Consumes: nenhuma função das tasks anteriores diretamente (mas usa o mesmo `JsonObject`/`FWHttpPost` já validados no projeto AdvPP).
- Produces:
  - `User Function MonNotificarTelegram(cToken, cChatId, cTexto) -> lOk`
  - `User Function MonMontarMensagem(cUnidade, cHost, nPort, cStatusNovo) -> cTexto`
    (`cStatusNovo` é `"UP"` ou `"DOWN"`; gera texto tipo `"[ALERTA] TCPSP (127.0.0.1:4000) caiu"` ou `"[OK] TCPSP (127.0.0.1:4000) voltou"`)

- [ ] **Step 1: Escrever os testes**

Adicionar em `tests/monitor_lib_test.prw`, antes do `ConOut("MONITOR_LIB_TEST_FIM")`. O teste de envio real ao Telegram é pulado por padrão (precisa de token real) — só roda se a env var `MONITOR_TEST_TELEGRAM_TOKEN` estiver setada, seguindo a mesma convenção de `http_native_test.prw` (pular quando faltar configuração externa):

```advpl
    Local cMsgDown := MonMontarMensagem("TCPSP", "10.0.200.62", 4000, "DOWN")
    Local cMsgUp   := MonMontarMensagem("TCPSP", "10.0.200.62", 4000, "UP")
    ConOut("teste17_msg_down=" + cMsgDown)
    ConOut("teste18_msg_up=" + cMsgUp)
    ConOut("teste19_msg_down_tem_unidade=" + IIF("TCPSP" $ cMsgDown, "SIM", "NAO"))
    ConOut("teste20_msg_down_tem_host_porta=" + IIF("10.0.200.62:4000" $ cMsgDown, "SIM", "NAO"))

    Local cTokenTeste := GetEnv("MONITOR_TEST_TELEGRAM_TOKEN")
    Local cChatTeste  := GetEnv("MONITOR_TEST_TELEGRAM_CHAT")
    If cTokenTeste == ""
        ConOut("teste21_telegram=skip_sem_token")
    Else
        ConOut("teste21_telegram=" + IIF(MonNotificarTelegram(cTokenTeste, cChatTeste, "teste automatizado do monitor"), "SIM", "NAO"))
    EndIf
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function MONMONTARMENSAGEM`.

- [ ] **Step 3: Implementar em `src/monitor_lib.prw`**

```advpl
User Function MonMontarMensagem(cUnidade, cHost, nPort, cStatusNovo)
    Local cTexto

    If cStatusNovo == "DOWN"
        cTexto := "[ALERTA] " + cUnidade + " (" + cHost + ":" + Str(nPort) + ") caiu"
    Else
        cTexto := "[OK] " + cUnidade + " (" + cHost + ":" + Str(nPort) + ") voltou"
    EndIf
Return cTexto

User Function MonNotificarTelegram(cToken, cChatId, cTexto)
    Local cUrl    := "https://api.telegram.org/bot" + cToken + "/sendMessage"
    Local oBody   := JsonObject():New()
    Local nStatus

    oBody["chat_id"] := cChatId
    oBody["text"]    := cTexto

    nStatus := FWHttpPost(cUrl, oBody:ToJson(), "application/json")
Return (nStatus >= 200 .And. nStatus < 300)
```

`Str(nPort)` traz espaços de padding (largura default do `Str()` do AdvPL) — ajustar para `Str(nPort, 10, 0)`... **na verdade, mais simples**: usar `AllTrim(Str(nPort))` para não vazar espaços na mensagem. Ajuste o código acima trocando as duas ocorrências de `Str(nPort)` por `AllTrim(Str(nPort))` antes de rodar o teste.

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas):
```
teste17_msg_down=[ALERTA] TCPSP (10.0.200.62:4000) caiu
teste18_msg_up=[OK] TCPSP (10.0.200.62:4000) voltou
teste19_msg_down_tem_unidade=SIM
teste20_msg_down_tem_host_porta=SIM
teste21_telegram=skip_sem_token
MONITOR_LIB_TEST_FIM
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: notificacao telegram e mensagem de alerta"
```

---

### Task 5: Ciclo de checagem completo (uma unidade, com alerta na borda) + `Try/Catch` por unidade

**Files:**
- Modify: `src/monitor_lib.prw`
- Modify: `tests/monitor_lib_test.prw`

**Interfaces:**
- Consumes: `MonCheckUnidade` (Task 1), `MonGetStatusAnterior`/`MonSetStatus` (Task 2), `MonLog` (Task 3), `MonMontarMensagem`/`MonNotificarTelegram` (Task 4).
- Produces: `User Function MonProcessarUnidade(cUnidade, cIniPath, nTimeoutMs, oState, cLogPath, cToken, cChatId) -> Nil`
  (faz 1 checagem da unidade, atualiza `oState` in-place, loga sempre, notifica só na borda; qualquer erro interno é capturado e só vira linha de log, nunca propaga)

- [ ] **Step 1: Escrever o teste**

Adicionar em `tests/monitor_lib_test.prw`, antes do `ConOut("MONITOR_LIB_TEST_FIM")`. Reaproveita o `.ini` de teste (`TCPOK` até responder, `TCPDOWN` sempre fechada) e um "Telegram fake": como não dá pra afirmar entrega real sem token, o teste verifica o efeito observável que não depende de rede — o log e o `oState` mudando corretamente — e usa host/porta inválidos de propósito para forçar `MonNotificarTelegram` a falhar (retornar `.F.`) sem quebrar o fluxo:

```advpl
    Local cIni2      := "test_units2.ini"
    Local cLog2      := "test_monitor2.log"
    Local oState2    := JsonObject():New()
    Local cTokenFake := "TOKEN_INVALIDO_DE_PROPOSITO"
    Local cChatFake  := "0"
    Local cLogTxt

    MemoWrite(cIni2, "[TCPX]" + Chr(13) + Chr(10) + ;
                     "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                     "Port=19193" + Chr(13) + Chr(10))
    FErase(cLog2)

    // 1ª passagem: unidade está down (nada escutando na 19193), estado
    // anterior é DESCONHECIDO -> muda pra DOWN -> deve logar e tentar notificar.
    MonProcessarUnidade("TCPX", cIni2, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("teste22_status_apos_1a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))

    // 2ª passagem: continua down, estado anterior já é DOWN -> não deve
    // gerar uma segunda tentativa de notificação (não dá pra observar a
    // notificação em si sem rede, mas o estado deve permanecer DOWN e
    // o log deve ganhar uma linha nova mesmo sem alerta).
    cLogTxt := MemoRead(cLog2)
    MonProcessarUnidade("TCPX", cIni2, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("teste23_status_apos_2a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))
    ConOut("teste24_log_cresceu=" + IIF(Len(MemoRead(cLog2)) > Len(cLogTxt), "SIM", "NAO"))

    FErase(cIni2)
    FErase(cLog2)
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function MONPROCESSARUNIDADE`.

- [ ] **Step 3: Implementar em `src/monitor_lib.prw`**

```advpl
User Function MonProcessarUnidade(cUnidade, cIniPath, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local oRes
    Local cStatusAnterior
    Local cStatusNovo
    Local cMsg
    Local e

    Try
        oRes := MonCheckUnidade(cUnidade, cIniPath, nTimeoutMs)
        cStatusAnterior := MonGetStatusAnterior(oState, cUnidade)
        cStatusNovo := IIF(oRes["UP"], "UP", "DOWN")

        MonLog(cLogPath, cUnidade + " " + oRes["HOST"] + ":" + AllTrim(Str(oRes["PORT"])) + " status=" + cStatusNovo)

        If cStatusNovo != cStatusAnterior
            cMsg := MonMontarMensagem(cUnidade, oRes["HOST"], oRes["PORT"], cStatusNovo)
            If !MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cUnidade + " falha ao notificar telegram")
            EndIf
            MonSetStatus(oState, cUnidade, cStatusNovo)
        EndIf
    Catch e
        MonLog(cLogPath, cUnidade + " erro_interno=" + e:description)
    EndTry
Return Nil
```

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas):
```
teste22_status_apos_1a_passagem=DOWN
teste23_status_apos_2a_passagem=DOWN
teste24_log_cresceu=SIM
MONITOR_LIB_TEST_FIM
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: ciclo de checagem por unidade com alerta na borda"
```

---

### Task 6: Programa principal (`monitor.prw`) — loop, `state.json` ao lado do exe, build do executável

**Files:**
- Create: `src/monitor.prw`
- Create: `README.md`

**Interfaces:**
- Consumes: todas as funções de `src/monitor_lib.prw` (Tasks 1–5).
- Produces: `User Function MonitorMain()` (entry point do build; loop infinito, não é chamada por nenhum teste — verificação manual no Step 3/4).

- [ ] **Step 1: Escrever `src/monitor.prw`**

```advpl
#include "monitor_lib.prw"

User Function MonitorMain()
    Local cConfigPath := "config.json"
    Local cStatePath  := "state.json"
    Local cLogPath    := "monitor.log"
    Local oConfig
    Local oState
    Local aUnidades
    Local i

    oConfig := MonLoadConfig(cConfigPath)
    If oConfig == Nil
        ConOut("ERRO FATAL: nao foi possivel ler " + cConfigPath)
        Return
    EndIf

    aUnidades := MonGetUnidades(oConfig)
    If Len(aUnidades) == 0
        ConOut("ERRO FATAL: config.json sem a chave 'unidades' ou lista vazia")
        Return
    EndIf

    oState := MonLoadState(cStatePath)

    ConOut("Monitor iniciado. " + AllTrim(Str(Len(aUnidades))) + " unidade(s), intervalo de " + AllTrim(Str(oConfig["intervaloSegundos"])) + "s.")

    While .T.
        For i := 1 To Len(aUnidades)
            MonProcessarUnidade(aUnidades[i], oConfig["iniPath"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
        Next
        MonSaveState(cStatePath, oState)
        Sleep(oConfig["intervaloSegundos"] * 1000)
    EndDo
Return
```

- [ ] **Step 2: Verificação manual do arranque (sem esperar o loop rodar pra sempre)**

Não dá pra "rodar até o fim" um `While .T.` em CI — a verificação aqui é de fumaça: confirmar que o programa sobe, lê a config, faz pelo menos uma passada e começa a esperar. Criar uma config de teste e interromper manualmente:

```bash
cd ~/Projetos/monitor/src
cat > config.json << 'EOF'
{
  "iniPath": "../tests/test_units.ini",
  "intervaloSegundos": 5,
  "timeoutMs": 500,
  "telegramBotToken": "FAKE",
  "telegramChatId": "0",
  "unidades": ["TCPGHOST"]
}
EOF
cat > ../tests/test_units.ini << 'EOF'
[TCPGHOST]
Server=127.0.0.1
Port=19199
EOF
timeout 8 ~/Projetos/AdvPP/advplc run monitor.prw
```

Expected: imprime `Monitor iniciado. 1 unidade(s), intervalo de 5s.`, o processo é encerrado pelo `timeout` após 8s (saída sem erro fatal), e `monitor.log`/`state.json` aparecem em `src/` com uma linha `TCPGHOST ... status=DOWN`.

```bash
cat monitor.log
cat state.json
rm -f config.json monitor.log state.json
rm -f ../tests/test_units.ini
```

- [ ] **Step 3: Compilar o executável standalone (cross-compile pro Windows)**

```bash
cd ~/Projetos/AdvPP
GOOS=windows GOARCH=amd64 ./advplc build ~/Projetos/monitor/src/monitor.prw -o ~/Projetos/monitor/dist/monitor.exe
ls -la ~/Projetos/monitor/dist/monitor.exe
```

Expected: o binário `monitor.exe` é gerado sem erro. (Se `GOOS`/`GOARCH` não forem respeitados pelo `advplc build` — ele pode já rodar num processo `go build` interno fixo pro SO do host — anotar isso e compilar diretamente na máquina Windows com o `advplc.exe`/fonte do AdvPP instalado lá, que é a alternativa já prevista na spec.)

- [ ] **Step 4: Escrever `README.md`**

```markdown
# Monitor de Unidades Protheus

Vigia o broker TCP (SmartClient) de cada unidade Protheus listada num
`.ini` de conexão existente, e avisa no Telegram quando uma unidade cai
ou volta.

## Compilar

A partir de um checkout do AdvPP (https://github.com/peder1981/AdvPP):

    ./advplc build /caminho/para/monitor/src/monitor.prw -o monitor.exe

Rodando em Linux, gera um binário do SO atual — pra gerar `.exe` do
Windows a partir do Linux, ver se `GOOS=windows GOARCH=amd64` antes do
comando funciona (ver plano de implementação, Task 6, Step 3); se não
funcionar, compile direto na máquina Windows com o AdvPP instalado lá.

## Configurar

Copie `config.example.json` para `config.json` ao lado do `monitor.exe`
e preencha:

- `iniPath`: caminho completo do `.ini` de conexão do SmartClient na
  máquina Windows (ex: `C:\\totvs\\appserver.ini`).
- `telegramBotToken` / `telegramChatId`: credenciais do bot do Telegram
  que vai mandar os alertas.
- `unidades`: lista dos nomes de seção do `.ini` a vigiar (ex: `TCPSP`,
  `TCPRJ`, ...).
- `intervaloSegundos` / `timeoutMs`: frequência da checagem e timeout
  de cada tentativa de conexão TCP.

## Rodar

    monitor.exe

Fica em loop pra sempre, gerando `monitor.log` (toda checagem) e
`state.json` (último status conhecido de cada unidade) ao lado do
`.exe`. Agende no Task Scheduler do Windows como "ao iniciar o
sistema", sem precisar de serviço Windows — o `Sleep` interno já
mantém o processo vivo.
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor.prw README.md
git commit -m "feat: programa principal com loop e build do executavel"
```

---

## Self-Review (feito ao escrever este plano)

- **Cobertura da spec:** arquitetura (Task 6), leitura do `.ini` (Task 1), checagem TCP (Task 1), config.json/unidades (Task 3), estado anterior/`state.json` (Task 2/6), log (Task 3), Telegram (Task 4), alerta só na borda (Task 5), `Try/Catch` por unidade (Task 5), empacotamento/build (Task 6), teste mínimo (todas as tasks têm teste próprio) — todas as seções da spec têm task correspondente. Dbaccess/License Server ficam de fora, como já combinado.
- **Placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem código completo.
- **Consistência de tipos:** `oResultado` de `MonCheckUnidade` (chaves `UNIDADE`/`HOST`/`PORT`/`UP`/`ERRO`) é usado com essas mesmas chaves em `MonProcessarUnidade` (Task 5). `oState`/`cStatus` (`"UP"`/`"DOWN"`/`"DESCONHECIDO"`) são usados com os mesmos literais em Task 2, 5 e 6. `MonGetUnidades` devolve array de string, consumido em `monitor.prw` com `For i := 1 To Len(aUnidades)` + `aUnidades[i]`.
