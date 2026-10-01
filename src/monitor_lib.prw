// Monitor library - checagem HTTP/TCP e controle de estado

// CSS compartilhado pelas 3 paginas do dashboard web (status, /config,
// /analise) -- centralizado aqui (primeiro include de monitor.prw) pra
// nao duplicar estilo em cada gerador de HTML. Sem fonte/CDN externo de
// proposito: o dashboard roda numa rede interna (10.0.100.x) sem
// garantia de saida pra internet.
User Function MonCssBase()
Return ":root{--bg:#f4f6f8;--card:#fff;--text:#1f2a37;--muted:#64748b;" + ;
    "--border:#e2e8f0;--accent:#2563eb;--up:#16a34a;--up-bg:#dcfce7;" + ;
    "--down:#dc2626;--down-bg:#fee2e2;--warn:#d97706;--warn-bg:#fef3c7;" + ;
    "--off:#6b7280;--off-bg:#f1f5f9}" + ;
    "*{box-sizing:border-box}" + ;
    "body{margin:0;font-family:-apple-system,'Segoe UI',Roboto,Arial,sans-serif;background:var(--bg);color:var(--text)}" + ;
    "header.topbar{background:#111827;color:#fff;padding:16px 24px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px}" + ;
    "header.topbar h1{margin:0;font-size:1.25rem;font-weight:600}" + ;
    "header.topbar nav a{color:#cbd5e1;text-decoration:none;margin-left:16px;font-size:0.9rem}" + ;
    "header.topbar nav a:hover{color:#fff}" + ;
    "main{padding:24px;max-width:1100px;margin:0 auto}" + ;
    ".card{background:var(--card);border:1px solid var(--border);border-radius:10px;padding:20px;margin-bottom:24px;box-shadow:0 1px 2px rgba(0,0,0,.04)}" + ;
    ".card h2{margin-top:0;font-size:1.05rem}" + ;
    "table{width:100%;border-collapse:collapse;font-size:0.9rem}" + ;
    "th{text-align:left;padding:8px 12px;color:var(--muted);font-weight:600;border-bottom:2px solid var(--border);white-space:nowrap}" + ;
    "td{padding:8px 12px;border-bottom:1px solid var(--border)}" + ;
    "tr:last-child td{border-bottom:none}" + ;
    "tr:hover td{background:#f8fafc}" + ;
    ".badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:0.78rem;font-weight:600;white-space:nowrap}" + ;
    ".badge-up,.badge-ok{background:var(--up-bg);color:var(--up)}" + ;
    ".badge-down{background:var(--down-bg);color:var(--down)}" + ;
    ".badge-quarentena{background:var(--warn-bg);color:var(--warn)}" + ;
    ".badge-desabilitado,.badge-off{background:var(--off-bg);color:var(--off)}" + ;
    ".meta{color:var(--muted);font-size:0.85rem;margin-bottom:16px}" + ;
    ".msg{padding:12px 16px;margin-bottom:20px;background:var(--warn-bg);border:1px solid #fcd34d;border-radius:8px;color:#78350f}" + ;
    ".empty{color:var(--muted);font-style:italic}" + ;
    "a{color:var(--accent)}" + ;
    "code{background:#eef2f7;padding:1px 6px;border-radius:4px;font-size:0.85em}" + ;
    "textarea{width:100%;min-height:280px;font-family:ui-monospace,Consolas,monospace;font-size:13px;padding:10px;border:1px solid var(--border);border-radius:8px}" + ;
    "input[type=password]{padding:8px 10px;border:1px solid var(--border);border-radius:6px}" + ;
    "button{padding:8px 18px;border:none;border-radius:6px;background:var(--accent);color:#fff;font-weight:600;cursor:pointer}" + ;
    "button:disabled{background:#94a3b8;cursor:not-allowed}" + ;
    "@media(max-width:640px){main{padding:12px}header.topbar{padding:12px 16px}}"

// Badge de status -- usado nas 3 paginas pra UP/DOWN/OK/QUARENTENA/
// DESABILITADO em vez de pintar a linha inteira da tabela.
User Function MonBadge(cStatus)
    Local cClasse := "badge-off"

    If cStatus == "UP" .Or. cStatus == "OK"
        cClasse := IIF(cStatus == "UP", "badge-up", "badge-ok")
    ElseIf cStatus == "DOWN"
        cClasse := "badge-down"
    ElseIf cStatus == "QUARENTENA"
        cClasse := "badge-quarentena"
    ElseIf cStatus == "DESABILITADO"
        cClasse := "badge-desabilitado"
    EndIf
Return "<span class='badge " + cClasse + "'>" + cStatus + "</span>"

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

// Gate reusado no startup (fatal se invalido) e no hot-reload de cada
// ciclo do MonitorMain (se invalido, mantem o config anterior em memoria
// em vez de derrubar o loop) -- necessario desde que o dashboard web
// ganhou a capacidade de editar config.json em producao.
User Function MonConfigValido(oConfig)
    If oConfig == Nil
        Return .F.
    EndIf
    If Len(MonGetUnidades(oConfig)) == 0
        Return .F.
    EndIf
    If !oConfig:HasProperty("intervaloSegundos") .Or. oConfig["intervaloSegundos"] <= 0
        Return .F.
    EndIf
    If !oConfig:HasProperty("timeoutMs") .Or. oConfig["timeoutMs"] <= 0
        Return .F.
    EndIf
Return .T.

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
            If MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " notificou telegram com sucesso")
            Else
                MonLog(cLogPath, cChave + " falha ao notificar telegram (http=" + AllTrim(Str(FWHttpStatus())) + " erro=" + FWHttpError() + ")")
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
