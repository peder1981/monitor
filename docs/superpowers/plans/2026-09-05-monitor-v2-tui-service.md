# Monitor v2 — webapp/HTTP, latência, TUI e serviço de fundo — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrar a checagem de appserver de TCP puro (broker SmartClient) para HTTP no webapp (porta fixa, medindo latência), adicionar latência também a dbaccess/license server, e entregar dois executáveis Windows compilados via CI: `MonitorService.exe` (loop de fundo, sem interface) e `MonitorTUI.exe` (painel ASCII interativo para configurar/controlar/ver status).

**Architecture:** `src/monitor_lib.prw` continua a única biblioteca de lógica (funções puras, sem loop); ganha `MonCheckWebapp` (substitui `MonCheckUnidade`), latência em `MonSetStatus`/nova `MonGetLatenciaAnterior`, e `MonProcessarUnidade` passa a delegar para o mesmo `MonProcessarResultado` já usado por dbaccess/license (elimina duplicação). Um arquivo novo, `src/monitor_tui_lib.prw`, concentra as funções específicas de interface (renderização de tabela, formulário de configuração, controle de processo) — mantém `monitor_lib.prw` livre de qualquer preocupação de UI. `src/monitor_tui.prw` é o entry point da TUI (`#include` dos dois libs). `src/monitor.prw` (o loop de fundo) muda pouco: só troca a chamada de checagem e o parâmetro de porta.

**Tech Stack:** AdvPL via AdvPP (`advplc`, pinado em `v3.0.4` — ver Global Constraints). Nativas novas usadas: `FWHttpGet`/`FWHttpTimeout` (checagem HTTP), `TimeCounter()` (latência, monotônico em ms), `UiBox`/`UiStreamBox`/`UiStreamReset`/`UiAltScreenEnter`/`UiAltScreenExit` (renderização TUI via lipgloss, sem cgo), `FWGetText`/`FWMenuSelect` (formulário/menu interativo via terminal, providos automaticamente pelo `advplc run`/`build` quando stdin é um TTY real), `ProcRun` (lista processos via `tasklist`, callback por linha), `WaitRun` (dispara `cmd /c start` desanexado e `taskkill`).

**Spec:** `docs/superpowers/specs/2026-09-05-monitor-v2-tui-service.md`

## Global Constraints

- `ADVPP_VERSION` pinado em `3.0.4` (arquivo na raiz do repo, mesma convenção do projeto `GesCon`) — toda referência a "o compilador" nas tasks usa essa versão exata, testada e confirmada com as nativas abaixo antes deste plano ser escrito.
- Nenhuma dependência nova além do que o AdvPP 3.0.4 já embute nativamente. Nenhum toolchain (MinGW/gcc) instalado em nenhuma máquina do operador — só a CI (GitHub Actions, runner `windows-latest`) compila; a máquina Windows alvo só baixa e roda os `.exe` prontos.
- Checagem de appserver por TCP puro (porta do broker SmartClient) é **removida por completo** — `MonCheckUnidade` e seus testes saem do código; não fica como opção paralela configurável.
- `state.json` NÃO usa objeto aninhado como valor — confirmado empiricamente que `JsonObject:ToJson()` não serializa um `JsonObject` aninhado (vira a string `"Object:JsonObject"`, perdendo dados). Formato real: chave paralela `"<CHAVE>_LATENCIA"` (número, ms) ao lado da chave de status existente (string).
- `MonitorTUI.exe` usa `FWGetText`/`FWMenuSelect`, que só rendem em modo console quando stdin é um TTY real — aberto por duplo-clique no Explorer (sem console anexado) o AdvPP abre uma janela Fyne por trás em vez do console. Mitigação: um `.bat` no release que abre um `cmd.exe` e roda o `.exe` de dentro dele; README documenta "nunca abra o `.exe` direto".
- Todo teste automatizado roda com `advplc run <arquivo>.prw` (binário em `/home/peder/Projetos/AdvPP/advplc`, ou o pinado em `3.0.4` — ver Task 8) e a verificação é lida via `ConOut`, mesma convenção da v1. Comandos que só existem no Windows real (`cmd /c start`, `taskkill`, `tasklist`) não podem ser exercitados neste ambiente Linux de desenvolvimento — cada task que os introduz tem um passo de **verificação manual na máquina Windows** claramente marcado, além do teste automatizado da lógica que não depende do SO.

---

## Arquivos deste plano

```
monitor/
  ADVPP_VERSION                # novo: "3.0.4"
  src/
    monitor_lib.prw            # modificado: MonCheckWebapp substitui MonCheckUnidade;
                                # MonSetStatus ganha latencia; MonProcessarUnidade
                                # delega para MonProcessarResultado (como dbaccess/license)
    monitor.prw                # modificado: usa MonCheckWebapp/portaWebapp
    monitor_tui_lib.prw        # novo: renderização de tabela, formulário, controle de processo
    monitor_tui.prw            # novo: entry point da TUI
  tests/
    monitor_lib_test.prw       # modificado: remove testes de MonCheckUnidade/MonProcessarUnidade
                                # antigos (TCP), adiciona equivalentes para MonCheckWebapp/latência
    monitor_tui_lib_test.prw   # novo: testa a lógica de monitor_tui_lib.prw que não depende do SO
  config.example.json          # modificado: adiciona portaWebapp
  abrir-painel.bat             # novo: abre MonitorTUI.exe dentro de um cmd.exe
  .github/workflows/
    release.yml                # novo: build dos dois .exe via CI (windows-latest)
  README.md                    # modificado: instruções de instalação/uso da v2
```

---

### Task 1: `MonCheckWebapp` — checagem HTTP com latência, substitui `MonCheckUnidade`

**Files:**
- Modify: `src/monitor_lib.prw` (remove `MonCheckUnidade` linhas 3-21; adiciona `MonCheckWebapp` no lugar)
- Modify: `tests/monitor_lib_test.prw` (remove `teste1`-`teste3` — testavam `MonCheckUnidade`; adiciona equivalentes para `MonCheckWebapp`)

**Interfaces:**
- Produces: `User Function MonCheckWebapp(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs) -> oResultado`, um `JsonObject` com as chaves `UNIDADE` (string), `HOST` (string, lido do `.ini` via `GetPvProfString(cUnidade, "Server", "", cIniPath)`), `PORT` (numeric, é o `nPortaWebapp` recebido, não lido do `.ini`), `UP` (logical — `.T.` se `FWHttpGet` retornar status HTTP entre 1 e 499), `ERRO` (string, `"secao_nao_encontrada_no_ini"` se `HOST` vier vazio, senão `""`), `LATENCIAMS` (numeric, ms entre o início e o fim da chamada HTTP — `0` se nem chegou a tentar por falta de host).

