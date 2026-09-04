// Monitor library - TCP/IP and unit checking

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
