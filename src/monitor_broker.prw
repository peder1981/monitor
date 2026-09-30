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

// Remove qualquer tag HTML de cTexto (ex: "<span class='tooltiptext'>
// motivo</span>" dentro de uma celula) -- usado por MonCelulasLinha pra
// nunca deixar uma tag aninhada disfarcar o valor real da celula.
User Function MonRemoverTags(cTexto)
    Local nPos
    Local nFimTag

    Do While .T.
        nPos := At("<", cTexto)
        If nPos == 0
            Exit
        EndIf
        nFimTag := At(">", SubStr(cTexto, nPos))
        If nFimTag == 0
            cTexto := SubStr(cTexto, 1, nPos - 1)
            Exit
        EndIf
        cTexto := SubStr(cTexto, 1, nPos - 1) + SubStr(cTexto, nPos + nFimTag)
    EndDo
Return cTexto

// Achado importante da revisao final: dividir por "<td>" literal falha
// em silencio quando a celula vem com atributo (ex: "<td class=
// 'inQuarantine'>"), o que desalinha todas as colunas seguintes e pode
// esconder uma quarentena real como "OK". Divide por "<td" (sem o ">"),
// localiza o fechamento da tag ">" em cada pedaco pra achar onde o
// conteudo real comeca. NAO remove tags aninhadas aqui -- a celula do
// server precisa do <a href=...> intacto pra MonExtrairHostPorta; quem
// consome a celula de quarentena/motivo (MonExtrairLinhaServer) e que
// decide tirar tag aninhada (ex: tooltip) do proprio valor.
User Function MonCelulasLinha(cLinha)
    Local aPedacos := StrTokArr(cLinha, "<td")
    Local aCelulas := {}
    Local nPosFechaTag
    Local cConteudo
    Local nFim
    Local i

    For i := 2 To Len(aPedacos)
        nPosFechaTag := At(">", aPedacos[i])
        If nPosFechaTag == 0
            cConteudo := ""
        Else
            cConteudo := SubStr(aPedacos[i], nPosFechaTag + 1)
        EndIf

        nFim := At("</td>", cConteudo)
        If nFim > 0
            cConteudo := SubStr(cConteudo, 1, nFim - 1)
        EndIf

        AAdd(aCelulas, AllTrim(cConteudo))
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
        cQuarentena         := AllTrim(MonRemoverTags(aCel[4]))
        oServ["MOTIVO"]     := IIF(AllTrim(MonRemoverTags(aCel[5])) == "-", "", AllTrim(MonRemoverTags(aCel[5])))
        oServ["USUARIOS"]  := MonSoNumero(aCel[6])
        oServ["THREADS"]   := MonSoNumero(aCel[7])
        oServ["MEMORIAKB"] := MonSoNumero(aCel[8])
        oServ["CPU"]       := MonSoNumero(aCel[9])
        oServ["UPTIME"]    := AllTrim(aCel[10])
        oServ["PID"]       := MonSoNumero(aCel[11])
    Else
        oServ["SESSOES"]   := 0
        oServ["CONEXOES"]  := MonSoNumero(aCel[2])
        cQuarentena         := AllTrim(MonRemoverTags(aCel[3]))
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

