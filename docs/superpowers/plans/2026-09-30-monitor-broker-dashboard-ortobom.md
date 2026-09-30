# Monitor — TOTVS Broker + Dashboard Web + Config Ortobom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trocar a checagem de unidade do monitor (hoje `.ini` do SmartClient + `GET /webapp/`) por uma lista 100% parametrizável em `config.json` (host+porta direto) checando `/totvs_broker_query`, interpretando o HTML de resposta do TOTVS Broker (sessões/conexões/tabela de servers, incluindo quarentena), consolidando tudo num dashboard web servido pelo próprio `MonitorService`, e publicando um `config.example.json` pré-preenchido com o ambiente Ortobom.

**Architecture:** Dois arquivos `.prw` novos — `src/monitor_broker.prw` (parser de HTML sem regex, via `At()`/`SubStr()`/`StrTokArr()` sobre âncoras ASCII, e a checagem/alerta do broker) e `src/monitor_dashboard.prw` (geração de HTML, persistência de `dashboard.json` a cada ciclo, e o servidor HTTP via `WSRestServer`, subido em job assíncrono via `StartJob` pra não bloquear o loop de checagem). `src/monitor_lib.prw` perde `MonCheckWebapp`/`MonProcessarUnidade` (mudam de lugar e de forma) e ganha `Return oRes` em `MonProcessarDbaccess`/`MonProcessarLicenseServer` (o dashboard precisa do resultado de cada ciclo). `src/monitor.prw` perde a dependência do `.ini` e passa a ler `unidades` como lista de objetos `{nome,host,porta}`.

**Tech Stack:** AdvPL via AdvPP (`advplc`). Nativas usadas: `FWHttpGet`/`FWHttpBody`/`FWHttpTimeout` (já em uso), `At`/`RAt`/`SubStr`/`StrTokArr`/`AllTrim`/`IsDigit`/`Val` (extração de HTML sem regex — AdvPP não expõe nativa de regex), `WSRestServer` (classe nativa REST real, resposta HTML crua via `Return {"__RAW_HTTP__", cContentType, cBody}` — só existe a partir da tag `v4.2.0`), `StartJob` (job assíncrono em VM isolada).

**Spec:** `docs/superpowers/specs/2026-09-30-monitor-broker-dashboard-ortobom.md`

## Global Constraints

- `ADVPP_VERSION` sobe de `3.0.4` para `4.2.1` — obrigatório pra `WSRestServer` devolver HTML cru (recurso introduzido na tag `v4.2.0`).
- Toda âncora de texto usada pra extrair dado do HTML do broker é ASCII puro (nunca contém acento) — a página declara `charset=Windows-1252` e o corpo chega como o broker gerou; comparar bytes acentuados arriscaria mismatch de encoding. Âncoras usadas: `" ativas</span>"`, `"sess"`, `"conex"`, `"Vers"`, `"ServerStatus/"`, `"Servers ("`, `"<table"`, `"</table>"`, `"<tr>"`, `"<td>"`, `"</td>"`.
- Mapeamento de coluna da tabela de servers é fixo por variante de broker (`"HTTP"` ou `"SMARTCLIENT"`, detectada por `MonModoBroker`) — não há parsing genérico de cabeçalho. Só essas duas variantes têm fixture real validada.
- `unidades` no `config.json` é lista de objetos `{nome, host, porta}` — o `.ini` do SmartClient (`iniPath`) deixa de existir no schema.
- `dashboardPorta` é opcional-mas-avisada: ausente/inválida loga aviso e desliga só o dashboard, resto do monitor funciona normal (mesmo padrão de `portaDbaccess`/`licenseServer`).
- Todo teste segue o padrão já usado no repo: `ConOut("testeN_descricao=" + IIF(condicao, "SIM", "NAO"))`, sem framework de assert, arquivo `.prw` de teste terminando com uma linha `ConOut("..._FIM")`.

## Review Focus

- **HTML do broker chega truncado ou com o body vazio** (timeout no meio da leitura, ou `FWHttpBody()` vazio) — `MonParseBrokerHtml("")` não pode estourar exceção; deve devolver `VALIDO=.F.` e campos zerados (coberto no Task 1, teste de string vazia).
- **Servidor no ar mas não é o broker** (outro serviço HTTP respondendo na porta configurada por engano) — `MonCheckBroker` deve marcar `UP=.F.` mesmo com HTTP 200, não confundir "respondeu" com "é o broker de verdade" (coberto no Task 2, contra o servidor de teste compartilhado que devolve `"ok"` puro).
- **`dashboard.json` ainda não existe** (primeiro ciclo do `MonitorService` ainda não rodou, mas alguém já abriu o navegador) — `MonRotaDashboard` não pode estourar exceção nem devolver JSON cru pro navegador, tem que devolver uma página HTML válida avisando que ainda não há dados (coberto no Task 5).
- **`dashboard.json` corrompido** (processo morto no meio da escrita) — mesma proteção que `MonLoadState` já tem pra `state.json` (`FromJson` falha → não deixa o handler quebrar) precisa existir também pro dashboard (coberto no Task 5).
- **Unidade com `host`/`porta` ausente ou mal formada no config** (erro de digitação editando a lista manualmente) — não pode derrubar o loop inteiro do `MonitorMain`; deve degradar pra "essa unidade sempre aparece DOWN" (mesmo caminho que host inalcançável), não uma exceção não tratada que mata o processo (coberto no Task 2, `MonCheckBroker` com host vazio).

---

## Arquivos deste plano

```
monitor/
  ADVPP_VERSION                     # modificado: 3.0.4 -> 4.2.1
  config.example.json               # modificado: schema novo, unidades Ortobom
  README.md                         # modificado: doc do config/endpoint/dashboard
  src/
    monitor_lib.prw                 # modificado: remove MonCheckWebapp/MonProcessarUnidade; Return oRes em Dbaccess/LicenseServer
    monitor_broker.prw              # novo: parser HTML + MonCheckBroker + MonProcessarUnidade + alerta granular por server
    monitor_dashboard.prw           # novo: dashboard.json + HTML + rota + servidor
    monitor.prw                     # modificado: config novo, sobe dashboard, escreve dashboard.json por ciclo
  tests/
    fixtures/
      broker_http_ok.html           # novo: fixture real (broker "para HTTP", saudavel)
      broker_smartclient_quarentena.html  # novo: fixture real (broker "para SmartClient", 9/14 em quarentena)
    monitor_lib_test.prw            # modificado: remove testes de MonCheckWebapp/.ini/MonProcessarUnidade; schema novo de unidades
    monitor_broker_test.prw         # novo
    monitor_dashboard_test.prw      # novo
```

---

### Task 1: Parser do HTML do broker (`monitor_broker.prw`)

**Files:**
- Create: `tests/fixtures/broker_http_ok.html`
- Create: `tests/fixtures/broker_smartclient_quarentena.html`
- Create: `src/monitor_broker.prw`
- Create: `tests/monitor_broker_test.prw`

**Interfaces:**
- Produces: `MonModoBroker(cHtml) -> cModo` (`"HTTP"`/`"SMARTCLIENT"`/`""`), `MonSoNumero(cTexto) -> nNumero`, `MonExtrairAtivas(cHtml) -> oJson{SESSOESATIVAS,CONEXOESATIVAS}`, `MonExtrairVersao(cHtml) -> cVersao`, `MonExtrairHostPorta(cCelula) -> cHostPorta`, `MonCelulasLinha(cLinha) -> aCelulas`, `MonExtrairLinhaServer(cLinha, cModo) -> oServ{HOSTPORTA,SESSOES,CONEXOES,USUARIOS,THREADS,MEMORIAKB,CPU,UPTIME,PID,STATUS,INICIOQUARENTENA,MOTIVO}`, `MonExtrairServers(cHtml, cModo) -> aServers`, `MonParseBrokerHtml(cHtml) -> oJson{VALIDO,SESSOESATIVAS,CONEXOESATIVAS,VERSAO,SERVERS}` — usado pelo Task 2.

- [ ] **Step 1: Criar as fixtures reais**

Crie `tests/fixtures/broker_http_ok.html` com exatamente este conteúdo (resposta real de um TOTVS Broker "para HTTP" saudável, 5 servers, colada pelo operador):

