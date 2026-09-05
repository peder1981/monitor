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

User Function MonSetStatus(oState, cUnidade, cStatus)
    oState[cUnidade] := cStatus
Return Nil

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

    oRes["UNIDADE"] := cChave
    oRes["HOST"]    := cHost
    oRes["PORT"]    := nPort
    oRes["UP"]      := PING(cHost, nPort, nTimeoutMs)
    oRes["ERRO"]    := ""
Return oRes

User Function MonProcessarResultado(cChave, cRotulo, oRes, oState, cLogPath, cToken, cChatId)
    Local cStatusAnterior
    Local cStatusNovo
    Local cMsg

    cStatusAnterior := MonGetStatusAnterior(oState, cChave)
    cStatusNovo := IIF(oRes["UP"], "UP", "DOWN")

    MonLog(cLogPath, cChave + " " + oRes["HOST"] + ":" + AllTrim(Str(oRes["PORT"])) + " status=" + cStatusNovo)

    If cStatusNovo != cStatusAnterior
        If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo == "DOWN"
            cMsg := MonMontarMensagem(cRotulo, oRes["HOST"], oRes["PORT"], cStatusNovo)
            If !MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " falha ao notificar telegram")
            EndIf
        EndIf
        MonSetStatus(oState, cChave, cStatusNovo)
    EndIf
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
Return Nil

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
Return Nil

User Function MonProcessarUnidade(cUnidade, cIniPath, nTimeoutMs, oState, cLogPath, cToken, cChatId)
    Local oRes
    Local cStatusAnterior
    Local cStatusNovo
    Local cMsg
    Local e

    Try
        oRes := MonCheckUnidade(cUnidade, cIniPath, nTimeoutMs)

        If oRes["ERRO"] != ""
            MonLog(cLogPath, cUnidade + " sem_dados erro=" + oRes["ERRO"])
            Return Nil
        EndIf

        cStatusAnterior := MonGetStatusAnterior(oState, cUnidade)
        cStatusNovo := IIF(oRes["UP"], "UP", "DOWN")

        MonLog(cLogPath, cUnidade + " " + oRes["HOST"] + ":" + AllTrim(Str(oRes["PORT"])) + " status=" + cStatusNovo)

        If cStatusNovo != cStatusAnterior
            // Não notifica "[OK] ... voltou" na primeira execução (não havia
            // estado anterior pra "voltar" de); mas transição pra DOWN sempre
            // notifica, mesmo vindo de DESCONHECIDO (unidade já nasce caída).
            If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo == "DOWN"
                cMsg := MonMontarMensagem(cUnidade, oRes["HOST"], oRes["PORT"], cStatusNovo)
                If !MonNotificarTelegram(cToken, cChatId, cMsg)
                    MonLog(cLogPath, cUnidade + " falha ao notificar telegram")
                EndIf
            EndIf
            MonSetStatus(oState, cUnidade, cStatusNovo)
        EndIf
    Catch e
        MonLog(cLogPath, cUnidade + " erro_interno=" + e:description)
    EndTry
Return Nil
