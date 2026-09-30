#include "../src/monitor_lib.prw"
#include "../src/monitor_broker.prw"

User Function MonitorBrokerTest()
    Local cHtmlHttp := MemoRead("fixtures/broker_http_ok.html")
    Local cHtmlSC   := MemoRead("fixtures/broker_smartclient_quarentena.html")
    Local oParsed
    Local oServ

    ConOut("testeFix1_http_carregou=" + IIF(cHtmlHttp != "", "SIM", "NAO"))
    ConOut("testeFix2_smartclient_carregou=" + IIF(cHtmlSC != "", "SIM", "NAO"))

    // --- MonModoBroker ---
    ConOut("testeModo1_http=" + MonModoBroker(cHtmlHttp))
    ConOut("testeModo2_smartclient=" + MonModoBroker(cHtmlSC))
    ConOut("testeModo3_vazio=" + IIF(MonModoBroker("") == "", "SIM", "NAO"))
    ConOut("testeModo4_lixo=" + IIF(MonModoBroker("<html>pagina qualquer</html>") == "", "SIM", "NAO"))

    // --- MonSoNumero ---
    ConOut("testeNum1_simples=" + Str(MonSoNumero("59 sessões")))
    ConOut("testeNum2_milhar=" + Str(MonSoNumero("4.087.092")))
    ConOut("testeNum3_percentual=" + Str(MonSoNumero("37%")))
    ConOut("testeNum4_interrogacao=" + Str(MonSoNumero("?")))
    ConOut("testeNum5_vazio=" + Str(MonSoNumero("")))
    ConOut("testeNum6_espacos=" + Str(MonSoNumero("    25")))

    // --- MonParseBrokerHtml (fixture 1: broker HTTP saudavel, 5 servers) ---
    oParsed := MonParseBrokerHtml(cHtmlHttp)
    ConOut("teste1_valido=" + IIF(oParsed["VALIDO"], "SIM", "NAO"))
    ConOut("teste2_sessoes=" + Str(oParsed["SESSOESATIVAS"]))
    ConOut("teste3_conexoes=" + Str(oParsed["CONEXOESATIVAS"]))
    ConOut("teste4_versao_tem_numero=" + IIF("24.3.1.9" $ oParsed["VERSAO"], "SIM", "NAO"))
    ConOut("teste5_qtd_servers=" + Str(Len(oParsed["SERVERS"])))

    oServ := oParsed["SERVERS"][1]
    ConOut("teste6_server1_hostporta=" + oServ["HOSTPORTA"])
    ConOut("teste7_server1_sessoes=" + Str(oServ["SESSOES"]))
    ConOut("teste8_server1_conexoes=" + Str(oServ["CONEXOES"]))
    ConOut("teste9_server1_usuarios=" + Str(oServ["USUARIOS"]))
    ConOut("teste10_server1_threads=" + Str(oServ["THREADS"]))
    ConOut("teste11_server1_memoria=" + Str(oServ["MEMORIAKB"]))
    ConOut("teste12_server1_cpu=" + Str(oServ["CPU"]))
    ConOut("teste13_server1_pid=" + Str(oServ["PID"]))
    ConOut("teste14_server1_status=" + oServ["STATUS"])
    ConOut("teste15_server1_sem_quarentena=" + IIF(oServ["INICIOQUARENTENA"] == "", "SIM", "NAO"))

    // --- MonParseBrokerHtml (fixture 2: broker SmartClient, 14 servers, 9 em quarentena) ---
    oParsed := MonParseBrokerHtml(cHtmlSC)
    ConOut("teste16_valido=" + IIF(oParsed["VALIDO"], "SIM", "NAO"))
    ConOut("teste17_conexoes=" + Str(oParsed["CONEXOESATIVAS"]))
    ConOut("teste18_qtd_servers=" + Str(Len(oParsed["SERVERS"])))

    oServ := oParsed["SERVERS"][1] // server 1: OK
    ConOut("teste19_server1_status=" + oServ["STATUS"])
    ConOut("teste20_server1_conexoes=" + Str(oServ["CONEXOES"]))

    oServ := oParsed["SERVERS"][5] // server 5: em quarentena desde 12:34:30
    ConOut("teste21_server5_hostporta=" + oServ["HOSTPORTA"])
    ConOut("teste22_server5_status=" + oServ["STATUS"])
    ConOut("teste23_server5_inicio_quarentena=" + oServ["INICIOQUARENTENA"])
    ConOut("teste24_server5_usuarios_zerado=" + Str(oServ["USUARIOS"]))
    ConOut("teste25_server5_memoria_zerada=" + Str(oServ["MEMORIAKB"]))

    oServ := oParsed["SERVERS"][8] // server 8: volta a ser OK no meio da lista de quarentenas
    ConOut("teste26_server8_status=" + oServ["STATUS"])

    oServ := oParsed["SERVERS"][14] // server 14: ultimo, tambem em quarentena
    ConOut("teste27_server14_status=" + oServ["STATUS"])
    ConOut("teste28_server14_inicio_quarentena=" + oServ["INICIOQUARENTENA"])

    // conta quantos servers estao em quarentena na fixture 2 (esperado: 9)
    Local nQuarentena := 0
    Local i
    For i := 1 To Len(oParsed["SERVERS"])
        If oParsed["SERVERS"][i]["STATUS"] == "QUARENTENA"
            nQuarentena++
        EndIf
    Next
    ConOut("teste29_total_em_quarentena=" + Str(nQuarentena))

    ConOut("MONITOR_BROKER_TEST_FIM")
Return