```html
<!DOCTYPE html><html><head><title> TOTVS Broker para HTTP</title><meta http-equiv='cache-control' content='no-cache' charset='Windows-1252'></head><body style='color:blue; background-color:#fffffa; padding: 10px; text-align: center;' onload="checkStrorage();">
<style>
.sortable th {
   cursor: pointer;
}
.sortable th.no-sort {
   pointer-events: none;
}
.sortable th::after,
.sortable th::before {
 transition: color 0.2s ease-in-out;
 font-size: 1.2em;
 color: transparent;
}
.sortable th::after {
   margin-left: 3px;
   content: '\025B8';
}
.sortable th:hover::after {
   color: inherit;
}
.sortable th.dir-d::after {
   color: inherit;
   content: '\025BE';
}
.sortable th.dir-u::after {
   color: inherit;
   content: '\025B4';
}

table, table td{border: solid thin lightgray; border-collapse: collapse; white-space:pre;}
th{background: PeachPuff; border: solid thin lightgray;}

.tooltiptext {
  visibility: hidden;
  background-color: black;
  color: #ffffff;
  text-align: center;
  padding: 5px 0;
  border-radius: 6px;
  position: absolute;
  z-index: 1;
}

.isDisabled {
  background-color: yellow;
  color: black;
  font-weight: bold;
  position: relative;
  display: inline-block;
  border-bottom: 1px dotted black;
  cursor: pointer;
}

.inQuarantine {
  background-color: #FF8488;
  color: black;
  font-weight: bold
}

.isBlockedByScalability {
  color: red;
  font-weight: bold
}

.defaultTooltip {
  font-weight: normal
}

.isDisabled:hover .tooltiptext {
  visibility: visible;
}

.inQuarantine:hover .tooltiptext {
  visibility: visible;
}

.isBlockedByScalability:hover .tooltiptext {
  visibility: visible;
}

.defaultTooltip:hover .tooltiptext {
  visibility: visible;
}
</style>

<script>
function findElementRecursive(element, tag) {
  return element.nodeName === tag ? element :
    findElementRecursive(element.parentNode, tag)
}

function sortTH(element, dirSave, alt_sort) {
  try {
    var regex_dir = / dir-(u|d) /
    var descending_th_class = ' dir-d '
    var ascending_th_class = ' dir-u '
    var descending_th_class = ' dir-d '
    var ascending_th_class = ' dir-u '
    var ascending_table_sort_class = 'asc'
    var descending_table_sort_class = 'desc'
    var regex_dir = / dir-(u|d) /
    var regex_table = /\bsortable\b/
    if (element === null) {
      return;
    }
    var tr = findElementRecursive(element, 'TR')
    if (tr === null) {
      return;
    }
    var table = findElementRecursive(tr, 'TABLE')
    if (table === null) {
      return;
    }

    function reClassify(element, dir) {
      element.className = element.className.replace(regex_dir, '') + dir
    }
    function getValue(element) {
      return (
        (alt_sort && element.getAttribute('data-sort-alt')) ||
      element.getAttribute('data-sort') || element.innerText
      )
    }
    if (regex_table.test(table.className)) {
      var column_index
      var nodes = tr.cells
      for (var i = 0; i < nodes.length; i++) {
        if (nodes[i] === element) {
          column_index = element.getAttribute('data-sort-col') || i
        } else {
          reClassify(nodes[i], '')
        }
      }
      var dir = descending_th_class
      if ( dirSave === ascending_table_sort_class ) {
        dir = ascending_th_class;
      } else if ( dirSave === descending_table_sort_class ) {
        dir = descending_th_class;
      } else {
        dir = descending_th_class
        dirSave = descending_table_sort_class
        if (
          element.className.indexOf(descending_th_class) !== -1 ||
          (table.className.indexOf(ascending_table_sort_class) !== -1 &&
            element.className.indexOf(ascending_th_class) == -1)
        ) {
          dir = ascending_th_class
          dirSave = ascending_table_sort_class
        }
      }
      reClassify(element, dir)
      var org_tbody = table.tBodies[0]
      var rows = [].slice.call(org_tbody.rows, 0)
      var reverse = dir === ascending_th_class
      rows.sort(function (a, b) {
        var x = getValue((reverse ? a : b).cells[column_index])
        var y = getValue((reverse ? b : a).cells[column_index])
        return isNaN(x - y) ? x.localeCompare(y) : x - y
      })
      var clone_tbody = org_tbody.cloneNode()
      while (rows.length) {
        clone_tbody.appendChild(rows.splice(0, 1)[0])
      }
      table.replaceChild(clone_tbody, org_tbody)

      sessionStorage.setItem('sortBy', column_index);
      sessionStorage.setItem('sortByDir', dirSave);
      sessionStorage.setItem('sortAlt', alt_sort);
    }
  } catch (error) {
  }
}

document.addEventListener('click', function (e) {
  try {
    var alt_sort = e.shiftKey || e.altKey
    var element = findElementRecursive(e.target, 'TH');

    sortTH(element, "", alt_sort);
  } catch (error) {
  }
});

function checkStrorage() {
  var sortBy= sessionStorage.getItem('sortBy');
  var sortByDir = sessionStorage.getItem('sortByDir');
  var sortAlt = sessionStorage.getItem('sortAlt');

  if (sortBy !== null && sortByDir !== null && sortAlt !== null) {
    var n = parseInt(sortBy);
    table = document.getElementsByClassName("sortable")[0];
    var element = table.getElementsByTagName('TH')[n];
    sortTH(element, sortByDir, sortAlt);
  }
}
</script>
<div style='display: inline-block;'><div style='text-align: left; color:blue; border: solid thin lightgray; background-color:whitesmoke; display: inline-block; padding: 10px; margin: auto'><h2>TOTVS Broker para HTTP em 10.0.100.115:8090</h2>Opção: STATUS<br><br>Versão 24.3.1.9 guapor lin64 rel 0b4bfda  Jul 15 2026 13:29:54 <br><br>Este broker aceita conexões de aplicações <span style='background-color:yellow'> HTTP</span>.<br>Broker iniciou operação às <span style='background-color:yellow'>03:10:02</span> de <span style='background-color:yellow'>30/09/2026</span>, agora é <span style='background-color:yellow'>10:22:58</span> de <span style='background-color:yellow'>30/09/2026</span>.<br>Existem <span style='background-color:yellow'>59 sessões ativas</span> no momento.<br>Houve 203 sessões desde o início da operação do broker.<br>Existem 175 conexões ativas no momento.<br>Houve 2457 conexões TCP desde o início da operação do broker.<br>Última conexão TCP foi às 10:22:30 de 30/09/2026.<br>Instância de execução com id 3259824.<br>Método de balanceamento: <span style='background-color:yellow'>consumo de memória</span>.<br>Webmonitor está ativo.<br>Consulta efetuada pelo client 10.0.100.203:52382.<br></div><br></div><br><div style='border: solid thin lightgray;padding: 10px; margin-top: 10px;background-color: whitesmoke; display: inline-block;'><div>Servers (5)<br><div><table class="sortable"><thead><tr><th>Server</th><th>Sessões</th><th>Conexões</th><th>Início ocorrência</th><th>Motivos</th><th>Usuários </th><th>Threads</th><th>Memória(Kb)</th><th>Cpu(%/5s)</th><th>upTime</th><th>pid</th></tr></thead><tr><td>(   1) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1236">10.0.100.115:1236</a></td><td>    11</td><td>    33</td><td>-</td><td>-</td><td>    25</td><td>    65</td><td>   4.087.092</td><td>  37%</td><td>2026/09/30 03:10:02</td><td>    3259754</td></tr><tr><td>(   2) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1237">10.0.100.115:1237</a></td><td>    14</td><td>    52</td><td>-</td><td>-</td><td>    29</td><td>    75</td><td>   4.587.544</td><td>  37%</td><td>2026/09/30 03:10:02</td><td>    3259765</td></tr><tr><td>(   3) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1238">10.0.100.115:1238</a></td><td>    16</td><td>    45</td><td>-</td><td>-</td><td>    27</td><td>    69</td><td>   4.101.660</td><td>  37%</td><td>2026/09/30 03:10:02</td><td>    3259776</td></tr><tr><td>(   4) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1239">10.0.100.115:1239</a></td><td>     8</td><td>    20</td><td>-</td><td>-</td><td>    27</td><td>    69</td><td>   4.582.344</td><td>  37%</td><td>2026/09/30 03:10:02</td><td>    3259788</td></tr><tr><td>(   5) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.115:1240">10.0.100.115:1240</a></td><td>    10</td><td>    25</td><td>-</td><td>-</td><td>    31</td><td>    77</td><td>   4.554.052</td><td>  37%</td><td>2026/09/30 03:10:02</td><td>    3259800</td></tr></table><table><br><thead><th></th><th>Sessões</th><th>Conexões</th><th>Usuários</th></tr></thead><td> <b>TOTAL</b> </td><td>59</td><td>175</td><td>139</td></tr></table></div></div>Usuários, threads, memória e cpu são informados pelos servidores configurados.<br>A coluna "Usuários" corresponde à mesma coluna no WebMonitor.<br></div></body></html>
```

Crie `tests/fixtures/broker_smartclient_quarentena.html` com exatamente este conteúdo (broker "para SmartClient" real, 14 servers, 9 em quarentena):

```html
<!DOCTYPE html><html><head> <meta http-equiv='cache-control' content='no-cache'> </head><body style='color:blue; background-color:#fffffa; padding: 10px; text-align: center;'><div style='display: inline-block;'><head><title> TOTVS Broker para SmartClient</title></head><div style='text-align: left; color:blue; border: solid thin lightgray; background-color:whitesmoke; display: inline-block; padding: 10px; margin: auto'><h2>TOTVS Broker para SmartClient em 10.0.100.38:4000</h2>Opção: STATUS<br><br>Versão: Broker 20.3.2.11 doce lin64 rel [rev-42186] { Jul  3 2024 23:54:32 } [[3467]]<br><br>Este broker aceita conexões de aplicações <span style='background-color:yellow'> SmartClient</span>.<br>Broker iniciou operação às <span style='background-color:yellow'>07:22:13</span> de <span style='background-color:yellow'>30/09/2026</span>, agora é <span style='background-color:yellow'>12:32:32</span> de <span style='background-color:yellow'>30/09/2026</span>.<br>Existem <span style='background-color:yellow'>43 conexões ativas</span> no momento.<br>Houve 285 conexões desde o início da operação do broker.<br>Última conexão foi às 12:31:46 de 30/09/2026.<br>Houve 31 reconexões desde o início da operação do broker.<br>Instância de execução com id [47CD8C60-C4FE4C1E-B2233ABC-296F5D06].<br>Consulta efetuada pelo client 10.0.100.203:64300.<br>Número máximo de conexões simultâneas: 10000.<br></div><br></div><br><div style='border: solid thin lightgray;padding: 10px; margin-top: 10px;background-color: whitesmoke; display: inline-block;'><div>Servers (14)<br><div><style>table, th, td { border-collapse: collapse; border: 1px solid lightgray; padding: 3px; }</style><table><tr><th>Server</th><td>Conexões</td><td>Quarentena</td><td>Usuários </td><td>Threads</td><td>Memória(Kb)*</td><td>Cpu(%/5s)</td></tr><tr><td>(1) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1236">10.0.100.38:1236</a></td><td>8</td><td>-</td><td>8</td><td>32</td><td>2.130.092</td><td>54%</td></tr><tr><td>(2) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1237">10.0.100.38:1237</a></td><td>7</td><td>-</td><td>7</td><td>30</td><td>2.061.812</td><td>54%</td></tr><tr><td>(3) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1238">10.0.100.38:1238</a></td><td>10</td><td>-</td><td>10</td><td>36</td><td>2.162.348</td><td>54%</td></tr><tr><td>(4) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1239">10.0.100.38:1239</a></td><td>10</td><td>-</td><td>10</td><td>36</td><td>1.979.220</td><td>54%</td></tr><tr><td>(5) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1240">10.0.100.38:1240</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(6) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1241">10.0.100.38:1241</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(7) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1242">10.0.100.38:1242</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(8) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1243">10.0.100.38:1243</a></td><td>8</td><td>-</td><td>8</td><td>32</td><td>1.925.184</td><td>54%</td></tr><tr><td>(9) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1244">10.0.100.38:1244</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(10) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1245">10.0.100.38:1245</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(11) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1246">10.0.100.38:1246</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(12) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1247">10.0.100.38:1247</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(13) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1248">10.0.100.38:1248</a></td><td>0</td><td>12:34:30</td><td>?</td><td>?</td><td>?</td><td>?</td></tr><tr><td>(14) <a href="/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.38:1249">10.0.100.38:1249</a></td><td>0</td><td>12:34:31</td><td>?</td><td>?</td><td>?</td><td>?</td></tr></table></div></div>Usuários, threads, memória e cpu são informados pelos servidores configurados.<br></div></body></html>
```

- [ ] **Step 2: Escrever o teste (falhando) contra as duas fixtures**

Crie `tests/monitor_broker_test.prw`:

