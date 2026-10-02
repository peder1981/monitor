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
    // Aritmetica de calendario propria (ver comentario em MonColetaArquivosUltimosDias
    // sobre `Date() - Numero` devolver Numero em vez de Data no advplc --
    // issue github.com/peder1981/AdvPP/issues/8). Regressao real: sem
    // isso, /analise ficava sempre vazia em producao mesmo com dias de
    // coleta acumulados.
    Local aR

    ConOut("testeCal1_bissexto_2024=" + IIF(MonBissexto(2024), "SIM", "NAO"))
    ConOut("testeCal2_nao_bissexto_2026=" + IIF(MonBissexto(2026), "SIM", "NAO"))
    ConOut("testeCal3_seculo_nao_bissexto_2100=" + IIF(MonBissexto(2100), "SIM", "NAO"))
    ConOut("testeCal4_seculo_bissexto_2000=" + IIF(MonBissexto(2000), "SIM", "NAO"))

    aR := MonDataMenosDias(2026, 1, 1, 1)
    ConOut("testeCal5_01jan2026_menos1=" + AllTrim(Str(aR[1])) + "-" + AllTrim(Str(aR[2])) + "-" + AllTrim(Str(aR[3])))

    aR := MonDataMenosDias(2024, 3, 1, 1)
    ConOut("testeCal6_01mar2024_menos1_bissexto=" + AllTrim(Str(aR[1])) + "-" + AllTrim(Str(aR[2])) + "-" + AllTrim(Str(aR[3])))

    aR := MonDataMenosDias(2026, 10, 2, 0)
    ConOut("testeCal7_menos0_nao_muda=" + AllTrim(Str(aR[1])) + "-" + AllTrim(Str(aR[2])) + "-" + AllTrim(Str(aR[3])))

    ConOut("testeCal8_formata_com_zero=" + MonFormataDDMMYYYY(2026, 1, 2))

    // teste real do bug: antes da correcao, todo nome de arquivo virava
    // "coleta_.csv" (Date()-i sempre devolvia "" via DTOC) -- agora cada
    // nome tem 8 digitos de data (DDMMAAAA) e nenhum fica vazio.
    Local aArquivos := MonColetaArquivosUltimosDias(5)
    Local lTodosValidos := .T.
    Local i
    For i := 1 To Len(aArquivos)
        If !("coleta_" $ aArquivos[i]) .Or. Len(aArquivos[i]) != Len("coleta_DDMMAAAA.csv")
            lTodosValidos := .F.
        EndIf
    Next
    ConOut("testeCal9_qtd_arquivos=" + Str(Len(aArquivos)))
    ConOut("testeCal10_todos_arquivos_com_data_valida=" + IIF(lTodosValidos, "SIM", "NAO"))
    ConOut("testeCal11_ultimo_arquivo_eh_hoje=" + IIF(aArquivos[Len(aArquivos)] == MonColetaArquivoHoje(), "SIM", "NAO"))

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