// Achado de campo (pos-deploy real): o broker devolve JSON (nao HTML)
// quando o client nao manda os headers que um navegador manda -- e
// exatamente o caso do FWHttpGet do monitor. A fixture HTML colada no
// inicio do projeto veio de um navegador de verdade; em producao, o
// FWHttpGet recebe JSON do mesmo endpoint, mesma versao de broker. O
// JSON e estritamente melhor pra esse parser: "inquarantine"/"disabled"
// sao booleanos de verdade, nao precisa inferir de texto de coluna.
User Function MonParseBrokerJson(cBody)
    Local oRes := JsonObject():New()
    Local oJson := JsonObject():New()
    Local aServers := {}
    Local aServersOrig
    Local oServOrig
    Local oServ
    Local i

    oRes["VALIDO"]          := .F.
    oRes["SESSOESATIVAS"]   := 0
    oRes["CONEXOESATIVAS"]  := 0
    oRes["VERSAO"]           := ""
    oRes["SERVERS"]          := {}

    If !oJson:FromJson(cBody)
        Return oRes
    EndIf
    If !oJson:HasProperty("servers")
        Return oRes
    EndIf

    oRes["VALIDO"] := .T.
    oRes["VERSAO"] := IIF(oJson:HasProperty("version"), oJson["version"], "")

    If oJson:HasProperty("total")
        oRes["SESSOESATIVAS"]  := oJson["total"]["sessions"]
        oRes["CONEXOESATIVAS"] := oJson["total"]["connections"]
    EndIf

    aServersOrig := oJson["servers"]
    For i := 1 To Len(aServersOrig)
        oServOrig := aServersOrig[i]
        oServ := JsonObject():New()

        oServ["HOSTPORTA"]  := oServOrig["server"]
        oServ["SESSOES"]    := oServOrig["sessions"]
        oServ["CONEXOES"]   := oServOrig["connections"]
        oServ["USUARIOS"]   := oServOrig["users"]
        oServ["THREADS"]    := oServOrig["threads"]
        oServ["MEMORIAKB"]  := oServOrig["memory"]
        oServ["CPU"]        := oServOrig["cpu"]
        oServ["UPTIME"]     := oServOrig["uptime"]
        oServ["PID"]        := oServOrig["pid"]
        oServ["MOTIVO"]     := IIF(oServOrig:HasProperty("disabled_reasons"), oServOrig["disabled_reasons"], "")

        If oServOrig["inquarantine"]
            oServ["STATUS"]           := "QUARENTENA"
            oServ["INICIOQUARENTENA"] := oServOrig["quarantine_entry_time"]
        ElseIf oServOrig["disabled"]
            oServ["STATUS"]           := "DESABILITADO"
            oServ["INICIOQUARENTENA"] := oServOrig["disabled_entry_time"]
        Else
            oServ["STATUS"]           := "OK"
            oServ["INICIOQUARENTENA"] := ""
        EndIf

        AAdd(aServers, oServ)
    Next
    oRes["SERVERS"] := aServers
Return oRes

// Ponto unico de entrada pro parsing: tenta JSON primeiro (formato que o
// FWHttpGet do monitor realmente recebe em producao); se o corpo nao for
// JSON valido de broker, cai pro parser de HTML (mantido pra nao quebrar
// quem hoje recebe HTML por algum motivo -- ex: proxy/cache no meio do
// caminho, ou uma configuracao de broker diferente).
User Function MonParseBrokerResposta(cBody)
    Local cTrim := AllTrim(cBody)
    Local oRes

    If Left(cTrim, 1) == "{"
        oRes := MonParseBrokerJson(cTrim)
        If oRes["VALIDO"]
            Return oRes
        EndIf
    EndIf
Return MonParseBrokerHtml(cBody)

// Achado do operador em campo: bases em build antiga (12.1.2310) so
// expoem o broker num caminho diferente do padrao
// (/totvs_broker_query/status, nao /totvs_broker_query) -- cEndpoint e
// opcional (Nil ou "" cai no caminho padrao), configuravel por unidade
// via a chave "endpoint" no config.json.
User Function MonMontarUrlBroker(cHost, nPorta, cEndpoint)
    Local cCaminho := IIF(cEndpoint == Nil .Or. cEndpoint == "", "/totvs_broker_query", cEndpoint)
Return "http://" + cHost + ":" + AllTrim(Str(nPorta)) + cCaminho