```advpl
#include "../src/monitor_lib.prw"
#include "../src/monitor_broker.prw"

User Function MonitorBrokerTest()
    Local cHtmlHttp := MemoRead("fixtures/broker_http_ok.html")
    Local cHtmlSC   := MemoRead("fixtures/broker_smartclient_quarentena.html")
    Local oParsed
    Local oServ

    ConOut("testeFix1_http_carregou=" + IIF(cHtmlHttp != "", "SIM", "NAO"))
    ConOut("testeFix2_smartclient_carregou=" + IIF(cHtmlSC != "", "SIM", "NAO"))

    // --- MonModoBroker ---
    ConOut("testeModo1_http=" + MonModoBroker(cHtmlHttp))
    ConOut("testeModo2_smartclient=" + MonModoBroker(cHtmlSC))
    ConOut("testeModo3_vazio=" + IIF(MonModoBroker("") == "", "SIM", "NAO"))
    ConOut("testeModo4_lixo=" + IIF(MonModoBroker("<html>pagina qualquer</html>") == "", "SIM", "NAO"))

    // --- MonSoNumero ---
    ConOut("testeNum1_simples=" + Str(MonSoNumero("59 sessões")))
    ConOut("testeNum2_milhar=" + Str(MonSoNumero("4.087.092")))
    ConOut("testeNum3_percentual=" + Str(MonSoNumero("37%")))
    ConOut("testeNum4_interrogacao=" + Str(MonSoNumero("?")))
    ConOut("testeNum5_vazio=" + Str(MonSoNumero("")))
    ConOut("testeNum6_espacos=" + Str(MonSoNumero("    25")))

    // --- MonParseBrokerHtml (fixture 1: broker HTTP saudavel, 5 servers) ---
    oParsed := MonParseBrokerHtml(cHtmlHttp)
    ConOut("teste1_valido=" + IIF(oParsed["VALIDO"], "SIM", "NAO"))
    ConOut("teste2_sessoes=" + Str(oParsed["SESSOESATIVAS"]))
    ConOut("teste3_conexoes=" + Str(oParsed["CONEXOESATIVAS"]))
    ConOut("teste4_versao_tem_numero=" + IIF("24.3.1.9" $ oParsed["VERSAO"], "SIM", "NAO"))
    ConOut("teste5_qtd_servers=" + Str(Len(oParsed["SERVERS"])))

    oServ := oParsed["SERVERS"][1]
    ConOut("teste6_server1_hostporta=" + oServ["HOSTPORTA"])
    ConOut("teste7_server1_sessoes=" + Str(oServ["SESSOES"]))
    ConOut("teste8_server1_conexoes=" + Str(oServ["CONEXOES"]))
    ConOut("teste9_server1_usuarios=" + Str(oServ["USUARIOS"]))
    ConOut("teste10_server1_threads=" + Str(oServ["THREADS"]))
    ConOut("teste11_server1_memoria=" + Str(oServ["MEMORIAKB"]))
    ConOut("teste12_server1_cpu=" + Str(oServ["CPU"]))
    ConOut("teste13_server1_pid=" + Str(oServ["PID"]))
    ConOut("teste14_server1_status=" + oServ["STATUS"])
    ConOut("teste15_server1_sem_quarentena=" + IIF(oServ["INICIOQUARENTENA"] == "", "SIM", "NAO"))

    // --- MonParseBrokerHtml (fixture 2: broker SmartClient, 14 servers, 9 em quarentena) ---
    oParsed := MonParseBrokerHtml(cHtmlSC)
    ConOut("teste16_valido=" + IIF(oParsed["VALIDO"], "SIM", "NAO"))
    ConOut("teste17_conexoes=" + Str(oParsed["CONEXOESATIVAS"]))
    ConOut("teste18_qtd_servers=" + Str(Len(oParsed["SERVERS"])))

    oServ := oParsed["SERVERS"][1] // server 1: OK
    ConOut("teste19_server1_status=" + oServ["STATUS"])
    ConOut("teste20_server1_conexoes=" + Str(oServ["CONEXOES"]))

    oServ := oParsed["SERVERS"][5] // server 5: em quarentena desde 12:34:30
    ConOut("teste21_server5_hostporta=" + oServ["HOSTPORTA"])
    ConOut("teste22_server5_status=" + oServ["STATUS"])
    ConOut("teste23_server5_inicio_quarentena=" + oServ["INICIOQUARENTENA"])
    ConOut("teste24_server5_usuarios_zerado=" + Str(oServ["USUARIOS"]))
    ConOut("teste25_server5_memoria_zerada=" + Str(oServ["MEMORIAKB"]))

    oServ := oParsed["SERVERS"][8] // server 8: volta a ser OK no meio da lista de quarentenas
    ConOut("teste26_server8_status=" + oServ["STATUS"])

    oServ := oParsed["SERVERS"][14] // server 14: ultimo, tambem em quarentena
    ConOut("teste27_server14_status=" + oServ["STATUS"])
    ConOut("teste28_server14_inicio_quarentena=" + oServ["INICIOQUARENTENA"])

    // conta quantos servers estao em quarentena na fixture 2 (esperado: 9)
    Local nQuarentena := 0
    Local i
    For i := 1 To Len(oParsed["SERVERS"])
        If oParsed["SERVERS"][i]["STATUS"] == "QUARENTENA"
            nQuarentena++
        EndIf
    Next
    ConOut("teste29_total_em_quarentena=" + Str(nQuarentena))

    ConOut("MONITOR_BROKER_TEST_FIM")
Return
```

- [ ] **Step 3: Rodar e confirmar que falha (funções ainda não existem)**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected: erro de compilação — `MonModoBroker`/`MonSoNumero`/`MonParseBrokerHtml` não existem ainda (nenhuma linha `testeN_` deve ser impressa).

- [ ] **Step 4: Implementar `src/monitor_broker.prw`**

```advpl
// Checagem e parsing do TOTVS Broker (endpoint /totvs_broker_query) --
// substitui a checagem HTTP generica antiga (MonCheckWebapp, removida de
// monitor_lib.prw). Sem nativa de regex disponivel no AdvPP -- extracao
// via At()/SubStr()/StrTokArr() sobre ancoras de texto fixas do HTML
// gerado pelo broker.
//
// Todas as ancoras usadas abaixo sao ASCII puro (nunca acentuadas), de
// proposito: a pagina do broker declara charset Windows-1252 e o corpo
// chega como o broker gerou -- comparar bytes acentuados arriscaria
// mismatch de encoding entre o texto literal deste fonte (salvo como
// UTF-8) e os bytes reais da resposta HTTP. Ancoras ASCII (" ativas</span>",
// "sess", "conex", "Vers", "ServerStatus/") nunca colidem com esse
// problema porque nao comparam a parte acentuada, so localizam ao redor
// dela.
//
// ponytail: so ha 2 layouts de tabela conhecidos e validados contra
// fixture real (broker "para HTTP" e "para SmartClient", ver
// tests/fixtures/) -- mapeamento de coluna por indice fixo por layout em
// MonExtrairLinhaServer, nao parsing generico de cabecalho. Se a TOTVS
// lancar um terceiro layout, adicionar um novo ramo ali contra uma
// fixture real, nao tentar generalizar sem uma.

User Function MonModoBroker(cHtml)
    If "TOTVS Broker para HTTP" $ cHtml
        Return "HTTP"
    ElseIf "TOTVS Broker para SmartClient" $ cHtml
        Return "SMARTCLIENT"
    EndIf
Return ""

User Function MonSoNumero(cTexto)
    Local cLimpo := ""
    Local cChar
    Local i

    cTexto := AllTrim(cTexto)
    For i := 1 To Len(cTexto)
        cChar := SubStr(cTexto, i, 1)
        If IsDigit(cChar)
            cLimpo += cChar
        ElseIf cChar == "." .And. cLimpo != ""
            // separador de milhar (ex: "4.087.092") -- ignora e continua
        Else
            Exit
        EndIf
    Next
Return Val(cLimpo)

User Function MonExtrairAtivas(cHtml)
    Local oRes := JsonObject():New()
    Local cAncora := " ativas</span>"
    Local nOffset := 0
    Local cResto := cHtml
    Local nPos
    Local nAbs
    Local cAntes
    Local nPosTag
    Local cTrecho

    oRes["SESSOESATIVAS"]  := 0
    oRes["CONEXOESATIVAS"] := 0

    Do While .T.
        nPos := At(cAncora, cResto)
        If nPos == 0
            Exit
        EndIf
        nAbs := nOffset + nPos

        cAntes  := SubStr(cHtml, 1, nAbs - 1)
        nPosTag := RAt(">", cAntes)
        cTrecho := SubStr(cHtml, nPosTag + 1, nAbs - nPosTag - 1)

        If "sess" $ cTrecho
            oRes["SESSOESATIVAS"] := MonSoNumero(cTrecho)
        ElseIf "conex" $ cTrecho
            oRes["CONEXOESATIVAS"] := MonSoNumero(cTrecho)
        EndIf

        nOffset := nAbs + Len(cAncora) - 1
        cResto  := SubStr(cHtml, nOffset + 1)
    EndDo
Return oRes

User Function MonExtrairVersao(cHtml)
    Local nPos := At("Vers", cHtml)
    Local nFim
    Local cTrecho

    If nPos == 0
        Return ""
    EndIf
    nFim := At("<br>", SubStr(cHtml, nPos))
    If nFim == 0
        Return ""
    EndIf
    cTrecho := SubStr(cHtml, nPos, nFim - 1)
Return AllTrim(cTrecho)

User Function MonExtrairHostPorta(cCelula)
    Local cAncora := "ServerStatus/"
    Local nPosSS := At(cAncora, cCelula)
    Local cResto
    Local nPosAspas

    If nPosSS == 0
        Return ""
    EndIf
    cResto := SubStr(cCelula, nPosSS + Len(cAncora))
    nPosAspas := At('"', cResto)
    If nPosAspas == 0
        Return AllTrim(cResto)
    EndIf
Return SubStr(cResto, 1, nPosAspas - 1)

User Function MonCelulasLinha(cLinha)
    Local aPedacos := StrTokArr(cLinha, "<td>")
    Local aCelulas := {}
    Local nFim
    Local i

    For i := 2 To Len(aPedacos)
        nFim := At("</td>", aPedacos[i])
        If nFim == 0
            AAdd(aCelulas, AllTrim(aPedacos[i]))
        Else
            AAdd(aCelulas, AllTrim(SubStr(aPedacos[i], 1, nFim - 1)))
        EndIf
    Next
Return aCelulas

User Function MonExtrairLinhaServer(cLinha, cModo)
    Local oServ := JsonObject():New()
    Local aCel  := MonCelulasLinha(cLinha)
    Local cQuarentena

    oServ["HOSTPORTA"] := MonExtrairHostPorta(aCel[1])

    If cModo == "HTTP"
        oServ["SESSOES"]   := MonSoNumero(aCel[2])
        oServ["CONEXOES"]  := MonSoNumero(aCel[3])
        cQuarentena         := AllTrim(aCel[4])
        oServ["MOTIVO"]     := IIF(AllTrim(aCel[5]) == "-", "", AllTrim(aCel[5]))
        oServ["USUARIOS"]  := MonSoNumero(aCel[6])
        oServ["THREADS"]   := MonSoNumero(aCel[7])
        oServ["MEMORIAKB"] := MonSoNumero(aCel[8])
        oServ["CPU"]       := MonSoNumero(aCel[9])
        oServ["UPTIME"]    := AllTrim(aCel[10])
        oServ["PID"]       := MonSoNumero(aCel[11])
    Else
        oServ["SESSOES"]   := 0
        oServ["CONEXOES"]  := MonSoNumero(aCel[2])
        cQuarentena         := AllTrim(aCel[3])
        oServ["MOTIVO"]     := ""
        oServ["USUARIOS"]  := MonSoNumero(aCel[4])
        oServ["THREADS"]   := MonSoNumero(aCel[5])
        oServ["MEMORIAKB"] := MonSoNumero(aCel[6])
        oServ["CPU"]       := MonSoNumero(aCel[7])
        oServ["UPTIME"]    := ""
        oServ["PID"]       := 0
    EndIf

    If cQuarentena == "-"
        oServ["STATUS"]           := "OK"
        oServ["INICIOQUARENTENA"] := ""
    Else
        oServ["STATUS"]           := "QUARENTENA"
        oServ["INICIOQUARENTENA"] := cQuarentena
    EndIf
Return oServ

User Function MonExtrairServers(cHtml, cModo)
    Local aServers := {}
    Local nPosServers := At("Servers (", cHtml)
    Local nPosTable
    Local nPosFimTable
    Local cTabela
    Local aLinhas
    Local i

    If nPosServers == 0
        Return aServers
    EndIf

    nPosTable := At("<table", SubStr(cHtml, nPosServers))
    If nPosTable == 0
        Return aServers
    EndIf
    nPosTable += nPosServers - 1

    nPosFimTable := At("</table>", SubStr(cHtml, nPosTable))
    If nPosFimTable == 0
        Return aServers
    EndIf
    cTabela := SubStr(cHtml, nPosTable, nPosFimTable + Len("</table>") - 1)

    aLinhas := StrTokArr(cTabela, "<tr>")
    For i := 1 To Len(aLinhas)
        If "ServerStatus/" $ aLinhas[i]
            AAdd(aServers, MonExtrairLinhaServer(aLinhas[i], cModo))
        EndIf
    Next
Return aServers

User Function MonParseBrokerHtml(cHtml)
    Local oRes := JsonObject():New()
    Local cModo := MonModoBroker(cHtml)
    Local oAtivas

    oRes["VALIDO"] := (cModo != "")
    If !oRes["VALIDO"]
        oRes["SESSOESATIVAS"]  := 0
        oRes["CONEXOESATIVAS"] := 0
        oRes["VERSAO"]         := ""
        oRes["SERVERS"]        := {}
        Return oRes
    EndIf

    oAtivas := MonExtrairAtivas(cHtml)
    oRes["SESSOESATIVAS"]  := oAtivas["SESSOESATIVAS"]
    oRes["CONEXOESATIVAS"] := oAtivas["CONEXOESATIVAS"]
    oRes["VERSAO"]          := MonExtrairVersao(cHtml)
    oRes["SERVERS"]         := MonExtrairServers(cHtml, cModo)
Return oRes
```

