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
    ConOut("MONITOR_LIB_TEST_FIM")
Return