- [ ] **Step 1: Remover o teste antigo de `MonCheckUnidade` e escrever o novo teste de `MonCheckWebapp`**

Em `tests/monitor_lib_test.prw`, localize e REMOVA o bloco de `teste1` a `teste3` (a parte que cria `test_units.ini` com `[TCPOK]`/`[TCPDOWN]`, chama `MonCheckUnidade` três vezes, e os `ConOut` de `teste1_unidade` até `teste3_erro`, terminando no `FErase(cIniPath)` daquele bloco). No lugar, insira:

```advpl
    // teste1-4: MonCheckWebapp -- checagem HTTP com latencia, porta fixa
    // (nao vem do .ini, só o host vem). "TCPWEBOK" tem host com um
    // servidor HTTP real escutando (subido pelo harness do teste antes de
    // rodar este .prw, na porta 19191); "TCPWEBGHOST" nao existe no .ini.
    Local cIniPath := "test_units.ini"
    Local oRes

    MemoWrite(cIniPath, "[TCPWEBOK]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10))

    oRes := MonCheckWebapp("TCPWEBOK", cIniPath, 19191, 2000)
    ConOut("teste1_unidade=" + oRes["UNIDADE"])
    ConOut("teste2_host=" + oRes["HOST"])
    ConOut("teste3_port=" + Str(oRes["PORT"]))
    ConOut("teste4_up=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste5_latencia_nao_negativa=" + IIF(oRes["LATENCIAMS"] >= 0, "SIM", "NAO"))

    oRes := MonCheckWebapp("TCPWEBGHOST", cIniPath, 19191, 2000)
    ConOut("teste6_up_secao_ausente=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste7_erro_secao_ausente=" + oRes["ERRO"])

    FErase(cIniPath)
```

- [ ] **Step 2: Rodar e confirmar que falha** (função ainda não existe, e o teste antigo já não existe mais no arquivo)

Subir um listener HTTP real na porta 19191 (necessário para os testes que ainda existem no arquivo, ex. o antigo `teste1` de outras seções e o novo `teste4`/`teste5` acima — todos compartilham essa porta):

```bash
python3 -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 19191), H).serve_forever()
" &
sleep 1
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function: MonCheckWebapp`.

- [ ] **Step 3: Remover `MonCheckUnidade` e implementar `MonCheckWebapp` em `src/monitor_lib.prw`**

Remover as linhas 1-21 atuais (comentário de topo + `MonCheckUnidade` inteira) e substituir por:

```advpl
// Monitor library - checagem HTTP/TCP e controle de estado

User Function MonCheckWebapp(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs)
    Local oRes  := JsonObject():New()
    Local cHost := GetPvProfString(cUnidade, "Server", "", cIniPath)
    Local nT1
    Local nStatus

    oRes["UNIDADE"] := cUnidade
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPortaWebapp

    If cHost == ""
        oRes["UP"]         := .F.
        oRes["ERRO"]       := "secao_nao_encontrada_no_ini"
        oRes["LATENCIAMS"] := 0
        Return oRes
    EndIf

    FWHttpTimeout(nTimeoutMs / 1000)
    nT1 := TimeCounter()
    nStatus := FWHttpGet("http://" + cHost + ":" + AllTrim(Str(nPortaWebapp)) + "/")
    oRes["LATENCIAMS"] := TimeCounter() - nT1
    oRes["UP"]   := (nStatus > 0 .And. nStatus < 500)
    oRes["ERRO"] := ""
Return oRes
```

- [ ] **Step 4: Rodar e confirmar sucesso**

Com o mesmo listener HTTP do Step 2 ainda de pé:

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (as primeiras linhas relevantes; as demais do arquivo, ainda não tocadas por esta task, continuam iguais):
```
teste1_unidade=TCPWEBOK
teste2_host=127.0.0.1
teste3_port=19191
teste4_up=SIM
teste5_latencia_nao_negativa=SIM
teste6_up_secao_ausente=NAO
teste7_erro_secao_ausente=secao_nao_encontrada_no_ini
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: MonCheckWebapp substitui MonCheckUnidade (HTTP com latencia)"
```

---

### Task 2: Latência em `MonSetStatus`/nova `MonGetLatenciaAnterior`

**Files:**
- Modify: `src/monitor_lib.prw` (função `MonSetStatus`, mais a nova `MonGetLatenciaAnterior`)
- Modify: `tests/monitor_lib_test.prw` (testes de estado, que hoje ficam depois do bloco de `MonLoadState`/`MonGetStatusAnterior`/`MonSetStatus`/`MonSaveState`)

**Interfaces:**
- Consumes: nada de Task 1 diretamente.
- Produces:
  - `User Function MonSetStatus(oState, cChave, cStatus, nLatenciaMs) -> Nil` — grava `oState[cChave] := cStatus` (como já fazia) **e** `oState[cChave + "_LATENCIA"] := nLatenciaMs`.
  - `User Function MonGetLatenciaAnterior(oState, cChave) -> nLatenciaMs` — `oState[cChave + "_LATENCIA"]` se existir, senão `-1`.
  - `MonGetStatusAnterior` **não muda** (mesma assinatura, mesmo comportamento).

- [ ] **Step 1: Escrever os testes**

Localize no arquivo de teste o bloco que testa `MonSetStatus`/`MonGetStatusAnterior` (as linhas que fazem `MonSetStatus(oState, "TCPSP", "UP")` e conferem `MonGetStatusAnterior`). Logo depois desse bloco, ANTES do `FErase(cStatePath)` que o encerra, insira:

```advpl
    MonSetStatus(oState, "TCPSP", "UP", 842)
    ConOut("testeLatencia1_valor=" + Str(MonGetLatenciaAnterior(oState, "TCPSP")))

    MonSaveState(cStatePath, oState)
    oState := MonLoadState(cStatePath)
    ConOut("testeLatencia2_valor_apos_reload=" + Str(MonGetLatenciaAnterior(oState, "TCPSP")))
    ConOut("testeLatencia3_unidade_sem_latencia=" + Str(MonGetLatenciaAnterior(oState, "TCPRJ")))
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: erro `unknown function: MonGetLatenciaAnterior` (ou, se essa linha não for alcançada por erro de assinatura de `MonSetStatus` com 4 argumentos onde a função atual só aceita 3 — nesse caso o AdvPP ignora o argumento extra silenciosamente e o erro real vem só na chamada de `MonGetLatenciaAnterior`; ambos os casos confirmam que a implementação ainda não existe).

- [ ] **Step 3: Implementar**

Em `src/monitor_lib.prw`, localize:

```advpl
User Function MonSetStatus(oState, cUnidade, cStatus)
    oState[cUnidade] := cStatus
Return Nil
```

Substitua por:

```advpl
User Function MonSetStatus(oState, cUnidade, cStatus, nLatenciaMs)
    oState[cUnidade] := cStatus
    oState[cUnidade + "_LATENCIA"] := nLatenciaMs
