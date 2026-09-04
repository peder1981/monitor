#include "../src/monitor_lib.prw"

User Function MonitorLibTest()
    Local cIniPath := "test_units.ini"
    Local oRes

    // .ini de teste: TCPOK aponta pra uma porta que sobe (127.0.0.1:19191,
    // aberta pelo harness do teste antes de rodar este .prw), TCPDOWN
    // aponta pra uma porta que ninguém escuta, TCPGHOST não existe no .ini.
    MemoWrite(cIniPath, "[TCPOK]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                        "Port=19191" + Chr(13) + Chr(10) + ;
                        "[TCPDOWN]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                        "Port=19192" + Chr(13) + Chr(10))

    oRes := MonCheckUnidade("TCPOK", cIniPath, 1000)
    ConOut("teste1_unidade=" + oRes["UNIDADE"])
    ConOut("teste1_host=" + oRes["HOST"])
    ConOut("teste1_port=" + Str(oRes["PORT"]))
    ConOut("teste1_up=" + IIF(oRes["UP"], "SIM", "NAO"))

    oRes := MonCheckUnidade("TCPDOWN", cIniPath, 1000)
    ConOut("teste2_up=" + IIF(oRes["UP"], "SIM", "NAO"))

    oRes := MonCheckUnidade("TCPGHOST", cIniPath, 1000)
    ConOut("teste3_up=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste3_erro=" + oRes["ERRO"])

    FErase(cIniPath)

    Local cStatePath := "test_state.json"
    Local oState

    FErase(cStatePath)
    oState := MonLoadState(cStatePath)
    ConOut("teste4_status_novo=" + MonGetStatusAnterior(oState, "TCPSP"))

    MonSetStatus(oState, "TCPSP", "UP")
    ConOut("teste5_status_apos_set=" + MonGetStatusAnterior(oState, "TCPSP"))

    ConOut("teste6_save=" + IIF(MonSaveState(cStatePath, oState), "SIM", "NAO"))

    oState := MonLoadState(cStatePath)
    ConOut("teste7_status_apos_reload=" + MonGetStatusAnterior(oState, "TCPSP"))
    ConOut("teste8_status_outra_unidade=" + MonGetStatusAnterior(oState, "TCPRJ"))

    FErase(cStatePath)

    Local cLogPath := "test_monitor.log"
    Local cConfigPath := "test_config.json"
    Local oConfig
    Local aUnidades
    Local cConteudoLog

    FErase(cLogPath)
    MonLog(cLogPath, "linha um")
    MonLog(cLogPath, "linha dois")
    cConteudoLog := MemoRead(cLogPath)
    ConOut("teste9_log_tem_linha_um=" + IIF("linha um" $ cConteudoLog, "SIM", "NAO"))
    ConOut("teste10_log_tem_linha_dois=" + IIF("linha dois" $ cConteudoLog, "SIM", "NAO"))
    FErase(cLogPath)

    MemoWrite(cConfigPath, '{"iniPath":"C:\\totvs\\appserver.ini","intervaloSegundos":60,' + ;
                           '"timeoutMs":3000,"telegramBotToken":"TOKEN123",' + ;
                           '"telegramChatId":"CHAT123","unidades":["TCPSP","TCPRJ"]}')
    oConfig := MonLoadConfig(cConfigPath)
    ConOut("teste11_inipath=" + oConfig["iniPath"])
    ConOut("teste12_intervalo=" + Str(oConfig["intervaloSegundos"]))

    aUnidades := MonGetUnidades(oConfig)
    ConOut("teste13_qtd_unidades=" + Str(Len(aUnidades)))
    ConOut("teste14_unidade1=" + aUnidades[1])
    ConOut("teste15_unidade2=" + aUnidades[2])
    FErase(cConfigPath)

    ConOut("teste16_config_ausente=" + IIF(MonLoadConfig("nao_existe.json") == Nil, "SIM", "NAO"))

    cConfigPath := "test_config_malformado.json"
    MemoWrite(cConfigPath, "{invalido")
    ConOut("teste17_config_malformado=" + IIF(MonLoadConfig(cConfigPath) == Nil, "SIM", "NAO"))
    FErase(cConfigPath)

    cConfigPath := "test_config_sem_unidades.json"
    MemoWrite(cConfigPath, '{"iniPath":"C:\\totvs\\appserver.ini","intervaloSegundos":60}')
    oConfig := MonLoadConfig(cConfigPath)
    aUnidades := MonGetUnidades(oConfig)
    ConOut("teste18_unidades_chave_ausente=" + IIF(Len(aUnidades) == 0, "SIM", "NAO"))
    FErase(cConfigPath)

    Local cMsgDown := MonMontarMensagem("TCPSP", "10.0.200.62", 4000, "DOWN")
    Local cMsgUp   := MonMontarMensagem("TCPSP", "10.0.200.62", 4000, "UP")
    ConOut("teste19_msg_down=" + cMsgDown)
    ConOut("teste20_msg_up=" + cMsgUp)
    ConOut("teste21_msg_down_tem_unidade=" + IIF("TCPSP" $ cMsgDown, "SIM", "NAO"))
    ConOut("teste22_msg_down_tem_host_porta=" + IIF("10.0.200.62:4000" $ cMsgDown, "SIM", "NAO"))

    Local cTokenTeste := GetEnv("MONITOR_TEST_TELEGRAM_TOKEN")
    Local cChatTeste  := GetEnv("MONITOR_TEST_TELEGRAM_CHAT")
    If cTokenTeste == "" .Or. cTokenTeste == "Nil"
        ConOut("teste23_telegram=skip_sem_token")
    Else
        ConOut("teste23_telegram=" + IIF(MonNotificarTelegram(cTokenTeste, cChatTeste, "teste automatizado do monitor"), "SIM", "NAO"))
    EndIf

    Local cIni2      := "test_units2.ini"
    Local cLog2      := "test_monitor2.log"
    Local oState2    := JsonObject():New()
    Local cTokenFake := "TOKEN_INVALIDO_DE_PROPOSITO"
    Local cChatFake  := "0"
    Local cLogTxt

    MemoWrite(cIni2, "[TCPX]" + Chr(13) + Chr(10) + ;
                     "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                     "Port=19193" + Chr(13) + Chr(10))
    FErase(cLog2)

    // 1ª passagem: unidade está down (nada escutando na 19193), estado
    // anterior é DESCONHECIDO -> muda pra DOWN -> deve logar e tentar notificar.
    MonProcessarUnidade("TCPX", cIni2, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("teste24_status_apos_1a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))

    // 2ª passagem: continua down, estado anterior já é DOWN -> não deve
    // gerar uma segunda tentativa de notificação (não dá pra observar a
    // notificação em si sem rede, mas o estado deve permanecer DOWN e
    // o log deve ganhar uma linha nova mesmo sem alerta).
    cLogTxt := MemoRead(cLog2)
    MonProcessarUnidade("TCPX", cIni2, 500, oState2, cLog2, cTokenFake, cChatFake)
    ConOut("teste25_status_apos_2a_passagem=" + MonGetStatusAnterior(oState2, "TCPX"))
    ConOut("teste26_log_cresceu=" + IIF(Len(MemoRead(cLog2)) > Len(cLogTxt), "SIM", "NAO"))

    FErase(cIni2)
    FErase(cLog2)

    // teste27-30: unidade com secao ausente no .ini nao deve virar DOWN --
    // MonProcessarUnidade deve logar "sem_dados" e sair sem tocar no estado
    // nem tentar notificar (fixing finding 1 da revisao final).
    Local cIni3     := "test_units3.ini"
    Local cLog3     := "test_monitor3.log"
    Local oState3   := JsonObject():New()
    Local cLogTxt3

    MemoWrite(cIni3, "[TCPOK]" + Chr(13) + Chr(10) + ;
                     "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                     "Port=19191" + Chr(13) + Chr(10))
    FErase(cLog3)

    MonProcessarUnidade("TCPGHOST", cIni3, 500, oState3, cLog3, cTokenFake, cChatFake)
    ConOut("teste27_status_permanece_desconhecido=" + MonGetStatusAnterior(oState3, "TCPGHOST"))

    cLogTxt3 := MemoRead(cLog3)
    ConOut("teste28_log_tem_sem_dados=" + IIF("sem_dados" $ cLogTxt3, "SIM", "NAO"))
    ConOut("teste29_log_tem_erro=" + IIF("secao_nao_encontrada_no_ini" $ cLogTxt3, "SIM", "NAO"))
    ConOut("teste30_nao_tentou_notificar=" + IIF("falha ao notificar telegram" $ cLogTxt3, "NAO", "SIM"))

    FErase(cIni3)
    FErase(cLog3)

    // teste31-33: primeira passagem com unidade ja saudavel (DESCONHECIDO ->
    // UP) nao deve disparar o "[OK] ... voltou" espurio (fixing finding 6),
    // mas deve gravar o estado normalmente. Como nao da pra observar a rede
    // diretamente, usamos o mesmo truque de teste24-26: com token invalido,
    // se a notificacao fosse tentada o log ganharia a linha de falha.
    Local cIni4   := "test_units4.ini"
    Local cLog4   := "test_monitor4.log"
    Local oState4 := JsonObject():New()
    Local cLogTxt4

    MemoWrite(cIni4, "[TCPUP]" + Chr(13) + Chr(10) + ;
                     "Server=127.0.0.1" + Chr(13) + Chr(10) + ;
                     "Port=19191" + Chr(13) + Chr(10))
    FErase(cLog4)

    MonProcessarUnidade("TCPUP", cIni4, 500, oState4, cLog4, cTokenFake, cChatFake)
    ConOut("teste31_status_apos_1a_passagem=" + MonGetStatusAnterior(oState4, "TCPUP"))

    cLogTxt4 := MemoRead(cLog4)
    ConOut("teste32_nao_tentou_notificar_ok_desconhecido=" + IIF("falha ao notificar telegram" $ cLogTxt4, "NAO", "SIM"))

    // 2a passagem: continua UP, nada muda -> tambem sem notificacao.
    MonProcessarUnidade("TCPUP", cIni4, 500, oState4, cLog4, cTokenFake, cChatFake)
    ConOut("teste33_status_apos_2a_passagem=" + MonGetStatusAnterior(oState4, "TCPUP"))

    FErase(cIni4)
    FErase(cLog4)

    // teste34: MonGetUnidades deve ignorar "unidades" quando nao for array
    // (ex: erro de digitacao no config.json colocando uma string solta),
    // retornando lista vazia em vez de corromper o loop chamador (finding 10).
    Local cConfigPath5 := "test_config_unidades_string.json"
    Local oConfig5
    Local aUnidades5

    MemoWrite(cConfigPath5, '{"iniPath":"C:\\totvs\\appserver.ini","intervaloSegundos":60,"unidades":"TCPSP"}')
    oConfig5  := MonLoadConfig(cConfigPath5)
    aUnidades5 := MonGetUnidades(oConfig5)
    ConOut("teste34_unidades_nao_array_retorna_vazio=" + IIF(Len(aUnidades5) == 0, "SIM", "NAO"))
    FErase(cConfigPath5)

    // teste35-36: MonPingServico -- checagem TCP direta (host/porta prontos,
    // sem lookup em .ini), usada por dbaccess e license server.
    Local oResServ

    oResServ := MonPingServico("TESTE_SERVICO", "127.0.0.1", 19191, 1000)
    ConOut("teste35_servico_unidade=" + oResServ["UNIDADE"])
    ConOut("teste35_servico_up=" + IIF(oResServ["UP"], "SIM", "NAO"))

    oResServ := MonPingServico("TESTE_SERVICO", "127.0.0.1", 19194, 500)
    ConOut("teste36_servico_down=" + IIF(oResServ["UP"], "SIM", "NAO"))

    // teste37-39: MonProcessarDbaccess -- reaproveita host do appserver da
    // unidade, porta de dbaccess vem do config; chave de estado
    // "<UNIDADE>_DBACCESS"; primeira passagem down nao notifica "voltou"
    // (nao ha "voltou" na primeira vez), mas registra estado.
    Local oState6 := JsonObject():New()
    Local cLog6   := "test_monitor_dbaccess.log"

    FErase(cLog6)
    MonProcessarDbaccess("TCPSP", "127.0.0.1", 19195, 500, oState6, cLog6, "TOKEN_FAKE", "0")
    ConOut("teste37_dbaccess_status=" + MonGetStatusAnterior(oState6, "TCPSP_DBACCESS"))

    Local cLogTxt6 := MemoRead(cLog6)
    ConOut("teste38_dbaccess_log_tem_rotulo=" + IIF("TCPSP_DBACCESS" $ cLogTxt6, "SIM", "NAO"))

    // unidade "irma" (mesmo host, dbaccess up) nao deve mexer no estado da TCPSP
    MonProcessarDbaccess("TCPRJ", "127.0.0.1", 19191, 500, oState6, cLog6, "TOKEN_FAKE", "0")
    ConOut("teste39_dbaccess_unidades_independentes=" + MonGetStatusAnterior(oState6, "TCPRJ_DBACCESS") + "/" + MonGetStatusAnterior(oState6, "TCPSP_DBACCESS"))

    FErase(cLog6)

    // teste40-41: MonProcessarLicenseServer -- checado uma vez, chave de
    // estado fixa "LICENSE_SERVER", independente de qualquer unidade.
    Local oState7 := JsonObject():New()
    Local cLog7   := "test_monitor_license.log"

    FErase(cLog7)
    MonProcessarLicenseServer("127.0.0.1", 19191, 500, oState7, cLog7, "TOKEN_FAKE", "0")
    ConOut("teste40_license_status=" + MonGetStatusAnterior(oState7, "LICENSE_SERVER"))

    Local cLogTxt7 := MemoRead(cLog7)
    ConOut("teste41_license_log_tem_rotulo=" + IIF("LICENSE_SERVER" $ cLogTxt7, "SIM", "NAO"))

    FErase(cLog7)

    ConOut("MONITOR_LIB_TEST_FIM")
Return
