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