User Function MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs, cEndpoint)
    Local oRes := JsonObject():New()
    Local nT1
    Local nStatus
    Local cBody
    Local oParsed
    Local lHttpOk

    oRes["UNIDADE"]  := cUnidade
    oRes["HOST"]     := cHost
    oRes["PORT"]     := nPorta
    oRes["ENDPOINT"] := IIF(cEndpoint == Nil .Or. cEndpoint == "", "/totvs_broker_query", cEndpoint)

    FWHttpTimeout(Max(1, Int((nTimeoutMs + 999) / 1000)))
    nT1 := TimeCounter()
    nStatus := FWHttpGet(MonMontarUrlBroker(cHost, nPorta, cEndpoint))
    oRes["LATENCIAMS"] := TimeCounter() - nT1
    cBody := FWHttpBody()

    lHttpOk := (nStatus > 0 .And. nStatus < 500)
    oParsed := MonParseBrokerResposta(cBody)

    oRes["UP"]              := (lHttpOk .And. oParsed["VALIDO"])
    oRes["SESSOESATIVAS"]   := oParsed["SESSOESATIVAS"]
    oRes["CONEXOESATIVAS"]  := oParsed["CONEXOESATIVAS"]
    oRes["VERSAO"]           := oParsed["VERSAO"]
    oRes["SERVERS"]          := oParsed["SERVERS"]
Return oRes

// Achado de campo: o JSON real do broker devolve "disabled" como
// booleano de verdade (alem de "inquarantine"), entao STATUS deixou de
// ser binario -- agora e OK/QUARENTENA/DESABILITADO.
User Function MonMontarMensagemServer(cUnidade, cHostPorta, cStatusNovo, cInicioQuarentena, cMotivo)
    Local cTexto

    If cStatusNovo == "QUARENTENA"
        cTexto := "[ALERTA] " + cUnidade + " server " + cHostPorta + " entrou em quarentena as " + cInicioQuarentena
        If cMotivo != ""
            cTexto += ", motivo: " + cMotivo
        EndIf
    ElseIf cStatusNovo == "DESABILITADO"
        cTexto := "[ALERTA] " + cUnidade + " server " + cHostPorta + " foi desabilitado as " + cInicioQuarentena
        If cMotivo != ""
            cTexto += ", motivo: " + cMotivo
        EndIf
    Else
        cTexto := "[OK] " + cUnidade + " server " + cHostPorta + " voltou ao normal"
    EndIf
Return cTexto

User Function MonProcessarServidorBroker(cUnidade, oServ, oState, cLogPath, cToken, cChatId)
    Local cChave := cUnidade + "_SERVER_" + oServ["HOSTPORTA"]
    Local cStatusAnterior := MonGetStatusAnterior(oState, cChave)
    Local cStatusNovo := oServ["STATUS"]
    Local cMsg

    If cStatusNovo != cStatusAnterior
        If cStatusAnterior != "DESCONHECIDO" .Or. cStatusNovo != "OK"
            cMsg := MonMontarMensagemServer(cUnidade, oServ["HOSTPORTA"], cStatusNovo, oServ["INICIOQUARENTENA"], oServ["MOTIVO"])
            If MonNotificarTelegram(cToken, cChatId, cMsg)
                MonLog(cLogPath, cChave + " notificou telegram com sucesso")
            Else
                MonLog(cLogPath, cChave + " falha ao notificar telegram (http=" + AllTrim(Str(FWHttpStatus())) + " erro=" + FWHttpError() + ")")
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

User Function MonProcessarUnidade(cUnidade, cHost, nPorta, nTimeoutMs, oState, cLogPath, cToken, cChatId, cEndpoint)
    Local oRes
    Local e

    Try
        oRes := MonCheckBroker(cUnidade, cHost, nPorta, nTimeoutMs, cEndpoint)
        MonProcessarResultado(cUnidade, cUnidade, oRes, oState, cLogPath, cToken, cChatId)
        MonProcessarServersBroker(cUnidade, oRes["SERVERS"], oState, cLogPath, cToken, cChatId)
    Catch e
        MonLog(cLogPath, cUnidade + " erro_interno=" + e:description)
    EndTry
Return oRes