Return Nil

User Function MonGetLatenciaAnterior(oState, cChave)
    If !oState:HasProperty(cChave + "_LATENCIA")
        Return -1
    EndIf
Return oState[cChave + "_LATENCIA"]
```

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas):
```
testeLatencia1_valor=842
testeLatencia2_valor_apos_reload=842
testeLatencia3_unidade_sem_latencia=-1
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: latencia em MonSetStatus, nova MonGetLatenciaAnterior"
```

---

### Task 3: `MonProcessarResultado` grava latência; `MonProcessarUnidade` passa a usá-lo (webapp)

**Files:**
- Modify: `src/monitor_lib.prw` (`MonProcessarResultado` grava latência; `MonProcessarUnidade` reescrita para delegar nela, igual `MonProcessarDbaccess`/`MonProcessarLicenseServer`)
- Modify: `tests/monitor_lib_test.prw` (testes de `MonProcessarUnidade` que hoje usam `.ini`/TCP passam a usar HTTP)

**Interfaces:**
- Consumes: `MonCheckWebapp` (Task 1), `MonGetLatenciaAnterior`/`MonSetStatus` com 4 argumentos (Task 2).
- Produces:
  - `User Function MonProcessarResultado(cChave, cRotulo, oRes, oState, cLogPath, cToken, cChatId) -> Nil` — assinatura **não muda**, mas agora lê `oRes["LATENCIAMS"]` (chave que `MonCheckWebapp`/`MonPingServico` já preenchem) e passa pra `MonSetStatus` como 4º argumento; também loga a latência na linha de log.
  - `User Function MonProcessarUnidade(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs, oState, cLogPath, cToken, cChatId) -> Nil` — **assinatura muda**: entra `nPortaWebapp` logo depois de `cIniPath` (antes só tinha `nTimeoutMs` ali). Chama `MonCheckWebapp` em vez de `MonCheckUnidade`; se `oRes["ERRO"] != ""`, loga e retorna sem chamar `MonProcessarResultado` (igual ao comportamento antigo); senão delega inteiramente pra `MonProcessarResultado`.

- [ ] **Step 1: Localizar e revisar os testes existentes de `MonProcessarUnidade`**

No arquivo de teste, localize o bloco que testa `MonProcessarUnidade` com `.ini`/porta TCP fixa (as seções que criam `test_units2.ini`/`test_units4.ini` com `[TCPX]`/`[TCPUP]` apontando pra portas TCP, e os `ConOut` de status/log associados a essas chamadas — abrangem várias dezenas de linhas, com nomes de teste como `status_apos_1a_passagem`, `log_tem_sem_dados`, `status_permanece_desconhecido`, etc). Substitua **todo esse bloco** (da primeira declaração `Local cIni2 := ...` até o último `FErase` relacionado a essas unidades de teste `TCPX`/`TCPGHOST`/`TCPUP`) pela versão em HTTP abaixo — mantém a mesma cobertura de comportamento (unidade cai, unidade some do `.ini`, unidade já sobe saudável), só troca o transporte:

```advpl
    // MonProcessarUnidade (webapp/HTTP): unidade sem listener na porta
    // configurada -> DOWN, loga, tenta notificar (com token invalido, so
    // confirma que tentou pela linha de falha no log).
    Local cIni2   := "test_units2.ini"
    Local cLog2   := "test_monitor2.log"
    Local oState2 := JsonObject():New()
    Local cTokenFake := "TOKEN_INVALIDO_DE_PROPOSITO"
    Local cChatFake  := "0"
    Local cLogTxt

    MemoWrite(cIni2, "[TCPX]" + Chr(13) + Chr(10) + "Server=127.0.0.1" + Chr(13) + Chr(10))
    FErase(cLog2)

    MonProcessarUnidade("TCPX", cIni2, 19194, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("testePU1_status_apos_1a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))

    cLogTxt := MemoRead(cLog2)
    MonProcessarUnidade("TCPX", cIni2, 19194, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("testePU2_status_apos_2a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))
    ConOut("testePU3_log_cresceu=" + IIF(Len(MemoRead(cLog2)) > Len(cLogTxt), "SIM", "NAO"))
    ConOut("testePU4_latencia_registrada=" + IIF(MonGetLatenciaAnterior(oState2, "TCPX") >= 0, "SIM", "NAO"))

    FErase(cIni2)
    FErase(cLog2)

    // unidade com secao ausente no .ini nao deve virar DOWN -- fica
    // DESCONHECIDO, loga "sem_dados" e nao tenta notificar.
    Local cIni3   := "test_units3.ini"
    Local cLog3   := "test_monitor3.log"
    Local oState3 := JsonObject():New()

    MemoWrite(cIni3, "[OUTRAUNIDADE]" + Chr(13) + Chr(10) + "Server=127.0.0.1" + Chr(13) + Chr(10))
    FErase(cLog3)

    MonProcessarUnidade("TCPGHOST", cIni3, 19194, 500, oState3, cLog3, cTokenFake, cChatFake)
    ConOut("testePU5_status_permanece_desconhecido=" + MonGetStatusAnterior(oState3, "TCPGHOST"))

    Local cLogTxt3 := MemoRead(cLog3)
    ConOut("testePU6_log_tem_sem_dados=" + IIF("sem_dados" $ cLogTxt3, "SIM", "NAO"))
    ConOut("testePU7_log_tem_erro=" + IIF("secao_nao_encontrada_no_ini" $ cLogTxt3, "SIM", "NAO"))
    ConOut("testePU8_nao_tentou_notificar=" + IIF("falha ao notificar telegram" $ cLogTxt3, "NAO", "SIM"))

    FErase(cIni3)
    FErase(cLog3)

    // primeira passagem com unidade ja saudavel (DESCONHECIDO -> UP) nao
    // deve disparar o "[OK] ... voltou" espurio, mas deve gravar o estado.
    Local cIni4   := "test_units4.ini"
    Local cLog4   := "test_monitor4.log"
    Local oState4 := JsonObject():New()

    MemoWrite(cIni4, "[TCPUP]" + Chr(13) + Chr(10) + "Server=127.0.0.1" + Chr(13) + Chr(10))
    FErase(cLog4)

    MonProcessarUnidade("TCPUP", cIni4, 19191, 500, oState4, cLog4, cTokenFake, cChatFake)
    ConOut("testePU9_status_apos_1a_passagem=" + MonGetStatusAnterior(oState4, "TCPUP"))

    Local cLogTxt4 := MemoRead(cLog4)
    ConOut("testePU10_nao_tentou_notificar_ok_desconhecido=" + IIF("falha ao notificar telegram" $ cLogTxt4, "NAO", "SIM"))

    MonProcessarUnidade("TCPUP", cIni4, 19191, 500, oState4, cLog4, cTokenFake, cChatFake)
    ConOut("testePU11_status_apos_2a_passagem=" + MonGetStatusAnterior(oState4, "TCPUP"))

    FErase(cIni4)
    FErase(cLog4)
```

(`TCPUP` aponta pra porta 19191 — a mesma porta com o listener HTTP real de pé desde a Task 1; `TCPX`/`TCPGHOST` usam 19194, porta sem ninguém escutando de propósito.)

- [ ] **Step 2: Rodar e confirmar falha**

```bash
# listener HTTP da Task 1 (porta 19191) precisa estar de pe -- ver Step 2 da Task 1
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: falha, seja por assinatura incompatível de `MonProcessarUnidade` (ainda espera 3 parâmetros antes de `oState`, não 4) ou por `oRes["ERRO"]` inexistente vindo de `MonCheckWebapp` sendo usado com a implementação antiga — qualquer uma dessas confirma que o Step 3 ainda não foi feito.

- [ ] **Step 3: Implementar**

Em `src/monitor_lib.prw`, primeiro atualize `MonProcessarResultado` para gravar latência (adicione a leitura de `oRes["LATENCIAMS"]` e passe pra `MonSetStatus`, e inclua na linha de log):

```advpl
User Function MonProcessarResultado(cChave, cRotulo, oRes, oState, cLogPath, cToken, cChatId)
    Local cStatusAnterior
    Local cStatusNovo
    Local cMsg

    cStatusAnterior := MonGetStatusAnterior(oState, cChave)
    cStatusNovo := IIF(oRes["UP"], "UP", "DOWN")

    MonLog(cLogPath, cChave + " " + oRes["HOST"] + ":" + AllTrim(Str(oRes["PORT"])) + " status=" + cStatusNovo + " latenciaMs=" + AllTrim(Str(oRes["LATENCIAMS"])))

    If cStatusNovo != cStatusAnterior
        If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo == "DOWN"
            cMsg := MonMontarMensagem(cRotulo, oRes["HOST"], oRes["PORT"], cStatusNovo)
            If !MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " falha ao notificar telegram")
            EndIf
        EndIf
        MonSetStatus(oState, cChave, cStatusNovo, oRes["LATENCIAMS"])
    EndIf
Return Nil
```

Depois, substitua a `MonProcessarUnidade` inteira (que hoje tem seu próprio `Try/Catch`/log/notify duplicado) por uma versão que delega em `MonProcessarResultado`, igual `MonProcessarDbaccess`/`MonProcessarLicenseServer` já fazem:

```advpl
User Function MonProcessarUnidade(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local oRes
    Local e

    Try
        oRes := MonCheckWebapp(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs)

        If oRes["ERRO"] != ""
            MonLog(cLogPath, cUnidade + " sem_dados erro=" + oRes["ERRO"])
            Return Nil
        EndIf

        MonProcessarResultado(cUnidade, cUnidade, oRes, oState, cLogPath, cToken, cChatId)
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

Expected (novas linhas, nomes exatos como escritos no Step 1):
```
testePU1_status_apos_1a_passagem=DOWN
testePU2_status_apos_2a_passagem=DOWN
testePU3_log_cresceu=SIM
testePU4_latencia_registrada=SIM
testePU5_status_permanece_desconhecido=DESCONHECIDO
testePU6_log_tem_sem_dados=SIM
testePU7_log_tem_erro=SIM
testePU8_nao_tentou_notificar=SIM
testePU9_status_apos_1a_passagem=UP
testePU10_nao_tentou_notificar_ok_desconhecido=SIM
testePU11_status_apos_2a_passagem=UP
```

Confira também que TODAS as linhas de teste anteriores a esta task (Task 1, Task 2, e os testes de `MonProcessarDbaccess`/`MonProcessarLicenseServer`/`MonLog`/`MonLoadConfig`/etc que não foram tocados) continuam passando sem erro — rode a suíte inteira e leia a saída de cima a baixo, não só as linhas novas.

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "refactor: MonProcessarUnidade usa webapp/HTTP e delega em MonProcessarResultado"
```

---

### Task 4: Latência em `MonProcessarDbaccess`/`MonProcessarLicenseServer` (via `MonPingServico`)

**Files:**
- Modify: `src/monitor_lib.prw` (`MonPingServico` ganha `LATENCIAMS`)
- Modify: `tests/monitor_lib_test.prw` (testes de dbaccess/license, adicionar checagem de latência)

**Interfaces:**
- Consumes: `MonProcessarResultado` já lendo `oRes["LATENCIAMS"]` (Task 3) — como `MonProcessarDbaccess`/`MonProcessarLicenseServer` já delegam nela, não precisam de nenhuma mudança própria além de `MonPingServico` passar a preencher essa chave.
- Produces: `MonPingServico(cChave, cHost, nPort, nTimeoutMs) -> oResultado` — mesma assinatura, `oResultado` ganha a chave `LATENCIAMS` (numeric, ms em torno da chamada `PING`).

- [ ] **Step 1: Escrever o teste**

Localize no arquivo de teste o bloco que testa `MonProcessarDbaccess`/`MonProcessarLicenseServer` (as seções com `MonProcessarDbaccess("TCPSP", ...)` e `MonProcessarLicenseServer(...)`). Logo depois desse bloco, antes da limpeza final (`FErase(cLog7)` ou equivalente), insira:

```advpl
    Local oState8 := JsonObject():New()
    Local cLog8   := "test_monitor_latencia.log"

    FErase(cLog8)
    MonProcessarDbaccess("TCPLAT", "127.0.0.1", 19191, 500, oState8, cLog8, "TOKEN_FAKE", "0")
    ConOut("testeLatDbaccess_registrada=" + IIF(MonGetLatenciaAnterior(oState8, "TCPLAT_DBACCESS") >= 0, "SIM", "NAO"))

    MonProcessarLicenseServer("127.0.0.1", 19191, 500, oState8, cLog8, "TOKEN_FAKE", "0")
    ConOut("testeLatLicense_registrada=" + IIF(MonGetLatenciaAnterior(oState8, "LICENSE_SERVER") >= 0, "SIM", "NAO"))
    FErase(cLog8)
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: `testeLatDbaccess_registrada=NAO`/`testeLatLicense_registrada=NAO` (já que `MonGetLatenciaAnterior` retorna `-1` — `MonSetStatus` está sendo chamado com `oRes["LATENCIAMS"]` que ainda não existe em `MonPingServico`, então vira `Nil`, e `MonSetStatus` grava `Nil` na chave de latência; `MonGetLatenciaAnterior` lendo `Nil` não é `>= 0`). Confirma que falta implementar.

- [ ] **Step 3: Implementar**

Em `src/monitor_lib.prw`, localize:

```advpl
User Function MonPingServico(cChave, cHost, nPort, nTimeoutMs)
    Local oRes := JsonObject():New()

    oRes["UNIDADE"] := cChave
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPort
    oRes["UP"]      := PING(cHost, nPort, nTimeoutMs)
    oRes["ERRO"]    := ""
Return oRes
```

Substitua por:

```advpl
User Function MonPingServico(cChave, cHost, nPort, nTimeoutMs)
    Local oRes := JsonObject():New()
    Local nT1

    oRes["UNIDADE"] := cChave
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPort

    nT1 := TimeCounter()
    oRes["UP"]         := PING(cHost, nPort, nTimeoutMs)
    oRes["LATENCIAMS"] := TimeCounter() - nT1
    oRes["ERRO"]       := ""
Return oRes
```

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected (linhas novas):
```
testeLatDbaccess_registrada=SIM
testeLatLicense_registrada=SIM
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw tests/monitor_lib_test.prw
git commit -m "feat: latencia em MonPingServico (dbaccess e license server)"
```

---

### Task 5: `monitor.prw` usa `portaWebapp`; `config.example.json`/README atualizados

**Files:**
- Modify: `src/monitor.prw`
- Modify: `config.example.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: `MonProcessarUnidade(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs, oState, cLogPath, cToken, cChatId)` (assinatura da Task 3).

- [ ] **Step 1: Atualizar `src/monitor.prw`**

Localize a validação de config (bloco que confere `intervaloSegundos`/`timeoutMs`) e adicione, logo depois da validação de `timeoutMs` e antes de `oState := MonLoadState(cStatePath)`, a validação de `portaWebapp`:

```advpl
    If !oConfig:HasProperty("portaWebapp")
        ConOut("ERRO FATAL: config.json sem 'portaWebapp' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'portaWebapp' valido (> 0)")
        Return
    EndIf
    If oConfig["portaWebapp"] <= 0
        ConOut("ERRO FATAL: config.json sem 'portaWebapp' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'portaWebapp' valido (> 0)")
        Return
    EndIf
```

E troque a chamada dentro do `For` (que hoje é `MonProcessarUnidade(aUnidades[i], oConfig["iniPath"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])`) por:

```advpl
            MonProcessarUnidade(aUnidades[i], oConfig["iniPath"], oConfig["portaWebapp"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
```

- [ ] **Step 2: Verificação manual de fumaça**

```bash
cd ~/Projetos/monitor/src
cat > config.json << 'EOF'
{
  "iniPath": "test_smoke.ini",
  "intervaloSegundos": 3,
  "timeoutMs": 500,
  "portaWebapp": 19199,
  "telegramBotToken": "FAKE",
  "telegramChatId": "0",
  "unidades": ["TCPGHOST"]
}
EOF
cat > test_smoke.ini << 'EOF'
[TCPGHOST]
Server=127.0.0.1
EOF
timeout 8 ~/Projetos/AdvPP/advplc run monitor.prw
cat monitor.log
rm -f config.json monitor.log state.json test_smoke.ini
```

Expected: `Monitor iniciado. 1 unidade(s)...`, e `monitor.log` mostrando `TCPGHOST 127.0.0.1:19199 status=DOWN latenciaMs=...` (sem listener na 19199, DOWN é o esperado).

- [ ] **Step 3: Atualizar `config.example.json`**

Adicione a chave `"portaWebapp": 8090` (documentando o valor real usado pelo ambiente do operador) junto das demais:

```json
{
  "iniPath": "C:\\totvs\\appserver.ini",
  "intervaloSegundos": 60,
  "timeoutMs": 3000,
  "portaWebapp": 8090,
  "telegramBotToken": "COLOQUE_O_TOKEN_DO_BOT_AQUI",
  "telegramChatId": "COLOQUE_O_CHAT_ID_AQUI",
  "unidades": ["TCPSP", "TCPRJ", "TCPMG", "TCPGO", "TCPMT", "TCPBA",
               "TCPPE", "TCPCE", "TCPPR", "TCPPA", "TCPRS", "TCPAM",
               "TCPFB", "TCPAF", "TCPOF"],
  "portaDbaccess": 1234,
  "licenseServer": {"host": "10.0.200.98", "port": 5555}
}
```

- [ ] **Step 4: Atualizar `README.md`**

Na seção "Configurar", troque a explicação de `unidades` (que hoje menciona porta lida do `.ini`) e adicione a explicação de `portaWebapp`, deixando claro que a checagem de appserver agora é HTTP:

```markdown
- `portaWebapp`: porta HTTP fixa (ex: `8090`) usada pra checar o appserver
  de cada unidade — o host continua vindo do `.ini` (`Server=` da seção),
  só a porta muda de "a porta do `.ini`" pra essa, fixa. A checagem faz um
  `GET` simples e mede quanto tempo demorou pra responder; qualquer status
  HTTP abaixo de 500 conta como "no ar".
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor.prw config.example.json README.md
git commit -m "feat: monitor.prw usa portaWebapp (checagem HTTP do appserver)"
```

---

### Task 6: `monitor_tui_lib.prw` — renderização da tabela de status

**Files:**
- Create: `src/monitor_tui_lib.prw`
- Create: `tests/monitor_tui_lib_test.prw`

**Interfaces:**
- Consumes: `MonLoadConfig`, `MonGetUnidades`, `MonLoadState`, `MonGetStatusAnterior`, `MonGetLatenciaAnterior` (todas já existentes em `monitor_lib.prw`).
- Produces: `User Function MonTuiLinhaStatus(cChave, cStatus, nLatenciaMs) -> cTexto` — uma linha de texto formatada (nome + status + latência, alinhados); `User Function MonTuiMontarTabela(oConfig, oState) -> cTexto` — monta o corpo da tabela inteira (uma `MonTuiLinhaStatus` por unidade em `MonGetUnidades(oConfig)`, mais uma linha pro dbaccess de cada uma se `portaDbaccess` existir no config, mais uma linha pro license server se `licenseServer` existir).

- [ ] **Step 1: Escrever o teste**

```advpl
#include "monitor_lib.prw"
#include "monitor_tui_lib.prw"

User Function MonitorTuiLibTest()
    Local cLinha := MonTuiLinhaStatus("TCPSP", "UP", 842)
    ConOut("teste1_linha_tem_chave=" + IIF("TCPSP" $ cLinha, "SIM", "NAO"))
    ConOut("teste2_linha_tem_status=" + IIF("UP" $ cLinha, "SIM", "NAO"))
    ConOut("teste3_linha_tem_latencia=" + IIF("842" $ cLinha, "SIM", "NAO"))

    Local cConfigPath := "test_tui_config.json"
    Local oConfig
    Local oState := JsonObject():New()
    Local cTabela

    MemoWrite(cConfigPath, '{"iniPath":"x.ini","intervaloSegundos":60,"timeoutMs":3000,' + ;
                           '"portaWebapp":8090,"unidades":["TCPSP","TCPRJ"],' + ;
                           '"portaDbaccess":1234,"licenseServer":{"host":"10.0.0.1","port":5555}}')
    oConfig := MonLoadConfig(cConfigPath)

    MonSetStatus(oState, "TCPSP", "UP", 100)
    MonSetStatus(oState, "TCPSP_DBACCESS", "UP", 50)
    MonSetStatus(oState, "TCPRJ", "DOWN", 0)
    MonSetStatus(oState, "LICENSE_SERVER", "UP", 30)

    cTabela := MonTuiMontarTabela(oConfig, oState)
    ConOut("teste4_tabela_tem_tcpsp=" + IIF("TCPSP" $ cTabela, "SIM", "NAO"))
    ConOut("teste5_tabela_tem_dbaccess=" + IIF("TCPSP_DBACCESS" $ cTabela, "SIM", "NAO"))
    ConOut("teste6_tabela_tem_tcprj_down=" + IIF("TCPRJ" $ cTabela .And. "DOWN" $ cTabela, "SIM", "NAO"))
    ConOut("teste7_tabela_tem_license=" + IIF("LICENSE_SERVER" $ cTabela, "SIM", "NAO"))

    FErase(cConfigPath)
    ConOut("MONITOR_TUI_LIB_TEST_FIM")
Return
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected: erro de `#include` (arquivo `monitor_tui_lib.prw` ainda não existe) ou `unknown function: MonTuiLinhaStatus`.

- [ ] **Step 3: Implementar `src/monitor_tui_lib.prw`**

```advpl
// TUI do monitor - renderizacao de tabela de status em ASCII

User Function MonTuiLinhaStatus(cChave, cStatus, nLatenciaMs)
    Local cCor := IIF(cStatus == "UP", "42", "196")
Return PadR(cChave, 24) + " " + PadR(cStatus, 6) + " " + PadL(AllTrim(Str(nLatenciaMs)) + "ms", 8)

User Function MonTuiMontarTabela(oConfig, oState)
    Local aUnidades := MonGetUnidades(oConfig)
    Local cCorpo := ""
    Local cUnidade
    Local i

    For i := 1 To Len(aUnidades)
        cUnidade := aUnidades[i]
        cCorpo += MonTuiLinhaStatus(cUnidade, MonGetStatusAnterior(oState, cUnidade), MonGetLatenciaAnterior(oState, cUnidade)) + Chr(10)

        If oConfig:HasProperty("portaDbaccess")
            cCorpo += MonTuiLinhaStatus(cUnidade + "_DBACCESS", MonGetStatusAnterior(oState, cUnidade + "_DBACCESS"), MonGetLatenciaAnterior(oState, cUnidade + "_DBACCESS")) + Chr(10)
        EndIf
    Next

    If oConfig:HasProperty("licenseServer")
        cCorpo += MonTuiLinhaStatus("LICENSE_SERVER", MonGetStatusAnterior(oState, "LICENSE_SERVER"), MonGetLatenciaAnterior(oState, "LICENSE_SERVER")) + Chr(10)
    EndIf
Return cCorpo
```

`PadR`/`PadL` são funções padrão de formatação de string do AdvPL (preenchimento à direita/esquerda) — já nativas do AdvPP, sem necessidade de implementar.

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected:
```
teste1_linha_tem_chave=SIM
teste2_linha_tem_status=SIM
teste3_linha_tem_latencia=SIM
teste4_tabela_tem_tcpsp=SIM
teste5_tabela_tem_dbaccess=SIM
teste6_tabela_tem_tcprj_down=SIM
teste7_tabela_tem_license=SIM
MONITOR_TUI_LIB_TEST_FIM
```

Se `PadR`/`PadL` não existirem nesta versão do AdvPP (erro `unknown function`), troque por concatenação manual com `Space()`: `cChave + Space(24 - Len(cChave))` no lugar de `PadR(cChave, 24)`, mesma ideia pra `PadL`. Confirme qual caminho funcionou antes de prosseguir.

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_tui_lib.prw tests/monitor_tui_lib_test.prw
git commit -m "feat: renderizacao da tabela de status da TUI"
```

---

### Task 7: `monitor_tui_lib.prw` — controle de processo (iniciar/parar/status) e `monitor_tui.prw`

**Files:**
- Modify: `src/monitor_tui_lib.prw` (adiciona funções de controle de processo)
- Create: `src/monitor_tui.prw`
- Modify: `tests/monitor_tui_lib_test.prw` (testa só a lógica que não depende do SO Windows)

**Interfaces:**
- Consumes: `MonTuiMontarTabela` (Task 6), tudo de `monitor_lib.prw`.
- Produces:
  - `User Function MonTuiProcessoEstaRodando(cSaidaTasklist) -> lRodando` — função pura (recebe a saída do `tasklist` já capturada como string, não chama nada do SO ela mesma) que decide se o processo aparece rodando. Separar a decisão da chamada ao SO é o que permite testar a lógica sem depender do Windows.
  - `User Function MonTuiIniciarServico(cCaminhoExe) -> Nil` — dispara `MonitorService.exe` desanexado via `WaitRun`.
  - `User Function MonTuiPararServico() -> Nil` — mata o processo via `WaitRun("taskkill ...")`.
  - `User Function MonTuiVerificarServicoRodando() -> lRodando` — roda `tasklist` via `ProcRun`, acumula a saída, delega a decisão pra `MonTuiProcessoEstaRodando`.
  - `User Function MonitorTuiMain()` (em `monitor_tui.prw`) — entry point: `UiAltScreenEnter()`, loop lendo `config.json`/`state.json` a cada 2 segundos e redesenhando com `UiStreamBox`/`MonTuiMontarTabela`, checando teclado pra ações (ver Step 3), `UiAltScreenExit()` ao sair.

- [ ] **Step 1: Escrever o teste da função pura (`MonTuiProcessoEstaRodando`)**

Adicione ao final de `tests/monitor_tui_lib_test.prw`, antes do `ConOut("MONITOR_TUI_LIB_TEST_FIM")`:

```advpl
    Local cSaidaComProcesso := '"MonitorService.exe","1234","Console","1","10.240 K"'
    Local cSaidaSemProcesso := "INFO: No tasks are running which match the specified criteria."

    ConOut("teste8_detecta_rodando=" + IIF(MonTuiProcessoEstaRodando(cSaidaComProcesso), "SIM", "NAO"))
    ConOut("teste9_detecta_parado=" + IIF(MonTuiProcessoEstaRodando(cSaidaSemProcesso), "SIM", "NAO"))
    ConOut("teste10_detecta_vazio=" + IIF(MonTuiProcessoEstaRodando(""), "SIM", "NAO"))
```

- [ ] **Step 2: Rodar e confirmar falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected: erro `unknown function: MonTuiProcessoEstaRodando`.

- [ ] **Step 3: Implementar em `src/monitor_tui_lib.prw`**

Adicione ao final do arquivo:

```advpl
User Function MonTuiProcessoEstaRodando(cSaidaTasklist)
Return "MonitorService.exe" $ cSaidaTasklist

User Function MonTuiVerificarServicoRodando()
    Local cSaida := ""
    Local bAcumula := {|cLinha| cSaida += cLinha + Chr(10)}

    ProcRun("tasklist", {"/FI", "IMAGENAME eq MonitorService.exe", "/FO", "CSV", "/NH"}, bAcumula)
Return MonTuiProcessoEstaRodando(cSaida)

User Function MonTuiIniciarServico(cCaminhoExe)
    WaitRun("cmd /c start " + cCaminhoExe)
Return Nil

User Function MonTuiPararServico()
    WaitRun("taskkill /IM MonitorService.exe /F")
Return Nil
```

- [ ] **Step 4: Rodar e confirmar sucesso do teste da função pura**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected (linhas novas):
```
teste8_detecta_rodando=SIM
teste9_detecta_parado=NAO
teste10_detecta_vazio=NAO
MONITOR_TUI_LIB_TEST_FIM
```

`MonTuiVerificarServicoRodando`/`MonTuiIniciarServico`/`MonTuiPararServico` chamam `tasklist`/`cmd`/`taskkill`, comandos que só existem no Windows — **não têm teste automatizado neste repositório** (rodar `tasklist` num Linux de desenvolvimento falha na criação do processo, não na lógica). A cobertura real delas é a função pura `MonTuiProcessoEstaRodando` (testada acima) mais a verificação manual do Step 6.

- [ ] **Step 5: Escrever `src/monitor_tui.prw`**

```advpl
#include "monitor_lib.prw"
#include "monitor_tui_lib.prw"

User Function MonitorTuiMain()
    Local cConfigPath := "config.json"
    Local cStatePath  := "state.json"
    Local cLogPath    := "monitor.log"
    Local oConfig
    Local oState
    Local cTabela
    Local lSair := .F.
    Local nOpcao
    Local cLinhasLog

    oConfig := MonLoadConfig(cConfigPath)
    If oConfig == Nil
        ConOut("ERRO FATAL: nao foi possivel ler " + cConfigPath)
        Return
    EndIf

    UiAltScreenEnter()

    While !lSair
        oState := MonLoadState(cStatePath)
        cTabela := MonTuiMontarTabela(oConfig, oState)
        UiStreamBox("Monitor Protheus - Status", cTabela + Chr(10) + ;
            "Servico: " + IIF(MonTuiVerificarServicoRodando(), "RODANDO", "PARADO") + Chr(10) + Chr(10) + ;
            "[1] Iniciar servico  [2] Parar servico  [3] Ver log  [4] Sair", "39", 70)

        nOpcao := Val(FWGetText("Escolha uma opcao (1-4, ou aguarde 5s pra atualizar)", "", .F.))

        Do Case
        Case nOpcao == 1
            MonTuiIniciarServico("MonitorService.exe")
        Case nOpcao == 2
            MonTuiPararServico()
        Case nOpcao == 3
            cLinhasLog := MemoRead(cLogPath)
            ConOut(cLinhasLog)
            FWGetText("Pressione Enter para voltar", "", .F.)
        Case nOpcao == 4
            lSair := .T.
        EndCase
    EndDo

    UiStreamReset()
    UiAltScreenExit()
Return
```

- [ ] **Step 6: Verificação manual na máquina Windows**

Este passo não pode ser automatizado neste ambiente Linux de desenvolvimento — precisa de uma máquina Windows com `MonitorService.exe`/`MonitorTUI.exe` (gerados na Task 8) ou, provisoriamente, com `advplc.exe run monitor_tui.prw` a partir de um checkout do AdvPP 3.0.4:

1. Abra um `cmd.exe`, navegue até a pasta com `monitor_tui.prw`/`monitor_lib.prw`/`monitor_tui_lib.prw`/um `config.json` válido.
2. Rode `advplc.exe run monitor_tui.prw` (ou o `.exe` compilado).
3. Confirme que a tabela aparece em ASCII com bordas, sem abrir nenhuma janela separada.
4. Pressione `1`, confirme que `MonitorService.exe` aparece no Gerenciador de Tarefas rodando, e que o prompt da TUI volta imediatamente (não trava esperando o serviço terminar).
5. Pressione `2`, confirme que o processo some do Gerenciador de Tarefas.
6. Pressione `4`, confirme que a tela volta ao normal do terminal (sem lixo visual deixado pela tela alternativa).
7. Feche o `cmd.exe` e reabra `monitor_tui.prw` por duplo-clique no Explorer (não a partir de um terminal) — confirme que, como esperado e documentado, isso abre uma janela Fyne em vez do console (comportamento do AdvPP quando stdin não é TTY e há `FWGetText`/`FWMenuSelect` no bytecode) — é exatamente o motivo do `abrir-painel.bat` da Task 8.

- [ ] **Step 7: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_tui_lib.prw src/monitor_tui.prw tests/monitor_tui_lib_test.prw
git commit -m "feat: controle de processo e entry point da TUI"
```

---

### Task 8: CI (GitHub Actions), `ADVPP_VERSION`, `abrir-painel.bat`, README final

**Files:**
- Create: `ADVPP_VERSION`
- Create: `.github/workflows/release.yml`
- Create: `abrir-painel.bat`
- Modify: `README.md`

**Interfaces:**
- Consumes: `src/monitor.prw` (Task 5), `src/monitor_tui.prw` (Task 7) — os dois arquivos que o CI compila.

- [ ] **Step 1: Criar `ADVPP_VERSION`**

```bash
cd ~/Projetos/monitor
printf '3.0.4' > ADVPP_VERSION
```

(Sem quebra de linha ao final, mesma convenção do `GesCon` — o workflow lê o conteúdo bruto do arquivo.)

- [ ] **Step 2: Criar `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

env:
  GO_VERSION: "1.24"

jobs:
  # O advplc build embute Fyne no stub (mesmo para um programa TUI como
  # este) e precisa de CGO pra linkar -- so compilamos no windows-latest,
  # que ja vem com o toolchain necessario (confirmado: o workflow do
  # GesCon nao instala nenhum compilador C extra pra Windows, so pra
  # Linux). E o unico alvo que este projeto precisa mesmo.
  build:
    runs-on: windows-latest
    steps:
      - name: Checkout monitor
        uses: actions/checkout@v4
        with:
          path: monitor

      - name: Le a versao do AdvPP
        id: advpp
        shell: bash
        run: echo "versao=v$(tr -d ' \n\r' < monitor/ADVPP_VERSION)" >> "$GITHUB_OUTPUT"

      - name: Checkout AdvPP (compilador)
        uses: actions/checkout@v4
        with:
          repository: peder1981/AdvPP
          ref: ${{ steps.advpp.outputs.versao }}
          path: AdvPP

      - uses: actions/setup-go@v5
        with:
          go-version: ${{ env.GO_VERSION }}

      - name: Build advplc
        shell: bash
        run: |
          cd AdvPP
          go build -o "$RUNNER_TEMP/advplc.exe" ./cmd/advplc

      - name: Build MonitorService.exe e MonitorTUI.exe
        shell: bash
        env:
          ADVPP_SRC: ${{ github.workspace }}/AdvPP
        run: |
          cd monitor
          "$RUNNER_TEMP/advplc.exe" build src/monitor.prw -o MonitorService.exe
          "$RUNNER_TEMP/advplc.exe" build src/monitor_tui.prw -o MonitorTUI.exe

      - uses: actions/upload-artifact@v4
        with:
          name: monitor-windows-amd64
          path: |
            monitor/MonitorService.exe
            monitor/MonitorTUI.exe
            monitor/config.example.json
            monitor/abrir-painel.bat

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artefatos
      - name: Publica os binarios no release
        uses: softprops/action-gh-release@v2
        with:
          files: artefatos/**/*
          generate_release_notes: true
```

- [ ] **Step 3: Criar `abrir-painel.bat`**

```bat
@echo off
rem abrir-painel.bat -- garante que MonitorTUI.exe roda dentro de um
rem console de verdade (stdin TTY). Aberto direto por duplo-clique no
rem Explorer, o AdvPP acha que deve abrir uma janela Fyne em vez do
rem console -- este .bat evita isso.
cd /d "%~dp0"
MonitorTUI.exe
pause
```

- [ ] **Step 4: Atualizar `README.md`**

Reescreva a seção de instalação/execução (a que hoje descreve `advplc.exe run monitor.prw`) para refletir os dois `.exe` compilados:

```markdown
## Instalar

1. Baixe o zip mais recente da aba Releases deste repositório
   (`monitor-windows-amd64`) — contém `MonitorService.exe`,
   `MonitorTUI.exe`, `config.example.json` e `abrir-painel.bat`, todos
   já compilados. Nenhum toolchain (MinGW, Go, AdvPP) precisa ser
   instalado na máquina Windows que vai rodar o monitor.
2. Copie os quatro arquivos pra uma pasta fixa (ex:
   `C:\MonitorProtheus\`).
3. Copie `config.example.json` para `config.json` na mesma pasta e
   preencha (ver "Configurar" abaixo).

## Rodar

- **Serviço de fundo**: agende `MonitorService.exe` no Task Scheduler
  do Windows como "ao iniciar o sistema", com "Start in" apontando pra
  essa mesma pasta (os arquivos `config.json`/`state.json`/
  `monitor.log` são caminhos relativos). Sobrevive a reboot e a troca
  de sessão RDP.
- **Painel de controle**: sempre abra **`abrir-painel.bat`**, nunca
  `MonitorTUI.exe` diretamente — o `.bat` garante que a interface abre
  dentro de um console de texto; aberto direto (duplo-clique), o
  interpretador entende que deve abrir uma janela gráfica em vez do
  painel ASCII. Do painel dá pra ver o status/latência de cada
  unidade, iniciar/parar o `MonitorService`, e ver as últimas linhas
  do log — tudo com teclado, sem precisar saber nenhum comando.
```

Remova da seção "Configurar" qualquer menção a compilar via `advplc build`/CI feita manualmente pelo operador — isso agora é responsabilidade do workflow de CI, documentado em `.github/workflows/release.yml`, não do usuário final.

- [ ] **Step 5: Verificação manual do workflow**

Este passo não roda de fato neste ambiente (exige um push de tag pra um repositório remoto real no GitHub, fora do escopo do que pode ser testado localmente). Ao integrar este plano:

1. Configure um repositório remoto real pro projeto `monitor` (se ainda não existir).
2. Dê push de uma tag `v0.1.0-teste` e confirme, na aba Actions do GitHub, que o workflow `Release` roda até o fim sem erro, publicando `MonitorService.exe`/`MonitorTUI.exe` como release.
3. Baixe o zip publicado numa máquina Windows real (ou VM) e confirme que os dois `.exe` rodam sem pedir nenhuma instalação adicional.

- [ ] **Step 6: Commit**

```bash
cd ~/Projetos/monitor
git add ADVPP_VERSION .github/workflows/release.yml abrir-painel.bat README.md
git commit -m "feat: pipeline de CI (GitHub Actions) e instalador via release"
```

---

## Self-Review (feito ao escrever este plano)

- **Cobertura da spec:** checagem HTTP+latência do appserver (Task 1, 3), latência de dbaccess/license (Task 4), formato de `state.json` corrigido em relação à spec original — a spec foi editada durante a escrita deste plano após um teste empírico revelar que objeto aninhado não serializa em `ToJson()` (Task 2), config `portaWebapp` (Task 5), TUI com tabela/controle de processo (Task 6, 7), pipeline de CI + distribuição sem toolchain na máquina alvo (Task 8). Item "fora de escopo" da spec (Windows Service via SCM, métricas internas via `GetUserInfoArray`, gráfico de série temporal) — nenhuma task tenta implementá-los, como esperado.
- **Placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem código completo. Onde uma dependência do ambiente Windows real não pode ser testada neste repositório (comandos `tasklist`/`cmd start`/`taskkill`, e o próprio workflow de CI), o plano diz isso explicitamente e prescreve uma verificação manual concreta, em vez de fingir uma automação que não existe.
- **Consistência de tipos:** `MonProcessarUnidade` (Task 3) usa a mesma ordem de parâmetros em `monitor.prw` (Task 5): `(cUnidade, cIniPath, nPortaWebapp, nTimeoutMs, oState, cLogPath, cToken, cChatId)`. `MonSetStatus` com 4 parâmetros (Task 2) é chamada assim em `MonProcessarResultado` (Task 3) e em nenhum outro lugar diretamente. `oRes["LATENCIAMS"]` é escrito por `MonCheckWebapp` (Task 1) e por `MonPingServico` (Task 4), e lido só por `MonProcessarResultado` (Task 3) — ambas as fontes preenchem a mesma chave, com o mesmo tipo (numeric, ms). `MonTuiMontarTabela`/`MonTuiLinhaStatus` (Task 6) usam exatamente as chaves de estado que `MonProcessarUnidade`/`MonProcessarDbaccess`/`MonProcessarLicenseServer` já gravam (`<UNIDADE>`, `<UNIDADE>_DBACCESS`, `LICENSE_SERVER`).
