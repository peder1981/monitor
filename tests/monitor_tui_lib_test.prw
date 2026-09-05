#include "../src/monitor_lib.prw"
#include "../src/monitor_tui_lib.prw"

User Function MonitorTuiLibTest()
    Local cLinha := MonTuiLinhaStatus("TCPSP", "UP", 842)
    ConOut("teste1_linha_tem_chave=" + IIF("TCPSP" $ cLinha, "SIM", "NAO"))
    ConOut("teste2_linha_tem_status=" + IIF("UP" $ cLinha, "SIM", "NAO"))
    ConOut("teste3_linha_tem_latencia=" + IIF("842" $ cLinha, "SIM", "NAO"))

    // achado 8 (revisao final): "DESCONHECIDO" (12 chars) e um status real
    // (unidade nunca checada) e nao pode ser truncado pelo PadR do campo
    // de status.
    Local cLinhaDesconhecida := MonTuiLinhaStatus("TCPSP", "DESCONHECIDO", -1)
    ConOut("teste11_linha_status_desconhecido_nao_truncado=" + IIF("DESCONHECIDO" $ cLinhaDesconhecida, "SIM", "NAO"))

    // achado 9 (revisao final): latencia -1 (sentinela de "sem dados") nao
    // pode vazar como "-1ms" pra tela -- deve virar um placeholder tipo
    // "--".
    ConOut("teste12_linha_latencia_sentinela_vira_traco=" + IIF("-1ms" $ cLinhaDesconhecida, "NAO", "SIM"))
    ConOut("teste13_linha_latencia_sentinela_tem_traco=" + IIF("--" $ cLinhaDesconhecida, "SIM", "NAO"))

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

    // achado 9 (revisao final): TCPRJ nunca teve latencia gravada (so
    // status, via MonSetStatus(..., "DOWN", 0) acima nao conta -- usamos
    // outra unidade abaixo sem nenhum MonSetStatus previo) -- a tabela
    // deve mostrar "--" e nao um "-1ms" cru.
    Local oStateVazio := JsonObject():New()
    Local cTabelaVazia := MonTuiMontarTabela(oConfig, oStateVazio)
    ConOut("teste14_tabela_sem_dados_nao_mostra_sentinela=" + IIF("-1ms" $ cTabelaVazia, "NAO", "SIM"))
    ConOut("teste15_tabela_sem_dados_mostra_traco=" + IIF("--" $ cTabelaVazia, "SIM", "NAO"))

    FErase(cConfigPath)

    Local cSaidaComProcesso := '"MonitorService.exe","1234","Console","1","10.240 K"'
    Local cSaidaSemProcesso := "INFO: No tasks are running which match the specified criteria."

    ConOut("teste8_detecta_rodando=" + IIF(MonTuiProcessoEstaRodando(cSaidaComProcesso), "SIM", "NAO"))
    ConOut("teste9_detecta_parado=" + IIF(MonTuiProcessoEstaRodando(cSaidaSemProcesso), "SIM", "NAO"))
    ConOut("teste10_detecta_vazio=" + IIF(MonTuiProcessoEstaRodando(""), "SIM", "NAO"))

    ConOut("MONITOR_TUI_LIB_TEST_FIM")
Return
