#include "../src/monitor_lib.prw"
#include "../src/monitor_dashboard.prw"

User Function MonitorDashboardTest()
    Local cPath := "test_dashboard.json"
    Local aUnidades := {}
    Local oU1 := JsonObject():New()
    Local oU2 := JsonObject():New()
    Local oServ := JsonObject():New()
    Local aServs := {}

    oServ["HOSTPORTA"] := "10.0.100.62:1236"
    oServ["STATUS"]    := "QUARENTENA"
    oServ["USUARIOS"]  := 0
    oServ["MEMORIAKB"] := 0
    oServ["CPU"]       := 0
    AAdd(aServs, oServ)

    oU1["UNIDADE"]         := "ORTOSP"
    oU1["HOST"]            := "10.0.100.62"
    oU1["PORT"]            := 8090
    oU1["UP"]              := .T.
    oU1["LATENCIAMS"]      := 42
    oU1["SESSOESATIVAS"]   := 59
    oU1["CONEXOESATIVAS"]  := 175
    oU1["SERVERS"]         := aServs
    oU1["ENDPOINT"]        := "/totvs_broker_query"

    oU2["UNIDADE"]         := "ORTORJ"
    oU2["HOST"]            := "10.0.100.53"
    oU2["PORT"]            := 8090
    oU2["UP"]              := .F.
    oU2["LATENCIAMS"]      := 0
    oU2["SESSOESATIVAS"]   := 0
    oU2["CONEXOESATIVAS"]  := 0
    oU2["SERVERS"]         := {}
    oU2["ENDPOINT"]        := "/totvs_broker_query/status"

    AAdd(aUnidades, oU1)
    AAdd(aUnidades, oU2)

    // --- MonSalvarDashboard ---
    FErase(cPath)
    ConOut("teste1_salvou=" + IIF(MonSalvarDashboard(cPath, aUnidades, {}, Nil, 45), "SIM", "NAO"))

    Local oDash := JsonObject():New()
    oDash:FromJson(MemoRead(cPath))
    ConOut("teste2_tem_atualizadoem=" + IIF(oDash["ATUALIZADOEM"] != "", "SIM", "NAO"))
    ConOut("teste3_qtd_unidades=" + Str(Len(oDash["UNIDADES"])))
    ConOut("teste4_unidade1_nome=" + oDash["UNIDADES"][1]["UNIDADE"])

    // --- MonGerarDashboardHtml ---
    Local cHtml := MonGerarDashboardHtml(oDash)
    ConOut("teste5_html_tem_ortosp=" + IIF("ORTOSP" $ cHtml, "SIM", "NAO"))
    ConOut("teste6_html_tem_ortorj=" + IIF("ORTORJ" $ cHtml, "SIM", "NAO"))
    ConOut("teste7_html_tem_up=" + IIF("UP" $ cHtml, "SIM", "NAO"))
    ConOut("teste8_html_tem_down=" + IIF("DOWN" $ cHtml, "SIM", "NAO"))
    ConOut("teste9_html_tem_server_quarentena=" + IIF("QUARENTENA" $ cHtml, "SIM", "NAO"))
    ConOut("teste10_html_sem_dbaccess_quando_vazio=" + IIF("dbaccess" $ cHtml, "NAO", "SIM"))
    ConOut("teste11_html_sem_license_quando_ausente=" + IIF("License Server" $ cHtml, "NAO", "SIM"))

    // teste11b: link pra pagina de edicao de unidades (achado do
    // operador em campo: quer editar hosts/portas pelo proprio dashboard).
    ConOut("teste11b_html_tem_link_config=" + IIF("/config" $ cHtml, "SIM", "NAO"))

    // teste11c-f (achado do operador em campo: quer clicar no dashboard
    // e abrir a pagina do broker de verdade). Link da unidade usa o
    // ENDPOINT configurado dela (inclusive o customizado da build
    // 12.1.2310, "/totvs_broker_query/status"); link do server individual
    // usa o padrao real observado nas fixtures (TOTVS_BROKER_QUERY/
    // ServerStatus/<hostporta do server>), sempre sob o host:porta da
    // UNIDADE (o broker, nao o server).
    ConOut("teste11c_link_unidade_endpoint_padrao=" + IIF("href='http://10.0.100.62:8090/totvs_broker_query'" $ cHtml, "SIM", "NAO"))
    ConOut("teste11d_link_unidade_endpoint_customizado=" + IIF("href='http://10.0.100.53:8090/totvs_broker_query/status'" $ cHtml, "SIM", "NAO"))
    ConOut("teste11e_link_server_individual=" + IIF("href='http://10.0.100.62:8090/TOTVS_BROKER_QUERY/ServerStatus/10.0.100.62:1236'" $ cHtml, "SIM", "NAO"))
    ConOut("teste11f_links_abrem_em_nova_aba=" + IIF("target='_blank'" $ cHtml, "SIM", "NAO"))

    // teste16-17: auto-refresh (achado importante da revisao final) -- a
    // pagina precisa se recarregar sozinha no intervalo configurado, via
    // <meta http-equiv='refresh'>.
    ConOut("teste16_html_tem_meta_refresh=" + IIF("http-equiv='refresh'" $ cHtml, "SIM", "NAO"))
    ConOut("teste17_html_intervalo_bate=" + IIF("content='45'" $ cHtml, "SIM", "NAO"))

    // teste18: sem intervalo informado (compatibilidade com chamada antiga
    // de 4 args), cai num default sensato em vez de gerar refresh "0" (que
    // recarregaria a pagina em loop infinito).
    Local cPathSemIntervalo := "test_dashboard_sem_intervalo.json"
    Local oDashSemIntervalo

    FErase(cPathSemIntervalo)
    MonSalvarDashboard(cPathSemIntervalo, aUnidades, {}, Nil)
    oDashSemIntervalo := JsonObject():New()
    oDashSemIntervalo:FromJson(MemoRead(cPathSemIntervalo))
    ConOut("teste18_intervalo_default_nao_e_zero=" + IIF("content='0'" $ MonGerarDashboardHtml(oDashSemIntervalo), "NAO", "SIM"))
    FErase(cPathSemIntervalo)

    // --- MonRotaDashboard: dashboard.json ausente ---
    FErase("dashboard_rota_ausente.json")
    Local aResp := MonRotaDashboard(Nil, "dashboard_rota_ausente.json")
    ConOut("teste12_sentinela=" + aResp[1])
    ConOut("teste13_content_type=" + aResp[2])
    ConOut("teste14_avisa_sem_dados=" + IIF("aguarde" $ aResp[3], "SIM", "NAO"))

    // --- MonRotaDashboard: dashboard.json presente ---
    Local aResp2 := MonRotaDashboard(Nil, cPath)
    ConOut("teste15_rota_tem_ortosp=" + IIF("ORTOSP" $ aResp2[3], "SIM", "NAO"))

    FErase(cPath)

    // teste19-20 (achado importante da revisao final): dashboard.json
    // corrompido (processo morto no meio da escrita) nao pode estourar
    // excecao nem devolver lixo pro navegador -- mesma protecao que
    // MonLoadState ja tem pra state.json.
    Local cPathCorrompido := "test_dashboard_corrompido.json"

    MemoWrite(cPathCorrompido, "{isso nao e json valido")
    Local aRespCorrompido := MonRotaDashboard(Nil, cPathCorrompido)
    ConOut("teste19_sentinela_corrompido=" + aRespCorrompido[1])
    ConOut("teste20_avisa_corrompido=" + IIF("corrompido" $ aRespCorrompido[3], "SIM", "NAO"))
    FErase(cPathCorrompido)

    // teste21-24 (achado importante da revisao final): dbaccess/license
    // preenchidos de verdade -- MonChecagemParaJson/MonChecagensParaJson
    // nunca tinham sido exercitados por nenhum teste ate aqui.
    Local cPathCompleto := "test_dashboard_completo.json"
    Local aDbaccess := {}
    Local oDbaccess1 := JsonObject():New()
    Local oLicense := JsonObject():New()

    oDbaccess1["UNIDADE"]    := "ORTOSP_DBACCESS"
    oDbaccess1["HOST"]       := "10.0.100.62"
    oDbaccess1["PORT"]       := 1234
    oDbaccess1["UP"]         := .T.
    oDbaccess1["LATENCIAMS"] := 5
    AAdd(aDbaccess, oDbaccess1)

    oLicense["UNIDADE"]    := "LICENSE_SERVER"
    oLicense["HOST"]       := "10.0.200.98"
    oLicense["PORT"]       := 5555
    oLicense["UP"]         := .F.
    oLicense["LATENCIAMS"] := 0

    MonSalvarDashboard(cPathCompleto, aUnidades, aDbaccess, oLicense, 60)

    Local oDashCompleto := JsonObject():New()
    oDashCompleto:FromJson(MemoRead(cPathCompleto))
    ConOut("teste21_dbaccess_roundtrip=" + IIF(oDashCompleto["DBACCESS"][1]["UNIDADE"] == "ORTOSP_DBACCESS", "SIM", "NAO"))
    ConOut("teste22_license_roundtrip=" + IIF(oDashCompleto["LICENSESERVER"]["HOST"] == "10.0.200.98", "SIM", "NAO"))

    Local cHtmlCompleto := MonGerarDashboardHtml(oDashCompleto)
    ConOut("teste23_html_tem_dbaccess=" + IIF("dbaccess" $ cHtmlCompleto, "SIM", "NAO"))
    ConOut("teste24_html_tem_license=" + IIF("License Server" $ cHtmlCompleto, "SIM", "NAO"))
    FErase(cPathCompleto)

    ConOut("MONITOR_DASHBOARD_TEST_FIM")
Return
