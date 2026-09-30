// Edicao de unidades (host/porta monitorados) pelo proprio dashboard web,
// sem precisar editar config.json na mao nem reiniciar o MonitorService.
//
// Limitacao de toolchain (AdvPP): WSRestServer nao expoe headers HTTP pro
// handler (so query string + path params + corpo JSON, ver pkg/rest/
// rest.go:dispatch), entao HTTP Basic Auth de verdade (popup nativo do
// navegador) nao e possivel. A "senha" aqui e um campo de formulario
// comparado no servidor -- nao e criptograficamente forte (trafega em
// texto claro, sem TLS, visivel na URL porque o formulario usa GET em vez
// de POST -- o dispatch do WSRestServer rejeita qualquer corpo POST que
// nao seja JSON valido, e um <form> HTML normal nao consegue montar um
// corpo JSON). E so uma barreira contra edicao acidental/casual, nao
// controle de acesso de verdade -- documentado na propria pagina tambem.

User Function MonTokensLinha(cLinha)
    Local aBrutos := StrTokArr(cLinha, " ")
    Local aTokens := {}
    Local i

    For i := 1 To Len(aBrutos)
        If AllTrim(aBrutos[i]) != ""
            AAdd(aTokens, AllTrim(aBrutos[i]))
        EndIf
    Next
Return aTokens

User Function MonTextoParaUnidades(cTexto)
    Local oRes := JsonObject():New()
    Local aLinhas := StrTokArr(StrTran(cTexto, Chr(13), ""), Chr(10))
    Local aUnidades := {}
    Local cLinha
    Local aTokens
    Local oU
    Local i

    oRes["OK"]   := .T.
    oRes["ERRO"] := ""

    For i := 1 To Len(aLinhas)
        cLinha := AllTrim(aLinhas[i])
        If cLinha != ""
            aTokens := MonTokensLinha(cLinha)
            If Len(aTokens) != 3
                oRes["OK"]   := .F.
                oRes["ERRO"] := "linha invalida (precisa de NOME HOST PORTA): " + cLinha
            ElseIf MonSoNumero(aTokens[3]) <= 0
                oRes["OK"]   := .F.
                oRes["ERRO"] := "porta invalida na linha: " + cLinha
            Else
                oU := JsonObject():New()
                oU["nome"]  := aTokens[1]
                oU["host"]  := aTokens[2]
                oU["porta"] := MonSoNumero(aTokens[3])
                AAdd(aUnidades, oU)
            EndIf
        EndIf
    Next

    If oRes["OK"] .And. Len(aUnidades) == 0
        oRes["OK"]   := .F.
        oRes["ERRO"] := "lista de unidades nao pode ficar vazia"
    EndIf

    oRes["UNIDADES"] := aUnidades
Return oRes

User Function MonUnidadesParaTexto(aUnidades)
    Local cTexto := ""
    Local oU
    Local i

    For i := 1 To Len(aUnidades)
        oU := aUnidades[i]
        cTexto += oU["nome"] + " " + oU["host"] + " " + AllTrim(Str(oU["porta"])) + Chr(10)
    Next
Return cTexto

User Function MonUnidadesConfigParaJson(aUnidades)
    Local cJson := "["
    Local oU
    Local i

    For i := 1 To Len(aUnidades)
        oU := aUnidades[i]
        If i > 1
            cJson += ","
        EndIf
        cJson += '{"nome":"' + MonJsonEscape(oU["nome"]) + '","host":"' + MonJsonEscape(oU["host"]) + '","porta":' + AllTrim(Str(oU["porta"])) + '}'
    Next
    cJson += "]"
Return cJson

// Reescreve config.json inteiro, trocando so a chave "unidades" -- as
// demais chaves vem do oConfig ja carregado (JsonObject:ToJson() do
// AdvPP nao serializa aninhado, mesma limitacao ja documentada em
// monitor_dashboard.prw, entao o JSON e montado na mao aqui tambem).
User Function MonConfigParaJson(oConfig, aUnidadesNovas)
    Local cJson := "{"

    cJson += '"unidades":' + MonUnidadesConfigParaJson(aUnidadesNovas)
    cJson += ',"intervaloSegundos":' + AllTrim(Str(oConfig["intervaloSegundos"]))
    cJson += ',"timeoutMs":' + AllTrim(Str(oConfig["timeoutMs"]))

    If oConfig:HasProperty("dashboardPorta")
        cJson += ',"dashboardPorta":' + AllTrim(Str(oConfig["dashboardPorta"]))
    EndIf
    If oConfig:HasProperty("dashboardSenha")
        cJson += ',"dashboardSenha":"' + MonJsonEscape(oConfig["dashboardSenha"]) + '"'
    EndIf
    If oConfig:HasProperty("telegramBotToken")
        cJson += ',"telegramBotToken":"' + MonJsonEscape(oConfig["telegramBotToken"]) + '"'
    EndIf
    If oConfig:HasProperty("telegramChatId")
        cJson += ',"telegramChatId":"' + MonJsonEscape(oConfig["telegramChatId"]) + '"'
    EndIf
    If oConfig:HasProperty("portaDbaccess")
        cJson += ',"portaDbaccess":' + AllTrim(Str(oConfig["portaDbaccess"]))
    EndIf
    If oConfig:HasProperty("licenseServer")
        cJson += ',"licenseServer":{"host":"' + MonJsonEscape(oConfig["licenseServer"]["host"]) + '","port":' + AllTrim(Str(oConfig["licenseServer"]["port"])) + '}'
    EndIf

    cJson += "}"
