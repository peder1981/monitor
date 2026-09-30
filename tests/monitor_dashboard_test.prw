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

    oU2["UNIDADE"]         := "ORTORJ"
    oU2["HOST"]            := "10.0.100.53"
    oU2["PORT"]            := 8090
    oU2["UP"]              := .F.
    oU2["LATENCIAMS"]      := 0
    oU2["SESSOESATIVAS"]   := 0
    oU2["CONEXOESATIVAS"]  := 0
    oU2["SERVERS"]         := {}

    AAdd(aUnidades, oU1)
    AAdd(aUnidades, oU2)

    // --- MonSalvarDashboard ---
    FErase(cPath)
    ConOut("teste1_salvou=" + IIF(MonSalvarDashboard(cPath, aUnidades, {}, Nil), "SIM", "NAO"))

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

    ConOut("MONITOR_DASHBOARD_TEST_FIM")
Return
