#include "../src/monitor_lib.prw"
#include "../src/monitor_coleta.prw"

Static Function MonTesteServ(cHostPorta, cStatus, nUsuarios, nMemKb, nCpu)
    Local oS := JsonObject():New()
    oS["HOSTPORTA"] := cHostPorta
    oS["STATUS"]    := cStatus
    oS["USUARIOS"]  := nUsuarios
    oS["MEMORIAKB"] := nMemKb
    oS["CPU"]       := nCpu
Return oS

Static Function MonTesteUnidade(cNome, aServers)
    Local oU := JsonObject():New()
    oU["UNIDADE"] := cNome
    oU["SERVERS"] := aServers
Return oU

User Function MonitorColetaTest()
    Local cArquivo := "test_coleta.csv"
    Local aRes1
    Local aRes2
    Local cConteudo
    Local aLinhas

    FErase(cArquivo)

    // teste1: primeira amostra cria arquivo com cabecalho + 2 linhas (2 servers)
    aRes1 := {MonTesteUnidade("TCPSP", {MonTesteServ("10.0.0.1:1000", "OK", 10, 204800, 5), ;
                                          MonTesteServ("10.0.0.1:1001", "QUARENTENA", 3, 51200, 90)})}
    ConOut("teste1_grava=" + IIF(MonColetarAmostra(cArquivo, aRes1), "SIM", "NAO"))
    cConteudo := MemoRead(cArquivo)
    ConOut("teste2_tem_cabecalho=" + IIF("ts;unidade;host_porta;status;usuarios;mem_kb;cpu_host" $ cConteudo, "SIM", "NAO"))
    ConOut("teste3_tem_server_ok=" + IIF("10.0.0.1:1000;OK;10;204800;5" $ cConteudo, "SIM", "NAO"))
    ConOut("teste4_tem_server_quarentena=" + IIF("10.0.0.1:1001;QUARENTENA;3;51200;90" $ cConteudo, "SIM", "NAO"))

    // teste5: segunda amostra faz append, sem repetir cabecalho
    aRes2 := {MonTesteUnidade("TCPSP", {MonTesteServ("10.0.0.1:1000", "OK", 20, 300000, 8)})}
    MonColetarAmostra(cArquivo, aRes2)
    cConteudo := MemoRead(cArquivo)
    ConOut("teste5_cabecalho_unico=" + IIF(Len(StrTokArr(cConteudo, "ts;unidade")) == 2, "SIM", "NAO"))
    ConOut("teste6_tem_segunda_amostra=" + IIF("10.0.0.1:1000;OK;20;300000;8" $ cConteudo, "SIM", "NAO"))

    // teste7: amostra sem servers nao grava nada (sem quebrar)
    ConOut("teste7_amostra_vazia=" + IIF(MonColetarAmostra(cArquivo, {MonTesteUnidade("TCPSP", {})}), "SIM", "NAO"))

    FErase(cArquivo)

    // --- analise ---
    Local cArqAnalise := "test_coleta_analise.csv"
    Local cConteudoAnalise := "ts;unidade;host_porta;status;usuarios;mem_kb;cpu_host" + Chr(13) + Chr(10) + ;
        "01/10/2026 09:00:00;TCPSP;10.0.0.1:1000;OK;10;204800;5" + Chr(13) + Chr(10) + ;
        "01/10/2026 09:00:00;TCPSP;10.0.0.1:1001;DESABILITADO;99;999999;99" + Chr(13) + Chr(10) + ; // deve ser ignorada (status != OK)
        "01/10/2026 10:00:00;TCPSP;10.0.0.1:1000;OK;20;307200;8" + Chr(13) + Chr(10) + ;
        "01/10/2026 20:00:00;TCPSP;10.0.0.1:1000;OK;5;102400;2" + Chr(13) + Chr(10)

    FErase(cArqAnalise)
    MemoWrite(cArqAnalise, cConteudoAnalise)

    aLinhas := MonColetaLer({cArqAnalise})
    ConOut("teste8_linhas_lidas=" + Str(Len(aLinhas)))  // 3 (desabilitado filtrado)
    ConOut("teste9_faixa_0800=" + MonFaixaHorario(9))
    ConOut("teste10_faixa_1218=" + MonFaixaHorario(17))
    ConOut("teste11_faixa_1824=" + MonFaixaHorario(20))

    Local aPicos := MonAnalisePicos(aLinhas)
    ConOut("teste12_qtd_faixas=" + Str(Len(aPicos)))  // 3 faixas distintas (08-12, 12-18 nao, 18-24)

    Local aMem := MonAnaliseMemoria(aLinhas)
    ConOut("teste13_qtd_unidades_mem=" + Str(Len(aMem)))
    If Len(aMem) > 0
        // 3 pontos: (10,200),(20,300),(5,100) -- correlacao perfeita: m=10, b=100
        ConOut("teste14_base_mb=" + AllTrim(Str(Round(aMem[1]["BASE_MB"], 1))))
        ConOut("teste15_mb_por_usuario=" + AllTrim(Str(Round(aMem[1]["MB_POR_USUARIO"], 1))))
    EndIf

    // teste16: MonGerarAnaliseHtml nao pode quebrar (ja pegou regressao real
    // de link: MonCssBase/MonBadge vivem em monitor_lib.prw e precisam estar
    // incluidos por quem gera a pagina).
    Local cHtmlAnalise := MonGerarAnaliseHtml(aPicos, aMem, 30)
    ConOut("teste16_html_tem_titulo=" + IIF("Analise historica" $ cHtmlAnalise, "SIM", "NAO"))
    ConOut("teste17_html_tem_unidade=" + IIF("TCPSP" $ cHtmlAnalise, "SIM", "NAO"))

    FErase(cArqAnalise)
    ConOut("MONITOR_COLETA_TEST_FIM")
Return Nil
