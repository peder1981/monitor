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

    // --- MonMontarMensagemServer ---
    Local cMsgQ := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "QUARENTENA", "12:34:30", "")
    Local cMsgO := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "OK", "", "")
    Local cMsgM := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "QUARENTENA", "12:34:30", "falha de comunicacao")

    ConOut("testeMsg1_quarentena_tem_unidade=" + IIF("ORTOSP" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg2_quarentena_tem_hostporta=" + IIF("10.0.100.62:1236" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg3_quarentena_tem_horario=" + IIF("12:34:30" $ cMsgQ, "SIM", "NAO"))
    ConOut("testeMsg4_ok_diz_voltou=" + IIF("voltou ao normal" $ cMsgO, "SIM", "NAO"))
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

    // testeCheck3b (achado importante da revisao final): testeCheck3
    // sozinho nao provava "respondeu 200 mas nao e o broker" -- se
    // alguem esquecer de subir o listener da 19191, o teste continuava
    // SIM do mesmo jeito (UP=NAO por falta de resposta, nao por conteudo
    // errado). Confirma tambem que o status HTTP foi mesmo 200.
    MonCheckBroker("TESTEBROKER", "127.0.0.1", 19191, 2000)
    ConOut("testeCheck3b_respondeu_200_de_verdade=" + IIF(FWHttpStatus() == 200, "SIM", "NAO"))

    // testeRobustez1-3 (achado importante da revisao final): <td> com
    // atributos (ex: <td class='inQuarantine'>) e conteudo com tag
    // aninhada (ex: tooltip em <span>) nao podem confundir o parser a
    // ponto de esconder uma quarentena real como "OK" em silencio.
    // SINTETICO -- nenhuma fixture real de quarentena na variante "para
    // HTTP" foi observada ainda (so a variante SmartClient, ver
    // tests/fixtures/broker_smartclient_quarentena.html); isso so
    // garante que o parser degrada com seguranca (nunca finge OK) se o
    // markup real vier assim, nao que o formato exato esteja confirmado.
    Local cLinhaSintetica := "<tr><td class='x'>(1) <a href=" + Chr(34) + ;
        "/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.99:1236" + Chr(34) + ;
        ">10.0.100.99:1236</a></td><td>5</td><td>8</td>" + ;
        "<td class='inQuarantine'>12:00:00<span class='tooltiptext'>motivo aqui</span></td>" + ;
        "<td>-</td><td>10</td><td>20</td><td>1.000</td><td>10%</td>" + ;
        "<td>2026/09/30 00:00:00</td><td>1234</td></tr>"
    Local oServSintetico := MonExtrairLinhaServer(cLinhaSintetica, "HTTP")

    ConOut("testeRobustez1_hostporta=" + oServSintetico["HOSTPORTA"])
    ConOut("testeRobustez2_conexoes=" + Str(oServSintetico["CONEXOES"]))
    ConOut("testeRobustez3_nao_finge_ok_com_atributo=" + IIF(oServSintetico["STATUS"] == "OK", "NAO", "SIM"))

    // achado pos-deploy real: o broker devolve JSON (nao HTML) quando o
    // client nao e um navegador -- e o caso do proprio monitor. Fixture
    // real colada pelo operador em campo (unidade ORTOSP, broker
    // 24.3.1.9, 5 servers, todos OK).
    Local cJsonReal := MemoRead("fixtures/broker_json_real.json")
    Local oParsedJson

    ConOut("testeFix3_json_carregou=" + IIF(cJsonReal != "", "SIM", "NAO"))

    oParsedJson := MonParseBrokerJson(cJsonReal)
    ConOut("testeJson1_valido=" + IIF(oParsedJson["VALIDO"], "SIM", "NAO"))
    ConOut("testeJson2_sessoes=" + Str(oParsedJson["SESSOESATIVAS"]))
    ConOut("testeJson3_conexoes=" + Str(oParsedJson["CONEXOESATIVAS"]))
    ConOut("testeJson4_versao=" + oParsedJson["VERSAO"])
    ConOut("testeJson5_qtd_servers=" + Str(Len(oParsedJson["SERVERS"])))

    Local oServJson := oParsedJson["SERVERS"][1]
    ConOut("testeJson6_server1_hostporta=" + oServJson["HOSTPORTA"])
    ConOut("testeJson7_server1_usuarios=" + Str(oServJson["USUARIOS"]))
    ConOut("testeJson8_server1_memoria=" + Str(oServJson["MEMORIAKB"]))
    ConOut("testeJson9_server1_status=" + oServJson["STATUS"])

    // JSON invalido/vazio nao pode estourar excecao
    ConOut("testeJson10_vazio_nao_valido=" + IIF(MonParseBrokerJson("")["VALIDO"], "NAO", "SIM"))
    ConOut("testeJson11_lixo_nao_valido=" + IIF(MonParseBrokerJson("{isso nao e json valido")["VALIDO"], "NAO", "SIM"))
    ConOut("testeJson12_sem_servers_nao_valido=" + IIF(MonParseBrokerJson('{"foo":"bar"}')["VALIDO"], "NAO", "SIM"))

    // quarentena/desabilitado via booleano -- SINTETICO (a fixture real
    // colada pelo operador nao tinha nenhum server em quarentena/
    // desabilitado no momento da captura), mas o campo "inquarantine"/
    // "disabled" e booleano de verdade no payload real, diferente do
    // HTML (onde so dava pra inferir por texto de coluna).
    Local cJsonQuarentena := '{"version":"1.0","total":{"sessions":1,"connections":1},"servers":[' + ;
        '{"server":"10.0.100.99:1236","connections":0,"sessions":0,"users":0,"threads":0,' + ;
        '"memory":0,"cpu":0,"uptime":"-","pid":0,"inquarantine":true,' + ;
        '"quarantine_entry_time":"17:00:00","disabled":false,"disabled_entry_time":"-",' + ;
        '"disabled_reasons":""}]}'
    Local oParsedQ := MonParseBrokerJson(cJsonQuarentena)
    Local oServQ2 := oParsedQ["SERVERS"][1]
    ConOut("testeJsonQ1_status=" + oServQ2["STATUS"])
    ConOut("testeJsonQ2_inicio=" + oServQ2["INICIOQUARENTENA"])

    Local cJsonDesabilitado := '{"version":"1.0","total":{"sessions":1,"connections":1},"servers":[' + ;
        '{"server":"10.0.100.99:1237","connections":0,"sessions":0,"users":0,"threads":0,' + ;
        '"memory":0,"cpu":0,"uptime":"-","pid":0,"inquarantine":false,' + ;
        '"quarantine_entry_time":"-","disabled":true,"disabled_entry_time":"18:00:00",' + ;
        '"disabled_reasons":"falha de rede"}]}'
    Local oParsedD := MonParseBrokerJson(cJsonDesabilitado)
    Local oServD := oParsedD["SERVERS"][1]
    ConOut("testeJsonD1_status=" + oServD["STATUS"])
    ConOut("testeJsonD2_inicio=" + oServD["INICIOQUARENTENA"])
    ConOut("testeJsonD3_motivo=" + oServD["MOTIVO"])

    // --- MonParseBrokerResposta: dispatcher JSON/HTML ---
    ConOut("testeResp1_json_valido=" + IIF(MonParseBrokerResposta(cJsonReal)["VALIDO"], "SIM", "NAO"))
    ConOut("testeResp2_html_http_ainda_valido=" + IIF(MonParseBrokerResposta(cHtmlHttp)["VALIDO"], "SIM", "NAO"))
    ConOut("testeResp3_html_smartclient_ainda_valido=" + IIF(MonParseBrokerResposta(cHtmlSC)["VALIDO"], "SIM", "NAO"))
    ConOut("testeResp4_lixo_invalido=" + IIF(MonParseBrokerResposta("nada disso")["VALIDO"], "NAO", "SIM"))

    // --- MonMontarMensagemServer / MonProcessarServidorBroker: estado DESABILITADO ---
    Local cMsgD := MonMontarMensagemServer("ORTOSP", "10.0.100.62:1236", "DESABILITADO", "18:00:00", "falha de rede")
    ConOut("testeMsgD1_tem_desabilitado=" + IIF("desabilitado" $ cMsgD, "SIM", "NAO"))
    ConOut("testeMsgD2_tem_motivo=" + IIF("falha de rede" $ cMsgD, "SIM", "NAO"))

    Local oState5 := JsonObject():New()
    Local cLog5   := "test_monitor_desabilitado.log"
    Local oServDesab := JsonObject():New()

    oServDesab["HOSTPORTA"]        := "10.0.100.62:1236"
    oServDesab["STATUS"]           := "DESABILITADO"
    oServDesab["INICIOQUARENTENA"] := "18:00:00"
    oServDesab["MOTIVO"]           := "falha de rede"

    FErase(cLog5)
    // primeira vez ja desabilitado (DESCONHECIDO -> DESABILITADO) deve notificar,
    // mesma regra ja usada pra QUARENTENA/DOWN (primeira observacao ruim alerta).
    MonProcessarServidorBroker("ORTOSP", oServDesab, oState5, cLog5, "TOKEN_FAKE", "0")
    ConOut("testeServD1_status=" + MonGetStatusAnterior(oState5, "ORTOSP_SERVER_10.0.100.62:1236"))
    ConOut("testeServD2_notificou=" + IIF("falha ao notificar telegram" $ MemoRead(cLog5), "SIM", "NAO"))
    FErase(cLog5)

    ConOut("MONITOR_BROKER_TEST_FIM")
Return
