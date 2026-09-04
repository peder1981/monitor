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

    ConOut("MONITOR_LIB_TEST_FIM")
Return
