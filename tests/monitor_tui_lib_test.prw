#include "../src/monitor_lib.prw"
#include "../src/monitor_tui_lib.prw"

User Function MonitorTuiLibTest()
    Local cLinha := MonTuiLinhaStatus("TCPSP", "UP", 842)
    ConOut("teste1_linha_tem_chave=" + IIF("TCPSP" $ cLinha, "SIM", "NAO"))
    ConOut("teste2_linha_tem_status=" + IIF("UP" $ cLinha, "SIM", "NAO"))
    ConOut("teste3_linha_tem_latencia=" + IIF("842" $ cLinha, "SIM", "NAO"))

    Local cConfigPath := "test_tui_config.json"
    Local oConfig
    Local oState := JsonObject():New()
    Local cTabela

    MemoWrite(cConfigPath, '{"iniPath":"x.ini","intervaloSegundos":60,"timeoutMs":3000,' + ;
                           '"portaWebapp":8090,"unidades":["TCPSP","TCPRJ"],' + ;
                           '"portaDbaccess":1234,"licenseServer":{"host":"10.0.0.1","port":5555}}')
    oConfig := MonLoadConfig(cConfigPath)

    MonSetStatus(oState, "TCPSP", "UP", 100)
    MonSetStatus(oState, "TCPSP_DBACCESS", "UP", 50)
    MonSetStatus(oState, "TCPRJ", "DOWN", 0)
    MonSetStatus(oState, "LICENSE_SERVER", "UP", 30)

    cTabela := MonTuiMontarTabela(oConfig, oState)
    ConOut("teste4_tabela_tem_tcpsp=" + IIF("TCPSP" $ cTabela, "SIM", "NAO"))
    ConOut("teste5_tabela_tem_dbaccess=" + IIF("TCPSP_DBACCESS" $ cTabela, "SIM", "NAO"))
    ConOut("teste6_tabela_tem_tcprj_down=" + IIF("TCPRJ" $ cTabela .And. "DOWN" $ cTabela, "SIM", "NAO"))
    ConOut("teste7_tabela_tem_license=" + IIF("LICENSE_SERVER" $ cTabela, "SIM", "NAO"))

    FErase(cConfigPath)

    Local cSaidaComProcesso := '"MonitorService.exe","1234","Console","1","10.240 K"'
    Local cSaidaSemProcesso := "INFO: No tasks are running which match the specified criteria."

    ConOut("teste8_detecta_rodando=" + IIF(MonTuiProcessoEstaRodando(cSaidaComProcesso), "SIM", "NAO"))
    ConOut("teste9_detecta_parado=" + IIF(MonTuiProcessoEstaRodando(cSaidaSemProcesso), "SIM", "NAO"))
    ConOut("teste10_detecta_vazio=" + IIF(MonTuiProcessoEstaRodando(""), "SIM", "NAO"))

    ConOut("MONITOR_TUI_LIB_TEST_FIM")
Return
