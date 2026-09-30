// Dashboard web consolidado -- servido pelo proprio MonitorService via
// WSRestServer (nativa disponivel a partir do ADVPP v4.2.0, que devolve
// HTML cru via Return {"__RAW_HTTP__", cContentType, cBody}). A rota HTTP
// roda numa VM isolada (sem acesso as variaveis do loop principal), entao
// le sempre o snapshot mais recente gravado em disco por
// MonSalvarDashboard -- mesmo padrao ja usado por state.json.

// JsonObject:ToJson() do AdvPP nao serializa array/objeto aninhado (so
// faz stringify raso de qualquer valor que nao seja string/numero/bool/
// nil) -- entao dashboard.json (que tem UNIDADES como array de objetos,
// cada um com um array SERVERS aninhado) e montado aqui na mao, string
// por string. FromJson() (leitura, em MonRotaDashboard) recursa
// corretamente de verdade, entao o round-trip funciona.
User Function MonJsonEscape(cTexto)
    cTexto := StrTran(cTexto, "\", "\\")
    cTexto := StrTran(cTexto, '"', '\"')
Return cTexto

User Function MonBoolJson(lVal)
Return IIF(lVal, "true", "false")

User Function MonServersParaJson(aServers)
    Local cJson := "["
    Local i
    Local oS

    For i := 1 To Len(aServers)
        oS := aServers[i]
        If i > 1
            cJson += ","
        EndIf
        cJson += '{"HOSTPORTA":"' + MonJsonEscape(oS["HOSTPORTA"]) + '",'
        cJson += '"STATUS":"' + MonJsonEscape(oS["STATUS"]) + '",'
        cJson += '"USUARIOS":' + AllTrim(Str(oS["USUARIOS"])) + ','
        cJson += '"MEMORIAKB":' + AllTrim(Str(oS["MEMORIAKB"])) + ','
        cJson += '"CPU":' + AllTrim(Str(oS["CPU"])) + '}'
    Next
    cJson += "]"
Return cJson

User Function MonUnidadesParaJson(aUnidades)
    Local cJson := "["
    Local i
    Local oU

    For i := 1 To Len(aUnidades)
        oU := aUnidades[i]
        If i > 1
            cJson += ","
        EndIf
        cJson += '{"UNIDADE":"' + MonJsonEscape(oU["UNIDADE"]) + '",'
        cJson += '"HOST":"' + MonJsonEscape(oU["HOST"]) + '",'
        cJson += '"PORT":' + AllTrim(Str(oU["PORT"])) + ','
        cJson += '"UP":' + MonBoolJson(oU["UP"]) + ','
        cJson += '"LATENCIAMS":' + AllTrim(Str(oU["LATENCIAMS"])) + ','
        cJson += '"SESSOESATIVAS":' + AllTrim(Str(oU["SESSOESATIVAS"])) + ','
        cJson += '"CONEXOESATIVAS":' + AllTrim(Str(oU["CONEXOESATIVAS"])) + ','
        cJson += '"SERVERS":' + MonServersParaJson(oU["SERVERS"]) + '}'
    Next
    cJson += "]"
Return cJson

User Function MonChecagemParaJson(oChk)
    Local cJson

    If oChk == Nil
        Return "null"
    EndIf

    cJson := '{"UNIDADE":"' + MonJsonEscape(oChk["UNIDADE"]) + '",'
    cJson += '"HOST":"' + MonJsonEscape(oChk["HOST"]) + '",'
    cJson += '"PORT":' + AllTrim(Str(oChk["PORT"])) + ','
    cJson += '"UP":' + MonBoolJson(oChk["UP"]) + ','
    cJson += '"LATENCIAMS":' + AllTrim(Str(oChk["LATENCIAMS"]))
    cJson += '}'
Return cJson

User Function MonChecagensParaJson(aChks)
    Local cJson := "["
    Local i

    For i := 1 To Len(aChks)
        If i > 1
            cJson += ","
        EndIf
        cJson += MonChecagemParaJson(aChks[i])
    Next
    cJson += "]"
Return cJson

// nIntervaloSegundos e opcional (chamada antiga de 4 args continua
// funcionando, cai no default abaixo) -- usado so pra montar o
// <meta http-equiv='refresh'> do dashboard (achado importante da
// revisao final: a pagina nao se recarregava sozinha, e o README
// afirmava que sim). Default de 30s evita "content='0'" (recarregaria
// em loop) quando o valor vier ausente/invalido.
User Function MonSalvarDashboard(cPath, aUnidadesRes, aDbaccessRes, oLicenseRes, nIntervaloSegundos)
    Local cJson := "{"
    Local nIntervalo := IIF(nIntervaloSegundos == Nil .Or. nIntervaloSegundos <= 0, 30, nIntervaloSegundos)

    cJson += '"ATUALIZADOEM":"' + MonJsonEscape(DTOC(Date()) + " " + Time()) + '",'
    cJson += '"INTERVALOSEGUNDOS":' + AllTrim(Str(nIntervalo)) + ','
    cJson += '"UNIDADES":' + MonUnidadesParaJson(aUnidadesRes) + ','
    cJson += '"DBACCESS":' + MonChecagensParaJson(aDbaccessRes) + ','
    cJson += '"LICENSESERVER":' + MonChecagemParaJson(oLicenseRes)
    cJson += "}"
Return MemoWrite(cPath, cJson)

User Function MonLinhaChecagem(cNome, cHost, nPort, lUp, nLatenciaMs)
    Local cHtml := "<tr class='" + IIF(lUp, "up", "down") + "'>"

    cHtml += "<td>" + cNome + "</td>"
    cHtml += "<td>" + cHost + ":" + AllTrim(Str(nPort)) + "</td>"
    cHtml += "<td>" + IIF(lUp, "UP", "DOWN") + "</td>"
    cHtml += "<td>" + AllTrim(Str(Round(nLatenciaMs, 0))) + "</td>"
    cHtml += "</tr>"
Return cHtml

User Function MonGerarDashboardHtml(oDash)
    Local nIntervalo := IIF(oDash:HasProperty("INTERVALOSEGUNDOS") .And. oDash["INTERVALOSEGUNDOS"] > 0, oDash["INTERVALOSEGUNDOS"], 30)
    Local cHtml := "<!doctype html><html><head><meta charset='utf-8'>" + ;
        "<meta http-equiv='refresh' content='" + AllTrim(Str(nIntervalo)) + "'>" + ;
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
