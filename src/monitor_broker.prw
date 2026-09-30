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

// Ruling (Task 1, teste3_conexoes): a fixture real mostra que so "sessões
// ativas" vem dentro de <span>; "conexões ativas" (broker HTTP) e texto
// solto ("Existem 175 conexões ativas..."), sem tag ao redor -- o brief
// original assumia os dois sempre dentro de <span>, o que nao bate com o
// HTML real. MonPrimeiroNumero acha o primeiro digito dentro do trecho em
// vez de exigir que o trecho comece com digito, cobrindo os dois casos.
User Function MonPrimeiroNumero(cTexto)
    Local i
    Local nPos := 0

    For i := 1 To Len(cTexto)
        If IsDigit(SubStr(cTexto, i, 1))
            nPos := i
            Exit
        EndIf
    Next
    If nPos == 0
        Return 0
    EndIf
Return MonSoNumero(SubStr(cTexto, nPos))

User Function MonExtrairAtivas(cHtml)
    Local oRes := JsonObject():New()
    Local cAncora := " ativas"
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
            oRes["SESSOESATIVAS"] := MonPrimeiroNumero(cTrecho)
        ElseIf "conex" $ cTrecho
            oRes["CONEXOESATIVAS"] := MonPrimeiroNumero(cTrecho)
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