Return cJson

User Function MonSalvarUnidadesConfig(cConfigPath, aUnidadesNovas)
    Local oConfig := MonLoadConfig(cConfigPath)

    If oConfig == Nil
        Return .F.
    EndIf
Return MemoWrite(cConfigPath, MonConfigParaJson(oConfig, aUnidadesNovas))

User Function MonGerarConfigFormHtml(aUnidades, cMensagem, lTemSenha)
    Local cHtml := "<!doctype html><html><head><meta charset='utf-8'>" + ;
        "<title>Configurar unidades - Monitor Ortobom</title>" + ;
        "<style>body{font-family:sans-serif;margin:20px;max-width:700px} " + ;
        "textarea{width:100%;height:300px;font-family:monospace;font-size:14px} " + ;
        "input[type=password]{padding:6px} button{padding:8px 16px} " + ;
        ".msg{padding:10px;margin-bottom:16px;background:#fff3cd;border:1px solid #ffc107}</style>" + ;
        "</head><body>"

    cHtml += "<h1>Configurar unidades</h1>"
    cHtml += "<p><a href='/'>&larr; voltar pro dashboard</a></p>"

    If cMensagem != ""
        cHtml += "<div class='msg'>" + cMensagem + "</div>"
    EndIf

    If !lTemSenha
        cHtml += "<p><b>Edicao desabilitada.</b> Defina a chave 'dashboardSenha' (qualquer texto serve de senha) no config.json pra habilitar.</p>"
    EndIf

    cHtml += "<p>Uma unidade por linha, formato <code>NOME HOST PORTA</code>. Exemplo: <code>ORTOSP 10.0.100.62 8090</code>.</p>"
    cHtml += "<form method='GET' action='/config/salvar'>"
    cHtml += "<textarea name='UNIDADES'>" + MonUnidadesParaTexto(aUnidades) + "</textarea><br><br>"
    cHtml += "Senha: <input type='password' name='SENHA'> "
    cHtml += "<button type='submit'" + IIF(!lTemSenha, " disabled", "") + ">Salvar</button>"
    cHtml += "</form>"
    cHtml += "<p style='color:#888;font-size:0.85em'>Nota: por limitacao do servidor HTTP embutido, o formulario usa GET em vez de POST -- a senha e o conteudo da lista aparecem na URL e no historico do navegador. Nao e um mecanismo de seguranca forte, so uma barreira contra edicao acidental.</p>"
    cHtml += "</body></html>"
Return cHtml

// oPathConfig e opcional, so pra facilitar teste (ver nota identica em
// MonRotaDashboard, monitor_dashboard.prw) -- em producao, chamado pelo
// WSRestServer com um argumento so, cai no default "config.json".
User Function MonRotaConfigForm(oParams, cPathConfig)
    Local cPath := IIF(cPathConfig == Nil, "config.json", cPathConfig)
    Local oConfig := MonLoadConfig(cPath)

    If oConfig == Nil
        Return {"__RAW_HTTP__", "text/html", "<html><body>config.json nao encontrado ou invalido.</body></html>", 500}
    EndIf
Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(MonGetUnidades(oConfig), "", oConfig:HasProperty("dashboardSenha")), 200}

User Function MonRotaConfigSalvar(oParams, cPathConfig)
    Local cPath := IIF(cPathConfig == Nil, "config.json", cPathConfig)
    Local oConfig := MonLoadConfig(cPath)
    Local cSenhaInformada
    Local cTexto
    Local oParsed

    If oConfig == Nil
        Return {"__RAW_HTTP__", "text/html", "<html><body>config.json nao encontrado ou invalido.</body></html>", 500}
    EndIf

    If !oConfig:HasProperty("dashboardSenha")
        Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(MonGetUnidades(oConfig), "Edicao desabilitada: defina 'dashboardSenha' no config.json pra habilitar.", .F.), 200}
    EndIf

    cSenhaInformada := IIF(oParams == Nil .Or. !oParams:HasProperty("SENHA"), "", oParams["SENHA"])
    cTexto          := IIF(oParams == Nil .Or. !oParams:HasProperty("UNIDADES"), "", oParams["UNIDADES"])

    If cSenhaInformada != oConfig["dashboardSenha"]
        Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(MonGetUnidades(oConfig), "Senha incorreta -- nada foi salvo.", .T.), 200}
    EndIf

    oParsed := MonTextoParaUnidades(cTexto)
    If !oParsed["OK"]
        Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(MonGetUnidades(oConfig), "Erro: " + oParsed["ERRO"] + " -- nada foi salvo.", .T.), 200}
    EndIf

    If !MonSalvarUnidadesConfig(cPath, oParsed["UNIDADES"])
        Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(MonGetUnidades(oConfig), "Erro ao gravar config.json -- nada foi salvo.", .T.), 200}
    EndIf

Return {"__RAW_HTTP__", "text/html", MonGerarConfigFormHtml(oParsed["UNIDADES"], "Salvo! " + AllTrim(Str(Len(oParsed["UNIDADES"]))) + " unidade(s). Vale a partir do proximo ciclo de checagem, sem precisar reiniciar o servico.", .T.), 200}
