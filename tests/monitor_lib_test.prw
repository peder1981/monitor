#include "../src/monitor_lib.prw"

User Function MonitorLibTest()
    // teste1-4: MonCheckWebapp -- checagem HTTP com latencia, porta fixa
    // (nao vem do .ini, só o host vem). "TCPWEBOK" tem host com um
    // servidor HTTP real escutando (subido pelo harness do teste antes de
    // rodar este .prw, na porta 19191); "TCPWEBGHOST" nao existe no .ini.
    Local cIniPath := "test_units.ini"
    Local oRes

    MemoWrite(cIniPath, "[TCPWEBOK]" + Chr(13) + Chr(10) + ;
                        "Server=127.0.0.1" + Chr(13) + Chr(10))

    oRes := MonCheckWebapp("TCPWEBOK", cIniPath, 19191, 2000)
    ConOut("teste1_unidade=" + oRes["UNIDADE"])
    ConOut("teste2_host=" + oRes["HOST"])
    ConOut("teste3_port=" + Str(oRes["PORT"]))
    ConOut("teste4_up=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste5_latencia_nao_negativa=" + IIF(oRes["LATENCIAMS"] >= 0, "SIM", "NAO"))

    oRes := MonCheckWebapp("TCPWEBGHOST", cIniPath, 19191, 2000)
    ConOut("teste6_up_secao_ausente=" + IIF(oRes["UP"], "SIM", "NAO"))
    ConOut("teste7_erro_secao_ausente=" + oRes["ERRO"])

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

    MonSetStatus(oState, "TCPSP", "UP", 842)
    ConOut("testeLatencia1_valor=" + Str(MonGetLatenciaAnterior(oState, "TCPSP")))

    MonSaveState(cStatePath, oState)
    oState := MonLoadState(cStatePath)
    ConOut("testeLatencia2_valor_apos_reload=" + Str(MonGetLatenciaAnterior(oState, "TCPSP")))
    ConOut("testeLatencia3_unidade_sem_latencia=" + Str(MonGetLatenciaAnterior(oState, "TCPRJ")))

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