- [ ] **Step 5: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected (entre outras): `teste1_valido=SIM`, `teste2_sessoes=59`, `teste3_conexoes=175`, `teste5_qtd_servers=5`, `teste14_server1_status=OK`, `teste16_valido=SIM`, `teste18_qtd_servers=14`, `teste19_server1_status=OK`, `teste22_server5_status=QUARENTENA`, `teste23_server5_inicio_quarentena=12:34:30`, `teste24_server5_usuarios_zerado=0`, `teste26_server8_status=OK`, `teste27_server14_status=QUARENTENA`, `teste29_total_em_quarentena=9`, terminando em `MONITOR_BROKER_TEST_FIM` sem nenhuma linha de erro do compilador acima.

- [ ] **Step 6: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_broker.prw tests/monitor_broker_test.prw tests/fixtures/
git commit -m "feat: parser do HTML do TOTVS Broker (sessoes, conexoes, tabela de servers, quarentena)"
```

---

### Task 2: `MonCheckBroker` + `MonProcessarUnidade` (substitui `MonCheckWebapp`)

**Files:**
- Modify: `src/monitor_lib.prw` (remove `MonCheckWebapp` e `MonProcessarUnidade` — mudam de arquivo)
- Modify: `src/monitor_broker.prw` (adiciona `MonCheckBroker`/`MonProcessarUnidade`)
- Modify: `tests/monitor_broker_test.prw`
- Modify: `tests/monitor_lib_test.prw` (remove os testes antigos de `MonCheckWebapp`/`.ini`/`MonProcessarUnidade`)

**Interfaces:**
- Consumes: `MonParseBrokerHtml` (Task 1), `MonProcessarResultado(cChave, cRotulo, oRes, oState, cLogPath, cToken, cChatId)` (já existe em `monitor_lib.prw`, usa `oRes["HOST"]`/`["PORT"]`/`["UP"]`/`["LATENCIAMS"]`).
- Produces: `MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs) -> oRes{UNIDADE,HOST,PORT,LATENCIAMS,UP,SESSOESATIVAS,CONEXOESATIVAS,VERSAO,SERVERS}`, `MonProcessarUnidade(cUnidade, cHost, nPorta, nTimeoutMs, oState, cLogPath, cToken, cChatId) -> oRes` (contrato de assinatura muda: antes recebia `cIniPath`, agora recebe `cHost` direto; **e agora devolve `oRes`**, antes devolvia `Nil` — usado pelo Task 6 pra montar o snapshot do dashboard). Usado pelo Task 3 (alerta granular) e Task 6 (`MonitorMain`).

- [ ] **Step 1: Remover de `src/monitor_lib.prw` as funções que mudam de lugar**

Abra `src/monitor_lib.prw` e:
1. Remova a função inteira `MonCheckWebapp` (linhas 3-26 do arquivo atual).
2. Remova a função inteira `MonProcessarUnidade` (as últimas 17 linhas do arquivo atual, começando em `User Function MonProcessarUnidade(...)`).
3. Em `MonProcessarDbaccess`, troque a última linha `Return Nil` por `Return oRes`.
4. Em `MonProcessarLicenseServer`, troque a última linha `Return Nil` por `Return oRes`.

O arquivo `src/monitor_lib.prw` completo deve ficar assim:

```advpl
// Monitor library - checagem HTTP/TCP e controle de estado

User Function MonLoadState(cStatePath)
    Local oState := JsonObject():New()
    Local cTxt   := MemoRead(cStatePath)

    If cTxt != ""
        If !oState:FromJson(cTxt)
            ConOut("AVISO: state.json corrompido, ignorando e comecando do zero")
            oState := JsonObject():New()
        EndIf
    EndIf
Return oState

User Function MonGetStatusAnterior(oState, cUnidade)
    If !oState:HasProperty(cUnidade)
        Return "DESCONHECIDO"
    EndIf
Return oState[cUnidade]

User Function MonSetStatus(oState, cUnidade, cStatus, nLatenciaMs)
    oState[cUnidade] := cStatus
    oState[cUnidade + "_LATENCIA"] := nLatenciaMs
Return Nil

User Function MonGetLatenciaAnterior(oState, cChave)
    If !oState:HasProperty(cChave + "_LATENCIA")
        Return -1
    EndIf
Return oState[cChave + "_LATENCIA"]

User Function MonSaveState(cStatePath, oState)
Return MemoWrite(cStatePath, oState:ToJson())

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
    If ValType(oConfig["unidades"]) != "A"
        Return {}
    EndIf
Return oConfig["unidades"]

User Function MonMontarMensagem(cUnidade, cHost, nPort, cStatusNovo)
    Local cTexto

    If cStatusNovo == "DOWN"
        cTexto := "[ALERTA] " + cUnidade + " (" + cHost + ":" + AllTrim(Str(nPort)) + ") caiu"
    Else
        cTexto := "[OK] " + cUnidade + " (" + cHost + ":" + AllTrim(Str(nPort)) + ") voltou"
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

User Function MonProcessarResultado(cChave, cRotulo, oRes, oState, cLogPath, cToken, cChatId)
    Local cStatusAnterior
    Local cStatusNovo
    Local nLatenciaMs
    Local cMsg

    cStatusAnterior := MonGetStatusAnterior(oState, cChave)
    cStatusNovo := IIF(oRes["UP"], "UP", "DOWN")
    nLatenciaMs := Round(oRes["LATENCIAMS"], 0)

    MonLog(cLogPath, cChave + " " + oRes["HOST"] + ":" + AllTrim(Str(oRes["PORT"])) + " status=" + cStatusNovo + " latenciaMs=" + AllTrim(Str(nLatenciaMs)))

    If cStatusNovo != cStatusAnterior
        If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo == "DOWN"
            cMsg := MonMontarMensagem(cRotulo, oRes["HOST"], oRes["PORT"], cStatusNovo)
            If !MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " falha ao notificar telegram")
            EndIf
        EndIf
    EndIf

    MonSetStatus(oState, cChave, cStatusNovo, nLatenciaMs)
Return Nil

