#include "../src/monitor_lib.prw"

User Function MonitorLibTest()
    Local cStatePath := "test_state.json"
    Local oState

    FErase(cStatePath)
    oState := MonLoadState(cStatePath)
    ConOut("teste4b_status_novo=" + MonGetStatusAnterior(oState, "TCPSP"))

    MonSetStatus(oState, "TCPSP", "UP", 0)
    ConOut("teste5b_status_apos_set=" + MonGetStatusAnterior(oState, "TCPSP"))

    ConOut("teste6b_save=" + IIF(MonSaveState(cStatePath, oState), "SIM", "NAO"))

    oState := MonLoadState(cStatePath)
    ConOut("teste7b_status_apos_reload=" + MonGetStatusAnterior(oState, "TCPSP"))
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

    MemoWrite(cConfigPath, '{"intervaloSegundos":60,' + ;
                           '"timeoutMs":3000,"telegramBotToken":"TOKEN123",' + ;
                           '"telegramChatId":"CHAT123","unidades":' + ;
                           '[{"nome":"TCPSP","host":"127.0.0.1","porta":8090},' + ;
                           '{"nome":"TCPRJ","host":"127.0.0.1","porta":8090}]}')
    oConfig := MonLoadConfig(cConfigPath)
    ConOut("teste12_intervalo=" + Str(oConfig["intervaloSegundos"]))

    aUnidades := MonGetUnidades(oConfig)
    ConOut("teste13_qtd_unidades=" + Str(Len(aUnidades)))
    ConOut("teste14_unidade1_nome=" + aUnidades[1]["nome"])
    ConOut("teste14b_unidade1_host=" + aUnidades[1]["host"])
    ConOut("teste15_unidade2_nome=" + aUnidades[2]["nome"])
    FErase(cConfigPath)

    ConOut("teste16_config_ausente=" + IIF(MonLoadConfig("nao_existe.json") == Nil, "SIM", "NAO"))

    cConfigPath := "test_config_malformado.json"
    MemoWrite(cConfigPath, "{invalido")
    ConOut("teste17_config_malformado=" + IIF(MonLoadConfig(cConfigPath) == Nil, "SIM", "NAO"))
    FErase(cConfigPath)

    cConfigPath := "test_config_sem_unidades.json"
    MemoWrite(cConfigPath, '{"intervaloSegundos":60}')
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

    Local oState8 := JsonObject():New()
    Local cLog8   := "test_monitor_latencia.log"

    FErase(cLog8)
    MonProcessarDbaccess("TCPLAT", "127.0.0.1", 19191, 500, oState8, cLog8, "TOKEN_FAKE", "0")
    ConOut("testeLatDbaccess_registrada=" + IIF(MonGetLatenciaAnterior(oState8, "TCPLAT_DBACCESS") >= 0, "SIM", "NAO"))

    MonProcessarLicenseServer("127.0.0.1", 19191, 500, oState8, cLog8, "TOKEN_FAKE", "0")
    ConOut("testeLatLicense_registrada=" + IIF(MonGetLatenciaAnterior(oState8, "LICENSE_SERVER") >= 0, "SIM", "NAO"))
    FErase(cLog8)

    // teste45-46 (achado 1 da revisao final): latencia fracionaria (como a
    // que TimeCounter() retorna de verdade) deve ser arredondada para
    // inteiro antes de logar/gravar em state.json -- nunca com casas
    // decimais, que estourariam o PadL(8) da TUI e virariam numero
    // truncado/ilegivel na tela.
    Local oState10 := JsonObject():New()
    Local cLog10   := "test_monitor_latencia_fracionaria.log"
    Local oRes10   := JsonObject():New()

    FErase(cLog10)
    oRes10["HOST"]       := "127.0.0.1"
    oRes10["PORT"]       := 19191
    oRes10["UP"]         := .T.
    oRes10["LATENCIAMS"] := 0.5071559999999997

    MonProcessarResultado("TCPFRAC", "TCPFRAC", oRes10, oState10, cLog10, "TOKEN_FAKE", "0")
    ConOut("teste45_latencia_arredondada=" + Str(MonGetLatenciaAnterior(oState10, "TCPFRAC")))

    Local cLogTxt10 := MemoRead(cLog10)
    ConOut("teste46_log_latencia_inteira=" + IIF("latenciaMs=1" $ cLogTxt10, "SIM", "NAO"))
    ConOut("teste46b_log_sem_latencia_fracionaria=" + IIF("latenciaMs=0.5" $ cLogTxt10, "NAO", "SIM"))

    FErase(cLog10)

    // teste47-49 (achado 2 da revisao final): a latencia deve ser gravada
    // em TODO ciclo, mesmo quando o status nao muda -- MonSetStatus nao
    // pode ficar preso dentro do "If cStatusNovo != cStatusAnterior" (isso
    // so deve controlar a notificacao do Telegram).
    Local oState9 := JsonObject():New()
    Local cLog9   := "test_monitor_latencia_estavel.log"
    Local oRes9   := JsonObject():New()

    FErase(cLog9)
    oRes9["HOST"]       := "127.0.0.1"
    oRes9["PORT"]       := 19191
    oRes9["UP"]         := .T.
    oRes9["LATENCIAMS"] := 100

    MonProcessarResultado("TCPFIX", "TCPFIX", oRes9, oState9, cLog9, "TOKEN_FAKE", "0")
    ConOut("teste47_latencia_ciclo1=" + Str(MonGetLatenciaAnterior(oState9, "TCPFIX")))

    oRes9["LATENCIAMS"] := 250
    MonProcessarResultado("TCPFIX", "TCPFIX", oRes9, oState9, cLog9, "TOKEN_FAKE", "0")
    ConOut("teste48_status_ciclo2_sem_mudanca=" + MonGetStatusAnterior(oState9, "TCPFIX"))
    ConOut("teste49_latencia_ciclo2_atualizou=" + IIF(MonGetLatenciaAnterior(oState9, "TCPFIX") == 250, "SIM", "NAO"))

    FErase(cLog9)

    ConOut("MONITOR_LIB_TEST_FIM")
Return