User Function MonProcessarDbaccess(cUnidade, cHostAppserver, nPortaDbaccess, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local cChave := cUnidade + "_DBACCESS"
    Local oRes
    Local e

    Try
        oRes := MonPingServico(cChave, cHostAppserver, nPortaDbaccess, nTimeoutMs)
        MonProcessarResultado(cChave, cUnidade + " dbaccess", oRes, oState, cLogPath, cToken, cChatId)
    Catch e
        MonLog(cLogPath, cChave + " erro_interno=" + e:description)
    EndTry
Return oRes

User Function MonProcessarLicenseServer(cHost, nPort, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local cChave := "LICENSE_SERVER"
    Local oRes
    Local e

    Try
        oRes := MonPingServico(cChave, cHost, nPort, nTimeoutMs)
        MonProcessarResultado(cChave, "License Server", oRes, oState, cLogPath, cToken, cChatId)
    Catch e
        MonLog(cLogPath, cChave + " erro_interno=" + e:description)
    EndTry
Return oRes
```

- [ ] **Step 2: Escrever o teste (falhando) de `MonCheckBroker`/`MonProcessarUnidade`**

Adicione ao final de `tests/monitor_broker_test.prw`, antes do `ConOut("MONITOR_BROKER_TEST_FIM")`:

```advpl
    // --- MonCheckBroker ---
    // porta 19191: servidor HTTP de teste ja usado pelo resto da suite
    // (README ja documenta como subir), responde "ok" puro -- serve pra
    // provar que "respondeu HTTP" != "e o broker de verdade".
    Local oCheck

    oCheck := MonCheckBroker("TESTEBROKER", "127.0.0.1", 19191, 2000)
    ConOut("testeCheck1_host=" + oCheck["HOST"])
    ConOut("testeCheck2_port=" + Str(oCheck["PORT"]))
    ConOut("testeCheck3_up_falso_no_broker=" + IIF(oCheck["UP"], "NAO", "SIM"))
    ConOut("testeCheck4_latencia_nao_negativa=" + IIF(oCheck["LATENCIAMS"] >= 0, "SIM", "NAO"))

    // porta 19194: ninguem escuta -- down de verdade
    oCheck := MonCheckBroker("TESTEBROKER", "127.0.0.1", 19194, 500)
    ConOut("testeCheck5_down_sem_listener=" + IIF(oCheck["UP"], "NAO", "SIM"))
    ConOut("testeCheck6_sessoes_zeradas=" + Str(oCheck["SESSOESATIVAS"]))
    ConOut("testeCheck7_servers_vazio=" + Str(Len(oCheck["SERVERS"])))

    // host vazio nao pode estourar excecao -- so fica down
    oCheck := MonCheckBroker("TESTEBROKER", "", 8090, 500)
    ConOut("testeCheck8_host_vazio_nao_quebra=" + IIF(oCheck["UP"], "NAO", "SIM"))

    // --- MonProcessarUnidade ---
    Local oState2 := JsonObject():New()
    Local cLog2   := "test_monitor_unidade.log"
    Local cTokenFake := "TOKEN_INVALIDO_DE_PROPOSITO"
    Local cChatFake  := "0"
    Local oResUnid

    FErase(cLog2)
    oResUnid := MonProcessarUnidade("TCPX", "127.0.0.1", 19194, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("testePU1_status_apos_1a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))
    ConOut("testePU2_retorna_oRes=" + IIF(oResUnid["UNIDADE"] == "TCPX", "SIM", "NAO"))

    Local cLogTxt := MemoRead(cLog2)
    MonProcessarUnidade("TCPX", "127.0.0.1", 19194, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("testePU3_status_apos_2a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))
    ConOut("testePU4_log_cresceu=" + IIF(Len(MemoRead(cLog2)) > Len(cLogTxt), "SIM", "NAO"))
    ConOut("testePU5_latencia_registrada=" + IIF(MonGetLatenciaAnterior(oState2, "TCPX") >= 0, "SIM", "NAO"))

    FErase(cLog2)
```

- [ ] **Step 3: Rodar e confirmar que falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected: erro de compilação — `MonCheckBroker`/`MonProcessarUnidade` ainda não existem em `monitor_broker.prw`.

- [ ] **Step 4: Adicionar `MonCheckBroker`/`MonProcessarUnidade` a `src/monitor_broker.prw`**

Adicione ao final de `src/monitor_broker.prw`:

```advpl
User Function MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs)
    Local oRes := JsonObject():New()
    Local nT1
    Local nStatus
    Local cBody
    Local oParsed
    Local lHttpOk

    oRes["UNIDADE"] := cUnidade
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPorta

    FWHttpTimeout(Max(1, Int((nTimeoutMs + 999) / 1000)))
    nT1 := TimeCounter()
    nStatus := FWHttpGet("http://" + cHost + ":" + AllTrim(Str(nPorta)) + "/totvs_broker_query")
    oRes["LATENCIAMS"] := TimeCounter() - nT1
    cBody := FWHttpBody()

    lHttpOk := (nStatus > 0 .And. nStatus < 500)
    oParsed := MonParseBrokerHtml(cBody)

    oRes["UP"]              := (lHttpOk .And. oParsed["VALIDO"])
    oRes["SESSOESATIVAS"]   := oParsed["SESSOESATIVAS"]
    oRes["CONEXOESATIVAS"]  := oParsed["CONEXOESATIVAS"]
    oRes["VERSAO"]           := oParsed["VERSAO"]
    oRes["SERVERS"]          := oParsed["SERVERS"]
Return oRes

User Function MonProcessarUnidade(cUnidade, cHost, nPorta, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local oRes
    Local e

    Try
        oRes := MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs)
        MonProcessarResultado(cUnidade, cUnidade, oRes, oState, cLogPath, cToken, cChatId)
    Catch e
        MonLog(cLogPath, cUnidade + " erro_interno=" + e:description)
    EndTry
Return oRes
```

(`MonProcessarServersBroker` — o alerta granular por server — entra no Task 3, chamado a partir daqui.)

- [ ] **Step 5: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected: `testeCheck3_up_falso_no_broker=SIM`, `testeCheck5_down_sem_listener=SIM`, `testeCheck7_servers_vazio=0`, `testeCheck8_host_vazio_nao_quebra=SIM`, `testePU2_retorna_oRes=SIM`, `testePU3_status_apos_2a_passagem=DOWN`, sem erro de compilação.

- [ ] **Step 6: Remover os testes antigos de `tests/monitor_lib_test.prw`**

Abra `tests/monitor_lib_test.prw` e remova:
1. O bloco de `MonCheckWebapp` no início (as declarações de `cIniPath`, os `MemoWrite`/`MonCheckWebapp`/`FErase(cIniPath)` de `teste1` a `teste7`).
2. O bloco inteiro de `MonProcessarUnidade` perto do final (`testePU1` a `testePU11`, incluindo as três seções com `cIni2`/`cIni3`/`cIni4`).

O restante do arquivo (estado, log, config, mensagens, Telegram, `MonPingServico`, `MonProcessarDbaccess`/`MonProcessarLicenseServer`, latência) fica igual — essas partes são reescritas no Task 6 (schema novo de `unidades`), não aqui.

- [ ] **Step 7: Rodar a suite antiga e confirmar que ainda compila**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
```

Expected: roda até `MONITOR_LIB_TEST_FIM` sem erro (os testes de `MonProcessarDbaccess`/`MonProcessarLicenseServer` continuam passando com o `Return oRes` novo, já que nenhum teste checava o valor de retorno até agora).

- [ ] **Step 8: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_lib.prw src/monitor_broker.prw tests/monitor_broker_test.prw tests/monitor_lib_test.prw
git commit -m "feat: MonCheckBroker/MonProcessarUnidade -- checagem via totvs_broker_query, sem .ini"
```

---

### Task 3: Alerta granular por server em quarentena

**Files:**
- Modify: `src/monitor_broker.prw` (adiciona `MonMontarMensagemServer`, `MonProcessarServidorBroker`, `MonProcessarServersBroker`; integra em `MonProcessarUnidade`)
- Modify: `tests/monitor_broker_test.prw`

**Interfaces:**
- Consumes: `MonGetStatusAnterior`/`MonNotificarTelegram`/`MonLog` (`monitor_lib.prw`).
- Produces: `MonMontarMensagemServer(cUnidade, cHostPorta, cStatusNovo, cInicioQuarentena, cMotivo) -> cTexto`, `MonProcessarServidorBroker(cUnidade, oServ, oState, cLogPath, cToken, cChatId)`, `MonProcessarServersBroker(cUnidade, aServers, oState, cLogPath, cToken, cChatId)` — usado pelo Task 6 indiretamente (via `MonProcessarUnidade`, que passa a chamar isso internamente).

- [ ] **Step 1: Escrever o teste (falhando)**

Adicione ao final de `tests/monitor_broker_test.prw`, antes do `ConOut("MONITOR_BROKER_TEST_FIM")`:

```advpl
    // --- MonMontarMensagemServer ---
    Local cMsgQ := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "QUARENTENA", "12:34:30", "")
    Local cMsgO := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "OK", "", "")
    Local cMsgM := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "QUARENTENA", "12:34:30", "falha de comunicacao")

    ConOut("testeMsg1_quarentena_tem_unidade=" + IIF("ORTOSP" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg2_quarentena_tem_hostporta=" + IIF("10.0.100.62:1236" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg3_quarentena_tem_horario=" + IIF("12:34:30" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg4_ok_diz_saiu=" + IIF("saiu da quarentena" $ cMsgO, "SIM", "NAO"))
    ConOut("testeMsg5_motivo_aparece_quando_preenchido=" + IIF("falha de comunicacao" $ cMsgM, "SIM", "NAO"))
    ConOut("testeMsg6_motivo_nao_aparece_quando_vazio=" + IIF("motivo:" $ cMsgQ, "NAO", "SIM"))

    // --- MonProcessarServidorBroker: transicoes de estado ---
    Local oState3 := JsonObject():New()
    Local cLog3   := "test_monitor_server_broker.log"
    Local oServOk := JsonObject():New()
    Local oServQ  := JsonObject():New()

    oServOk["HOSTPORTA"]        := "10.0.100.62:1236"
    oServOk["STATUS"]           := "OK"
    oServOk["INICIOQUARENTENA"] := ""
    oServOk["MOTIVO"]           := ""

    oServQ["HOSTPORTA"]        := "10.0.100.62:1236"
    oServQ["STATUS"]           := "QUARENTENA"
    oServQ["INICIOQUARENTENA"] := "12:34:30"
    oServQ["MOTIVO"]           := ""

    FErase(cLog3)

    // 1a passagem OK (DESCONHECIDO -> OK) nao deve notificar
    MonProcessarServidorBroker("ORTOSP", oServOk, oState3, cLog3, "TOKEN_FAKE", "0")
    ConOut("testeServ1_status_apos_ok_inicial=" + MonGetStatusAnterior(oState3, "ORTOSP_SERVER_10.0.100.62:1236"))
    ConOut("testeServ2_nao_notificou_ok_inicial=" + IIF("falha ao notificar telegram" $ MemoRead(cLog3), "NAO", "SIM"))

    // OK -> QUARENTENA deve notificar (log de falha aparece, pois token e fake)
    MonProcessarServidorBroker("ORTOSP", oServQ, oState3, cLog3, "TOKEN_FAKE", "0")
    ConOut("testeServ3_status_apos_quarentena=" + MonGetStatusAnterior(oState3, "ORTOSP_SERVER_10.0.100.62:1236"))
    ConOut("testeServ4_notificou_quarentena=" + IIF("falha ao notificar telegram" $ MemoRead(cLog3), "SIM", "NAO"))

    // QUARENTENA -> QUARENTENA (sem mudanca) nao deve renotificar
    Local cLogAntes := MemoRead(cLog3)
    MonProcessarServidorBroker("ORTOSP", oServQ, oState3, cLog3, "TOKEN_FAKE", "0")
    ConOut("testeServ5_sem_renotificar_quarentena_repetida=" + IIF(MemoRead(cLog3) == cLogAntes, "SIM", "NAO"))

    // QUARENTENA -> OK deve notificar "saiu"
    Local cLogAntes2 := MemoRead(cLog3)
    MonProcessarServidorBroker("ORTOSP", oServOk, oState3, cLog3, "TOKEN_FAKE", "0")
    ConOut("testeServ6_status_apos_saida=" + MonGetStatusAnterior(oState3, "ORTOSP_SERVER_10.0.100.62:1236"))
    ConOut("testeServ7_notificou_saida=" + IIF(MemoRead(cLog3) != cLogAntes2, "SIM", "NAO"))

    FErase(cLog3)

    // --- MonProcessarServersBroker: unidade independente por hostporta ---
    Local oState4 := JsonObject():New()
    Local cLog4   := "test_monitor_servers_broker.log"
    Local oServA  := JsonObject():New()
    Local oServB  := JsonObject():New()
    Local aServs  := {}

    oServA["HOSTPORTA"]        := "10.0.100.62:1236"
    oServA["STATUS"]           := "OK"
    oServA["INICIOQUARENTENA"] := ""
    oServA["MOTIVO"]           := ""

    oServB["HOSTPORTA"]        := "10.0.100.62:1237"
    oServB["STATUS"]           := "QUARENTENA"
    oServB["INICIOQUARENTENA"] := "09:00:00"
    oServB["MOTIVO"]           := ""

    AAdd(aServs, oServA)
    AAdd(aServs, oServB)

    FErase(cLog4)
    MonProcessarServersBroker("ORTOSP", aServs, oState4, cLog4, "TOKEN_FAKE", "0")
    ConOut("testeServs1_a_ok=" + MonGetStatusAnterior(oState4, "ORTOSP_SERVER_10.0.100.62:1236"))
    ConOut("testeServs2_b_quarentena=" + MonGetStatusAnterior(oState4, "ORTOSP_SERVER_10.0.100.62:1237"))
    FErase(cLog4)
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected: erro de compilação — `MonMontarMensagemServer`/`MonProcessarServidorBroker`/`MonProcessarServersBroker` ainda não existem.

- [ ] **Step 3: Implementar em `src/monitor_broker.prw`**

Adicione ao final de `src/monitor_broker.prw`:

```advpl
User Function MonMontarMensagemServer(cUnidade, cHostPorta, cStatusNovo, cInicioQuarentena, cMotivo)
    Local cTexto

    If cStatusNovo == "QUARENTENA"
        cTexto := "[ALERTA] " + cUnidade + " server " + cHostPorta + " entrou em quarentena as " + cInicioQuarentena
        If cMotivo != ""
            cTexto += ", motivo: " + cMotivo
        EndIf
    Else
        cTexto := "[OK] " + cUnidade + " server " + cHostPorta + " saiu da quarentena"
    EndIf
Return cTexto

User Function MonProcessarServidorBroker(cUnidade, oServ, oState, cLogPath, cToken, cChatId)
    Local cChave := cUnidade + "_SERVER_" + oServ["HOSTPORTA"]
    Local cStatusAnterior := MonGetStatusAnterior(oState, cChave)
    Local cStatusNovo := oServ["STATUS"]
    Local cMsg

    If cStatusNovo != cStatusAnterior
        If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo == "QUARENTENA"
            cMsg := MonMontarMensagemServer(cUnidade, oServ["HOSTPORTA"], cStatusNovo, oServ["INICIOQUARENTENA"], oServ["MOTIVO"])
            If !MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " falha ao notificar telegram")
            EndIf
        EndIf
    EndIf

    oState[cChave] := cStatusNovo
Return Nil

User Function MonProcessarServersBroker(cUnidade, aServers, oState, cLogPath, cToken, cChatId)
    Local i

    For i := 1 To Len(aServers)
        MonProcessarServidorBroker(cUnidade, aServers[i], oState, cLogPath, cToken, cChatId)
    Next
Return Nil
```

Agora integre em `MonProcessarUnidade` (já em `src/monitor_broker.prw`, do Task 2) — adicione a chamada logo após `MonProcessarResultado`:

```advpl
User Function MonProcessarUnidade(cUnidade, cHost, nPorta, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local oRes
    Local e

    Try
        oRes := MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs)
        MonProcessarResultado(cUnidade, cUnidade, oRes, oState, cLogPath, cToken, cChatId)
        MonProcessarServersBroker(cUnidade, oRes["SERVERS"], oState, cLogPath, cToken, cChatId)
    Catch e
        MonLog(cLogPath, cUnidade + " erro_interno=" + e:description)
    EndTry
Return oRes
```

(Substitua o corpo da função que o Task 2 criou por este — só a linha `MonProcessarServersBroker(...)` é nova.)

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
```

Expected: `testeServ2_nao_notificou_ok_inicial=SIM`, `testeServ4_notificou_quarentena=SIM`, `testeServ5_sem_renotificar_quarentena_repetida=SIM`, `testeServ7_notificou_saida=SIM`, `testeServs1_a_ok=OK`, `testeServs2_b_quarentena=QUARENTENA`, terminando em `MONITOR_BROKER_TEST_FIM` sem erro.

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_broker.prw tests/monitor_broker_test.prw
git commit -m "feat: alerta granular por server em quarentena no broker"
```

---

### Task 4: Bump `ADVPP_VERSION`

**Files:**
- Modify: `ADVPP_VERSION`

**Interfaces:**
- Produces: nenhuma mudança de interface — só habilita, na CI, o recurso de resposta HTTP crua do `WSRestServer` que o Task 5 usa. Localmente, `~/Projetos/AdvPP/advplc` já é um build atual (mais novo que `v4.2.1`) e já suporta o recurso independente deste bump — o bump é só pra CI.

- [ ] **Step 1: Confirmar que o build local suporta `__RAW_HTTP__`**

```bash
grep -c "__RAW_HTTP__" ~/Projetos/AdvPP/pkg/vm/rest_native.go
```

Expected: `2` (ou mais) — confirma que o binário local (`~/Projetos/AdvPP/advplc`) já foi compilado de um checkout que tem o recurso, então os testes do Task 5 rodam sem precisar recompilar nada agora.

- [ ] **Step 2: Bumpar `ADVPP_VERSION`**

Substitua o conteúdo de `ADVPP_VERSION` (sem quebra de linha no final, igual ao arquivo atual) por:

```
4.2.1
```

- [ ] **Step 3: Commit**

```bash
cd ~/Projetos/monitor
git add ADVPP_VERSION
git commit -m "chore: bump ADVPP_VERSION para 4.2.1 (necessario pro WSRestServer devolver HTML cru)"
```

---

### Task 5: Dashboard — geração, persistência, rota HTTP e servidor

**Files:**
- Create: `src/monitor_dashboard.prw`
- Create: `tests/monitor_dashboard_test.prw`

**Interfaces:**
- Consumes: nenhuma dependência de `monitor_lib.prw`/`monitor_broker.prw` (arquivo autossuficiente, igual `monitor_tui_lib.prw` já é).
- Produces: `MonSalvarDashboard(cPath, aUnidadesRes, aDbaccessRes, oLicenseRes) -> lOk`, `MonGerarDashboardHtml(oDash) -> cHtml`, `MonRotaDashboard(oParams) -> {"__RAW_HTTP__", cContentType, cHtml, nStatus}`, `MonServirDashboard(nPorta)` (bloqueia — só deve rodar dentro de um `StartJob` assíncrono, nunca chamado direto no loop principal). Usado pelo Task 6 (`MonitorMain`).

- [ ] **Step 1: Escrever o teste (falhando)**

Crie `tests/monitor_dashboard_test.prw`:

```advpl
#include "../src/monitor_dashboard.prw"

User Function MonitorDashboardTest()
    Local cPath := "test_dashboard.json"
    Local aUnidades := {}
    Local oU1 := JsonObject():New()
    Local oU2 := JsonObject():New()
    Local oServ := JsonObject():New()
    Local aServs := {}

    oServ["HOSTPORTA"] := "10.0.100.62:1236"
    oServ["STATUS"]    := "QUARENTENA"
    oServ["USUARIOS"]  := 0
    oServ["MEMORIAKB"] := 0
    oServ["CPU"]       := 0
    AAdd(aServs, oServ)

    oU1["UNIDADE"]         := "ORTOSP"
    oU1["HOST"]            := "10.0.100.62"
    oU1["PORT"]            := 8090
    oU1["UP"]              := .T.
    oU1["LATENCIAMS"]      := 42
    oU1["SESSOESATIVAS"]   := 59
    oU1["CONEXOESATIVAS"]  := 175
    oU1["SERVERS"]         := aServs

    oU2["UNIDADE"]         := "ORTORJ"
    oU2["HOST"]            := "10.0.100.53"
    oU2["PORT"]            := 8090
    oU2["UP"]              := .F.
    oU2["LATENCIAMS"]      := 0
    oU2["SESSOESATIVAS"]   := 0
    oU2["CONEXOESATIVAS"]  := 0
    oU2["SERVERS"]         := {}

    AAdd(aUnidades, oU1)
    AAdd(aUnidades, oU2)

    // --- MonSalvarDashboard ---
    FErase(cPath)
    ConOut("teste1_salvou=" + IIF(MonSalvarDashboard(cPath, aUnidades, {}, Nil), "SIM", "NAO"))

    Local oDash := JsonObject():New()
    oDash:FromJson(MemoRead(cPath))
    ConOut("teste2_tem_atualizadoem=" + IIF(oDash["ATUALIZADOEM"] != "", "SIM", "NAO"))
    ConOut("teste3_qtd_unidades=" + Str(Len(oDash["UNIDADES"])))
    ConOut("teste4_unidade1_nome=" + oDash["UNIDADES"][1]["UNIDADE"])

    // --- MonGerarDashboardHtml ---
    Local cHtml := MonGerarDashboardHtml(oDash)
    ConOut("teste5_html_tem_ortosp=" + IIF("ORTOSP" $ cHtml, "SIM", "NAO"))
    ConOut("teste6_html_tem_ortorj=" + IIF("ORTORJ" $ cHtml, "SIM", "NAO"))
    ConOut("teste7_html_tem_up=" + IIF("UP" $ cHtml, "SIM", "NAO"))
    ConOut("teste8_html_tem_down=" + IIF("DOWN" $ cHtml, "SIM", "NAO"))
    ConOut("teste9_html_tem_server_quarentena=" + IIF("QUARENTENA" $ cHtml, "SIM", "NAO"))
    ConOut("teste10_html_sem_dbaccess_quando_vazio=" + IIF("dbaccess" $ cHtml, "NAO", "SIM"))
    ConOut("teste11_html_sem_license_quando_ausente=" + IIF("License Server" $ cHtml, "NAO", "SIM"))

    // --- MonRotaDashboard: dashboard.json ausente ---
    FErase("dashboard_rota_ausente.json")
    Local aResp := MonRotaDashboard(Nil, "dashboard_rota_ausente.json")
    ConOut("teste12_sentinela=" + aResp[1])
    ConOut("teste13_content_type=" + aResp[2])
    ConOut("teste14_avisa_sem_dados=" + IIF("aguarde" $ aResp[3], "SIM", "NAO"))

    // --- MonRotaDashboard: dashboard.json presente ---
    Local aResp2 := MonRotaDashboard(Nil, cPath)
    ConOut("teste15_rota_tem_ortosp=" + IIF("ORTOSP" $ aResp2[3], "SIM", "NAO"))

    FErase(cPath)

    ConOut("MONITOR_DASHBOARD_TEST_FIM")
Return
```

- [ ] **Step 2: Rodar e confirmar que falha**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_dashboard_test.prw
```

Expected: erro de compilação — nenhuma das funções existe ainda.

- [ ] **Step 3: Implementar `src/monitor_dashboard.prw`**

```advpl
// Dashboard web consolidado -- servido pelo proprio MonitorService via
// WSRestServer (nativa disponivel a partir do ADVPP v4.2.0, que devolve
// HTML cru via Return {"__RAW_HTTP__", cContentType, cBody}). A rota HTTP
// roda numa VM isolada (sem acesso as variaveis do loop principal), entao
// le sempre o snapshot mais recente gravado em disco por
// MonSalvarDashboard -- mesmo padrao ja usado por state.json.

User Function MonSalvarDashboard(cPath, aUnidadesRes, aDbaccessRes, oLicenseRes)
    Local oDash := JsonObject():New()

    oDash["ATUALIZADOEM"]  := DTOC(Date()) + " " + Time()
    oDash["UNIDADES"]      := aUnidadesRes
    oDash["DBACCESS"]      := aDbaccessRes
    oDash["LICENSESERVER"] := oLicenseRes
Return MemoWrite(cPath, oDash:ToJson())

User Function MonLinhaChecagem(cNome, cHost, nPort, lUp, nLatenciaMs)
    Local cHtml := "<tr class='" + IIF(lUp, "up", "down") + "'>"

    cHtml += "<td>" + cNome + "</td>"
    cHtml += "<td>" + cHost + ":" + AllTrim(Str(nPort)) + "</td>"
    cHtml += "<td>" + IIF(lUp, "UP", "DOWN") + "</td>"
    cHtml += "<td>" + AllTrim(Str(Round(nLatenciaMs, 0))) + "</td>"
    cHtml += "</tr>"
Return cHtml

User Function MonGerarDashboardHtml(oDash)
    Local cHtml := "<!doctype html><html><head><meta charset='utf-8'>" + ;
        "<title>Monitor Protheus - Ortobom</title>" + ;
        "<style>body{font-family:sans-serif;margin:20px} " + ;
        "table{border-collapse:collapse;margin-bottom:24px} " + ;
        "td,th{border:1px solid #ccc;padding:4px 10px;text-align:left} " + ;
        "tr.up{background:#e6ffed} tr.down{background:#ffe6e6} " + ;
        "h1{font-size:1.4em} h2{font-size:1.1em;margin-top:28px}</style>" + ;
        "</head><body>"
    Local aUnidades := oDash["UNIDADES"]
    Local aDbaccess := oDash["DBACCESS"]
    Local oLicense  := oDash["LICENSESERVER"]
    Local oU
    Local oS
    Local i
    Local j

    cHtml += "<h1>Monitor Protheus - Ortobom</h1>"
    cHtml += "<p>Atualizado em " + oDash["ATUALIZADOEM"] + "</p>"

    cHtml += "<table><tr><th>Unidade</th><th>Host:Porta</th><th>Status</th>" + ;
        "<th>Latencia(ms)</th><th>Sessoes ativas</th><th>Conexoes ativas</th></tr>"
    For i := 1 To Len(aUnidades)
        oU := aUnidades[i]
        cHtml += "<tr class='" + IIF(oU["UP"], "up", "down") + "'>"
        cHtml += "<td>" + oU["UNIDADE"] + "</td>"
        cHtml += "<td>" + oU["HOST"] + ":" + AllTrim(Str(oU["PORT"])) + "</td>"
        cHtml += "<td>" + IIF(oU["UP"], "UP", "DOWN") + "</td>"
        cHtml += "<td>" + AllTrim(Str(Round(oU["LATENCIAMS"], 0))) + "</td>"
        cHtml += "<td>" + AllTrim(Str(oU["SESSOESATIVAS"])) + "</td>"
        cHtml += "<td>" + AllTrim(Str(oU["CONEXOESATIVAS"])) + "</td>"
        cHtml += "</tr>"
    Next
    cHtml += "</table>"

    For i := 1 To Len(aUnidades)
        oU := aUnidades[i]
        If Len(oU["SERVERS"]) > 0
            cHtml += "<h2>" + oU["UNIDADE"] + " - servers do broker</h2>"
            cHtml += "<table><tr><th>Host:Porta</th><th>Status</th><th>Usuarios</th>" + ;
                "<th>Memoria(Kb)</th><th>Cpu(%)</th></tr>"
            For j := 1 To Len(oU["SERVERS"])
                oS := oU["SERVERS"][j]
                cHtml += "<tr class='" + IIF(oS["STATUS"] == "OK", "up", "down") + "'>"
                cHtml += "<td>" + oS["HOSTPORTA"] + "</td>"
                cHtml += "<td>" + oS["STATUS"] + "</td>"
                cHtml += "<td>" + AllTrim(Str(oS["USUARIOS"])) + "</td>"
                cHtml += "<td>" + AllTrim(Str(oS["MEMORIAKB"])) + "</td>"
                cHtml += "<td>" + AllTrim(Str(oS["CPU"])) + "</td>"
                cHtml += "</tr>"
            Next
            cHtml += "</table>"
        EndIf
    Next

    If ValType(aDbaccess) == "A" .And. Len(aDbaccess) > 0
        cHtml += "<h2>dbaccess</h2><table><tr><th>Unidade</th><th>Host:Porta</th>" + ;
            "<th>Status</th><th>Latencia(ms)</th></tr>"
        For i := 1 To Len(aDbaccess)
            oU := aDbaccess[i]
            cHtml += MonLinhaChecagem(oU["UNIDADE"], oU["HOST"], oU["PORT"], oU["UP"], oU["LATENCIAMS"])
        Next
        cHtml += "</table>"
    EndIf

    If ValType(oLicense) == "O"
        cHtml += "<h2>License Server</h2><table><tr><th>Host:Porta</th><th>Status</th>" + ;
            "<th>Latencia(ms)</th></tr>"
        cHtml += MonLinhaChecagem("License Server", oLicense["HOST"], oLicense["PORT"], oLicense["UP"], oLicense["LATENCIAMS"])
        cHtml += "</table>"
    EndIf

    cHtml += "</body></html>"
Return cHtml

User Function MonRotaDashboard(oParams, cPathDashboard)
    Local cPath := IIF(cPathDashboard == Nil, "dashboard.json", cPathDashboard)
    Local cJson := MemoRead(cPath)
    Local oDash

    If cJson == ""
        Return {"__RAW_HTTP__", "text/html", ;
            "<!doctype html><html><body>Dashboard ainda sem dados -- aguarde o primeiro ciclo de checagem.</body></html>", 200}
    EndIf

    oDash := JsonObject():New()
    If !oDash:FromJson(cJson)
        Return {"__RAW_HTTP__", "text/html", ;
            "<!doctype html><html><body>dashboard.json corrompido.</body></html>", 200}
    EndIf
Return {"__RAW_HTTP__", "text/html", MonGerarDashboardHtml(oDash), 200}

User Function MonServirDashboard(nPorta)
    Local oServer := WSRestServer():New("MonitorDashboard", "1.0.0")

    oServer:AddRoute("GET", "/", "MonRotaDashboard")
    oServer:Serve(nPorta)
Return Nil
```

**Nota:** `MonRotaDashboard` tem um segundo parâmetro opcional (`cPathDashboard`) só pra facilitar o teste (apontar pra um arquivo de teste em vez do `dashboard.json` real) — quando o `WSRestServer` chama essa função como rota HTTP, ele sempre passa só um argumento (o objeto de parâmetros da requisição), então em produção `cPathDashboard` vem `Nil` e cai no default `"dashboard.json"`, igual ao restante do monitor.

- [ ] **Step 4: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_dashboard_test.prw
```

Expected: `teste1_salvou=SIM`, `teste3_qtd_unidades=2`, `teste5_html_tem_ortosp=SIM`, `teste8_html_tem_down=SIM`, `teste9_html_tem_server_quarentena=SIM`, `teste10_html_sem_dbaccess_quando_vazio=SIM`, `teste11_html_sem_license_quando_ausente=SIM`, `teste12_sentinela=__RAW_HTTP__`, `teste14_avisa_sem_dados=SIM`, `teste15_rota_tem_ortosp=SIM`, terminando em `MONITOR_DASHBOARD_TEST_FIM` sem erro.

- [ ] **Step 5: Verificação sintática de `monitor.prw` com o novo include (adiantada)**

Ainda não foi modificado `monitor.prw` (isso é o Task 6), mas confirme que `monitor_dashboard.prw` sozinho compila limpo fora do contexto de teste também:

```bash
cd ~/Projetos/monitor
~/Projetos/AdvPP/advplc check src/monitor_dashboard.prw
```

Expected: sem erro (o arquivo não depende de include nenhum, é autossuficiente).

- [ ] **Step 6: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_dashboard.prw tests/monitor_dashboard_test.prw
git commit -m "feat: dashboard web consolidado (dashboard.json + HTML + WSRestServer)"
```

---

### Task 6: `MonitorMain` — config novo, sem `.ini`, sobe o dashboard

**Files:**
- Modify: `src/monitor.prw`

**Interfaces:**
- Consumes: `MonProcessarUnidade` (Task 2, agora devolve `oRes`), `MonProcessarDbaccess`/`MonProcessarLicenseServer` (Task 2, agora devolvem `oRes`), `MonSalvarDashboard` (Task 5), `MonServirDashboard` (Task 5, via `StartJob`).
- Produces: nada consumido por outra task — é o entry point.

- [ ] **Step 1: Reescrever `src/monitor.prw`**

```advpl
#include "monitor_lib.prw"
#include "monitor_broker.prw"
#include "monitor_dashboard.prw"

User Function MonitorMain()
    Local cConfigPath    := "config.json"
    Local cStatePath     := "state.json"
    Local cLogPath       := "monitor.log"
    Local cDashboardPath := "dashboard.json"
    Local oConfig
    Local oState
    Local aUnidades
    Local aResUnidades
    Local aResDbaccess
    Local oResLicense
    Local oResUnidade
    Local i

    oConfig := MonLoadConfig(cConfigPath)
    If oConfig == Nil
        ConOut("ERRO FATAL: nao foi possivel ler " + cConfigPath)
        MonLog(cLogPath, "ERRO FATAL: nao foi possivel ler " + cConfigPath)
        Return
    EndIf

    aUnidades := MonGetUnidades(oConfig)
    If Len(aUnidades) == 0
        ConOut("ERRO FATAL: config.json sem a chave 'unidades' ou lista vazia")
        MonLog(cLogPath, "ERRO FATAL: config.json sem a chave 'unidades' ou lista vazia")
        Return
    EndIf

    If !oConfig:HasProperty("intervaloSegundos") .Or. oConfig["intervaloSegundos"] <= 0
        ConOut("ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        Return
    EndIf

    If !oConfig:HasProperty("timeoutMs") .Or. oConfig["timeoutMs"] <= 0
        ConOut("ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        Return
    EndIf

    If oConfig:HasProperty("dashboardPorta") .And. oConfig["dashboardPorta"] > 0
        StartJob("MonServirDashboard", "", .F., oConfig["dashboardPorta"])
        ConOut("Dashboard web em http://localhost:" + AllTrim(Str(oConfig["dashboardPorta"])) + "/")
    Else
        ConOut("AVISO: dashboardPorta ausente/invalida -- dashboard web desabilitado")
        MonLog(cLogPath, "AVISO: dashboardPorta ausente/invalida -- dashboard web desabilitado")
    EndIf

    oState := MonLoadState(cStatePath)

    ConOut("Monitor iniciado. " + AllTrim(Str(Len(aUnidades))) + " unidade(s), intervalo de " + AllTrim(Str(oConfig["intervaloSegundos"])) + "s.")

    While .T.
        aResUnidades := {}
        aResDbaccess := {}
        oResLicense  := Nil

        For i := 1 To Len(aUnidades)
            oResUnidade := MonProcessarUnidade(aUnidades[i]["nome"], aUnidades[i]["host"], aUnidades[i]["porta"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
            AAdd(aResUnidades, oResUnidade)

            If oConfig:HasProperty("portaDbaccess")
                AAdd(aResDbaccess, MonProcessarDbaccess(aUnidades[i]["nome"], aUnidades[i]["host"], oConfig["portaDbaccess"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"]))
            EndIf
        Next

        If oConfig:HasProperty("licenseServer")
            oResLicense := MonProcessarLicenseServer(oConfig["licenseServer"]["host"], oConfig["licenseServer"]["port"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
        EndIf

        MonSalvarDashboard(cDashboardPath, aResUnidades, aResDbaccess, oResLicense)
        MonSaveState(cStatePath, oState)
        Sleep(oConfig["intervaloSegundos"] * 1000)
    EndDo
Return
```

- [ ] **Step 2: Verificação de compilação**

```bash
cd ~/Projetos/monitor
~/Projetos/AdvPP/advplc check src/monitor.prw
```

Expected: sem erro — confirma que os três `#include` resolvem e todas as funções chamadas (`MonLoadConfig`, `MonGetUnidades`, `MonProcessarUnidade`, `MonProcessarDbaccess`, `MonProcessarLicenseServer`, `MonSalvarDashboard`, `MonServirDashboard`, `MonLoadState`, `MonSaveState`, `MonLog`) existem nos arquivos incluídos.

- [ ] **Step 3: Teste manual de ponta a ponta (não automatizável em unit test — processo de fundo real)**

```bash
cd ~/Projetos/monitor
cat > config.json <<'EOF'
{
  "unidades": [{"nome": "TESTE", "host": "127.0.0.1", "porta": 19191}],
  "intervaloSegundos": 5,
  "timeoutMs": 1000,
  "dashboardPorta": 9099,
  "telegramBotToken": "TOKEN_FAKE",
  "telegramChatId": "0"
}
EOF

# num terminal, suba o servidor de teste na porta 19191 (README ja documenta)
python3 -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 19191), H).serve_forever()
" &

~/Projetos/AdvPP/advplc build src/monitor.prw -o /tmp/monitor_teste
/tmp/monitor_teste &
sleep 2
curl -s http://localhost:9099/ | grep -o "TESTE"
kill %1 %2 2>/dev/null
rm -f config.json state.json dashboard.json monitor.log /tmp/monitor_teste
```

Expected: a saída do `curl` imprime `TESTE` (o dashboard subiu e a unidade aparece na página, mesmo estando `DOWN` — o servidor de teste responde `"ok"` puro, não é um broker de verdade, então `UP` fica falso, mas a linha da unidade existe no HTML).

- [ ] **Step 4: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor.prw
git commit -m "feat: MonitorMain usa config parametrizavel (sem .ini) e sobe o dashboard web"
```

---

### Task 7: `config.example.json` (Ortobom) + README + suíte completa

**Files:**
- Modify: `config.example.json`
- Modify: `README.md`

**Interfaces:** nenhuma (documentação e dado de configuração, sem código).

- [ ] **Step 1: Reescrever `config.example.json`**

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

- [ ] **Step 2: Atualizar `README.md` — parágrafo de abertura**

Troque:

```markdown
Vigia o appserver web de cada unidade Protheus listada num `.ini` de
conexão existente — checagem HTTP (`GET` simples numa porta fixa) com
medição de latência — e avisa no Telegram quando uma unidade cai ou
volta. Opcionalmente também vigia o dbaccess de cada unidade (mesmo
host do appserver, porta configurável, checagem TCP) e um license
server centralizado (único para todo o ambiente, checagem TCP) — ver
`portaDbaccess`/`licenseServer` em "Configurar" abaixo.
```

por:

```markdown
Vigia o TOTVS Broker de cada unidade Protheus listada em `config.json`
(nome, host e porta — 100% parametrizável, sem depender de nenhum `.ini`
de conexão) — checagem HTTP no endpoint `/totvs_broker_query`, com
medição de latência, e interpreta o HTML de resposta do broker
(sessões/conexões ativas, e a tabela de servers, incluindo servers
individuais que caem em quarentena) — avisa no Telegram quando a
unidade inteira cai/volta e quando um server individual entra/sai de
quarentena. Opcionalmente também vigia o dbaccess de cada unidade
(mesmo host do appserver, porta configurável, checagem TCP) e um
license server centralizado (único para todo o ambiente, checagem TCP)
— ver `portaDbaccess`/`licenseServer` em "Configurar" abaixo. Um
dashboard web consolidado (ver "Dashboard web" abaixo) reúne tudo isso
numa única página.
```

- [ ] **Step 3: Atualizar `README.md` — seção "Configurar"**

Troque a seção inteira (do `## Configurar` até o parágrafo que termina em "...`LICENSE_SERVER`, respectivamente — não colidem com a chave da própria unidade (appserver).") por:

```markdown
## Configurar

Copie `config.example.json` para `config.json` na mesma pasta dos executáveis
e preencha:

- `unidades`: lista de objetos `{"nome": "...", "host": "...", "porta": ...}`
  — uma entrada por unidade a vigiar. `nome` é o rótulo usado nos logs e
  alertas (livre, sem precisar bater com nada externo); `host`/`porta`
  apontam direto pro TOTVS Broker daquela unidade. Adicionar, remover ou
  mudar IP/porta de uma unidade é só editar essa lista — não depende de
  nenhum `.ini` de conexão do SmartClient.
- `telegramBotToken` / `telegramChatId`: credenciais do bot do Telegram
  que vai mandar os alertas.
- `intervaloSegundos` / `timeoutMs`: frequência da checagem e timeout
  de cada tentativa (tanto do `GET` HTTP do broker quanto das checagens
  TCP de dbaccess/license server). `timeoutMs` é convertido internamente
  para segundos inteiros, sempre arredondado pra cima e com no mínimo 1
  segundo.
- `dashboardPorta`: porta HTTP local onde o dashboard web consolidado
  fica disponível (ver "Dashboard web" abaixo). Se ausente ou inválida,
  o `MonitorService` loga um aviso e roda normalmente sem o dashboard —
  as checagens e os alertas do Telegram não dependem disso.
- `portaDbaccess` (opcional): porta do dbaccess, igual pra todas as
  unidades — o host usado é o mesmo host da unidade. Se essa chave não
  existir no `config.json`, o dbaccess não é checado.
- `licenseServer` (opcional): objeto `{"host": "...", "port": ...}` do
  license server, único pra todo o ambiente (não é por unidade). Se essa
  chave não existir, o license server não é checado.

Cada unidade é checada em `http://<host>:<porta>/totvs_broker_query` —
o mesmo endpoint que a página HTML de status do TOTVS Broker usa. A
unidade conta como `UP` quando o HTTP responde com status abaixo de 500
**e** o corpo é reconhecivelmente uma página do broker (protege contra
"o host respondeu alguma coisa, mas não é o broker" virar um falso UP).
Servers individuais da tabela do broker que entram em quarentena geram
um alerta próprio, granular por `host:porta` do server — independente
do alerta de broker inteiro cair/voltar. **Limitação conhecida:** o
campo `Motivos` da tabela do broker (texto livre, quando preenchido)
nunca foi observado com conteúdo em nenhum ambiente de teste — é
capturado e aparece no alerta quando vier preenchido, mas seu formato
real não está validado.

Alertas de dbaccess saem como `TCPSP dbaccess (host:porta) caiu/voltou`
e de license server como `License Server (host:porta) caiu/voltou`; o
estado de cada um fica guardado em `state.json` sob as chaves
`<UNIDADE>_DBACCESS` e `LICENSE_SERVER`, respectivamente — não colidem
com a chave da própria unidade (broker).
```

- [ ] **Step 4: Adicionar seção "Dashboard web" ao `README.md`**

Insira, logo depois da seção "## Configurar" (antes de "## Rodar os testes"):

```markdown
## Dashboard web

Com `dashboardPorta` configurada, o próprio `MonitorService` (o mesmo
processo de fundo que faz as checagens) sobe um servidor HTTP local
nessa porta — acesse `http://<host-onde-o-monitor-roda>:<dashboardPorta>/`
de qualquer navegador na rede pra ver uma página consolidada com todas
as unidades: status, latência, sessões/conexões ativas do broker, e uma
tabela por unidade com os servers individuais (incluindo os que estão
em quarentena). A página recarrega periodicamente sozinha e reflete
sempre o resultado do ciclo de checagem mais recente — não é preciso
reiniciar nada pra ela atualizar.
```

- [ ] **Step 5: Atualizar `README.md` — seção "Rodar os testes"**

No parágrafo que começa com `tests/monitor_lib_test.prw cobre src/monitor_lib.prw`, troque:

```markdown
`tests/monitor_lib_test.prw` cobre `src/monitor_lib.prw` (checagem HTTP
do appserver com latência, checagem TCP de dbaccess/license server,
estado, config, log, montagem de mensagem e os ciclos de
`MonProcessarUnidade`/`MonProcessarDbaccess`/`MonProcessarLicenseServer`).
```

por:

```markdown
`tests/monitor_lib_test.prw` cobre `src/monitor_lib.prw` (checagem TCP
de dbaccess/license server, estado, config, log, montagem de mensagem).
`tests/monitor_broker_test.prw` cobre `src/monitor_broker.prw` (parser
do HTML do TOTVS Broker contra duas fixtures reais em `tests/fixtures/`
— uma saudável, outra com 9 de 14 servers em quarentena —, a checagem
via `/totvs_broker_query`, e o alerta granular por server).
`tests/monitor_dashboard_test.prw` cobre `src/monitor_dashboard.prw`
(geração do HTML consolidado e da rota HTTP, sem precisar de rede —
`MonServirDashboard`, que sobe o servidor de verdade, é testado
manualmente, ver Task 6 do plano de implementação).
```

Depois, no passo 2 (rodar as suites), troque:

```markdown
2. Em outro terminal, rode as duas suites (ajuste o caminho do `advplc`
   pra onde ele estiver instalado):

       cd tests && /caminho/para/advplc run monitor_lib_test.prw
       cd tests && /caminho/para/advplc run monitor_tui_lib_test.prw
```

por:

```markdown
2. Em outro terminal, rode as quatro suites (ajuste o caminho do
   `advplc` pra onde ele estiver instalado):

       cd tests && /caminho/para/advplc run monitor_lib_test.prw
       cd tests && /caminho/para/advplc run monitor_broker_test.prw
       cd tests && /caminho/para/advplc run monitor_dashboard_test.prw
       cd tests && /caminho/para/advplc run monitor_tui_lib_test.prw
```

E no passo 3 (última linha esperada), troque:

```markdown
3. A última linha da saída de cada suite deve ser `MONITOR_LIB_TEST_FIM`
   ou `MONITOR_TUI_LIB_TEST_FIM`, sem nenhuma linha de erro do
   compilador/interpretador acima dela.
```

por:

```markdown
3. A última linha da saída de cada suite deve ser `MONITOR_LIB_TEST_FIM`,
   `MONITOR_BROKER_TEST_FIM`, `MONITOR_DASHBOARD_TEST_FIM` ou
   `MONITOR_TUI_LIB_TEST_FIM` (conforme a suite), sem nenhuma linha de
   erro do compilador/interpretador acima dela.
```

- [ ] **Step 6: Rodar a suite completa (as quatro, mais o listener de teste)**

```bash
cd ~/Projetos/monitor
python3 -c "
import http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 19191), H).serve_forever()
" &
sleep 1

cd tests
~/Projetos/AdvPP/advplc run monitor_lib_test.prw
~/Projetos/AdvPP/advplc run monitor_broker_test.prw
~/Projetos/AdvPP/advplc run monitor_dashboard_test.prw
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw

kill %1 2>/dev/null
```

Expected: as quatro suites terminam nas linhas `_FIM` esperadas, sem nenhum erro de compilação acima delas, e nenhuma asserção `testeN_...=NAO` onde o esperado era `SIM` (releia a saída linha a linha se algo não bater — mesma orientação que o README já dá).

- [ ] **Step 7: Commit final**

```bash
cd ~/Projetos/monitor
git add config.example.json README.md
git commit -m "docs: config.example.json com unidades Ortobom, README documenta broker/dashboard"
```

---

## Self-Review

- **Cobertura da spec:** schema novo de `unidades` sem `.ini` (Task 6), endpoint `/totvs_broker_query` com sanidade "é broker de verdade" (Task 2), parser do HTML sem regex com as duas fixtures reais (Task 1), alerta granular por server em quarentena (Task 3), bump do `ADVPP_VERSION` (Task 4), dashboard web consolidado (Task 5, ligado ao loop principal no Task 6), `config.example.json` Ortobom + README (Task 7). Nenhum item do "Objetivo" da spec ficou sem task.
- **Fora de escopo respeitado:** nenhuma task mexe em Homologação, GUI Fyne, `MonitorTUI`, ou cria fork/branch — confirmado, nenhuma referência a esses itens em nenhuma task.
- **Placeholders:** nenhum "TBD"/"implementar depois" — toda task tem código completo, inclusive as duas fixtures HTML por inteiro (Task 1) e os três blocos de edição textual do README (Task 7).
- **Consistência de tipos/assinaturas:** `MonProcessarUnidade`, `MonProcessarDbaccess`, `MonProcessarLicenseServer` mudam de `Return Nil` pra `Return oRes` de forma consistente entre onde são definidas (Task 2, `monitor_lib.prw`/`monitor_broker.prw`) e onde são consumidas (Task 6, `MonitorMain`, que monta `aResUnidades`/`aResDbaccess`/`oResLicense` a partir desses retornos pro dashboard). `oServ`/`oRes` usam as mesmas chaves (`HOSTPORTA`, `STATUS`, `SESSOESATIVAS`, etc.) em todo lugar que aparecem — Task 1 define, Task 2/3 consomem, Task 5/6 consomem de novo pro dashboard.
- **Review Focus coberto:** HTML vazio/truncado → Task 1 (`MonParseBrokerHtml("")`, via `testeModo3_vazio`/`testeNum5_vazio`) e Task 2 (`testeCheck5_down_sem_listener` gera corpo vazio de verdade). Host responde mas não é broker → Task 2 (`testeCheck3_up_falso_no_broker`, contra o servidor `"ok"` compartilhado). `dashboard.json` ausente → Task 5 (`teste12`-`teste14`). `dashboard.json` corrompido → Task 5 (`MonRotaDashboard` trata `!oDash:FromJson(cJson)` sem estourar, mesmo padrão do `MonLoadState`). Unidade com host/porta mal formada → Task 2 (`testeCheck8_host_vazio_nao_quebra`).
