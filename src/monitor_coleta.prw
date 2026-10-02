#include "monitor_lib.prw"

// Coleta historica (CSV) -- substitui nativamente o coletor Python em
// anexo: uma linha por server por amostra, append-only, um arquivo por
// dia. Serve de base para decisao de capacidade (pico por faixa/dia da
// semana, memoria base + incremento por usuario via regressao linear --
// ver MonAnaliseMemoria).
//
// ponytail: arquivo direto na raiz do projeto (sem subpasta "coleta/"),
// evita depender de MakeDir (nao usado em nenhum outro lugar do
// monitor). Se a lista de arquivos crescer demais, mover para subpasta
// vira so trocar MonColetaArquivo.

User Function MonColetaArquivo(cData)
Return "coleta_" + StrTran(cData, "/", "") + ".csv"

User Function MonColetaArquivoHoje()
Return MonColetaArquivo(DTOC(Date()))

// --- Aritmetica de calendario propria (sem usar Data-Numero) ---
//
// Achado real em producao: "Analise historica" sempre vazia mesmo com
// coleta rodando ha dias. Causa raiz: o operador `Data - Numero` do
// advplc devolve Numero (nao Data) -- `DTOC(Date() - 1)` vira "" porque
// DTOC so sabe formatar Data de verdade. `MonColetaArquivosUltimosDias`
// usava exatamente esse operador pra montar os nomes dos arquivos dos
// ultimos N dias, entao TODOS os nomes (inclusive o de hoje, via
// `Date() - 0`) viravam "coleta_.csv" -- um arquivo que nunca existe.
// Issue aberta no AdvPP: https://github.com/peder1981/AdvPP/issues/8
// (a mesma raiz de bug reportada antes pro `AEval`/closure).
//
// Workaround: nunca usar `Date() +/- Numero`. Year()/Month()/Day() leem
// campos de uma Data sem problema (nao passam pelo operador quebrado),
// entao a subtracao de dias e feita aqui em cima de inteiros puros,
// com regra de bissexto e fim de mes explicitas -- sem Julian Day (a
// primeira tentativa, de cabeca, saiu errada; isto aqui foi validado
// contra 8 casos, incluindo bissexto e virada de ano/seculo).
User Function MonBissexto(nAno)
Return (nAno % 4 == 0 .And. nAno % 100 != 0) .Or. nAno % 400 == 0

User Function MonUltimoDiaMes(nAno, nMes)
    Local aDias := {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}

    If nMes == 2 .And. MonBissexto(nAno)
        Return 29
    EndIf
Return aDias[nMes]

User Function MonDiaAnterior(nAno, nMes, nDia)
    Local nMesAnt
    Local nAnoAnt

    If nDia > 1
        Return {nAno, nMes, nDia - 1}
    EndIf

    nMesAnt := nMes - 1
    nAnoAnt := nAno
    If nMesAnt < 1
        nMesAnt := 12
        nAnoAnt := nAno - 1
    EndIf
Return {nAnoAnt, nMesAnt, MonUltimoDiaMes(nAnoAnt, nMesAnt)}

User Function MonDataMenosDias(nAno, nMes, nDia, nDiasAtras)
    Local aData := {nAno, nMes, nDia}
    Local i

    For i := 1 To nDiasAtras
        aData := MonDiaAnterior(aData[1], aData[2], aData[3])
    Next
Return aData

User Function MonFormataDDMMYYYY(nAno, nMes, nDia)
Return PadL(AllTrim(Str(nDia)), 2, "0") + "/" + PadL(AllTrim(Str(nMes)), 2, "0") + "/" + AllTrim(Str(nAno))

// Nomes dos arquivos dos ultimos nDias (hoje incluso), do mais antigo
// pro mais recente -- usado pela analise em vez de listar diretorio
// (nativa de listagem de arquivos nao disponivel no AdvPP). Arquivo de
// um dia sem coleta simplesmente nao existe -- MonColetaLer ja trata
// MemoRead("") como "sem linhas" sem erro.
User Function MonColetaArquivosUltimosDias(nDias)
    Local aArquivos := {}
    Local nAnoHoje := Year(Date())
    Local nMesHoje := Month(Date())
    Local nDiaHoje := Day(Date())
    Local aData
    Local i

    For i := nDias - 1 To 0 Step -1
        aData := MonDataMenosDias(nAnoHoje, nMesHoje, nDiaHoje, i)
        AAdd(aArquivos, MonColetaArquivo(MonFormataDDMMYYYY(aData[1], aData[2], aData[3])))
    Next
Return aArquivos

User Function MonColetaCsvEscape(xVal)
    If ValType(xVal) == "C"
        Return StrTran(xVal, ";", ",")
    EndIf
Return AllTrim(Str(xVal))

User Function MonColetaLinhaServer(cTs, cUnidade, oServ)
Return cTs + ";" + MonColetaCsvEscape(cUnidade) + ";" + MonColetaCsvEscape(oServ["HOSTPORTA"]) + ";" + ;
    MonColetaCsvEscape(oServ["STATUS"]) + ";" + MonColetaCsvEscape(oServ["USUARIOS"]) + ";" + ;
    MonColetaCsvEscape(oServ["MEMORIAKB"]) + ";" + MonColetaCsvEscape(oServ["CPU"])

// Uma amostra = um ciclo do loop principal (aResUnidades inteiro). Grava
// uma linha por server de cada unidade -- mesma granularidade do
// coletor Python original (ts;unidade;host_porta;status;usuarios;
// mem_kb;cpu_host).
User Function MonColetarAmostra(cArquivo, aResUnidades)
    Local cTs := DTOC(Date()) + " " + Time()
    Local cConteudo := ""
    Local lNovo := (MemoRead(cArquivo) == "")
    Local nH
    Local i
    Local j
    Local oU

    For i := 1 To Len(aResUnidades)
        oU := aResUnidades[i]
        For j := 1 To Len(oU["SERVERS"])
            cConteudo += MonColetaLinhaServer(cTs, oU["UNIDADE"], oU["SERVERS"][j]) + Chr(13) + Chr(10)
        Next
    Next

    If cConteudo == ""
        Return .F.
    EndIf

    nH := FOpen(cArquivo, 1)
    If nH < 0
        nH := FCreate(cArquivo)
        If nH >= 0 .And. lNovo
            FWrite(nH, "ts;unidade;host_porta;status;usuarios;mem_kb;cpu_host" + Chr(13) + Chr(10))
        EndIf
    EndIf
    If nH < 0
        Return .F.
    EndIf
    FSeek(nH, 0, 2)
    FWrite(nH, cConteudo)
    FClose(nH)
Return .T.

// --- Analise: picos por faixa de horario + regressao linear de memoria ---
// Reimplementa nativamente o script pandas em anexo (picos P/P95 por
// faixa, e base_mb/mb_por_usuario por unidade via minimos quadrados).

User Function MonFaixaHorario(nHora)
    If nHora < 8
        Return "00-08"
    ElseIf nHora < 12
        Return "08-12"
    ElseIf nHora < 18
        Return "12-18"
    EndIf
Return "18-24"

// Le um ou mais arquivos coleta_*.csv e devolve array de linhas
// (JsonObject com TS/UNIDADE/HOSTPORTA/STATUS/USUARIOS/MEMORIAKB/CPU),
// so as com STATUS == "OK" (equivalente ao df[df.status=="OK"] do
// script original).
User Function MonColetaLer(aArquivos)
    Local aLinhas := {}
    Local cConteudo
    Local aBrutas
    Local aCampos
    Local oLin
    Local i
    Local k

    For i := 1 To Len(aArquivos)
        cConteudo := MemoRead(aArquivos[i])
        If cConteudo == ""
            Loop
        EndIf
        aBrutas := StrTokArr(cConteudo, Chr(10))
        For k := 2 To Len(aBrutas)  // pula cabecalho
            aCampos := StrTokArr(AllTrim(StrTran(aBrutas[k], Chr(13), "")), ";")
            If Len(aCampos) < 7 .Or. aCampos[4] != "OK"
                Loop
            EndIf
            oLin := JsonObject():New()
            oLin["TS"]        := aCampos[1]
            oLin["UNIDADE"]   := aCampos[2]
            oLin["HOSTPORTA"] := aCampos[3]
            oLin["STATUS"]    := aCampos[4]
            oLin["USUARIOS"]  := Val(aCampos[5])
            oLin["MEMORIAKB"] := Val(aCampos[6])
            oLin["CPU"]       := Val(aCampos[7])
            AAdd(aLinhas, oLin)
        Next
    Next
Return aLinhas

// Extrai a hora (0-23) de um timestamp "dd/mm/yyyy hh:mm:ss".
User Function MonColetaHora(cTs)
    Local nPosEspaco := At(" ", cTs)

    If nPosEspaco == 0
        Return 0
    EndIf
Return Val(SubStr(cTs, nPosEspaco + 1, 2))

// Percentil por interpolacao linear (equivalente a Series.quantile do
// pandas) sobre um array ja ordenado ascendente.
User Function MonPercentil(aOrdenado, nP)
    Local nN := Len(aOrdenado)
    Local nIdx
    Local nBase
    Local nFrac

    If nN == 0
        Return 0
    EndIf
    If nN == 1
        Return aOrdenado[1]
    EndIf
    nIdx  := nP * (nN - 1) + 1
    nBase := Int(nIdx)
    nFrac := nIdx - nBase
    If nBase >= nN
        Return aOrdenado[nN]
    EndIf
Return aOrdenado[nBase] + nFrac * (aOrdenado[nBase + 1] - aOrdenado[nBase])

User Function MonOrdenarNumeros(aVals)
    Local aOrd := AClone(aVals)
Return ASort(aOrd)

// Pico de usuarios (soma por unidade+ts, ja que cada server e uma
// linha) por unidade+faixa: P (maximo) e P95. Devolve array de
// JsonObject {UNIDADE,FAIXA,P,P95}.
User Function MonAnalisePicos(aLinhas)
    Local oSomaPorChave := JsonObject():New()  // "UNIDADE|TS|FAIXA" -> soma usuarios
    Local oChaves := JsonObject():New()        // "UNIDADE|FAIXA" -> array de somas
    Local cChaveTs
    Local cChaveFaixa
    Local cFaixa
    Local oLin
    Local aResultado := {}
    Local aPartes
    Local i

    For i := 1 To Len(aLinhas)
        oLin := aLinhas[i]
        cFaixa := MonFaixaHorario(MonColetaHora(oLin["TS"]))
        cChaveTs := oLin["UNIDADE"] + "|" + oLin["TS"]
        If !oSomaPorChave:HasProperty(cChaveTs)
            oSomaPorChave[cChaveTs] := 0
        EndIf
        oSomaPorChave[cChaveTs] := oSomaPorChave[cChaveTs] + oLin["USUARIOS"]
        If !oSomaPorChave:HasProperty(cChaveTs + "_FAIXA")
            oSomaPorChave[cChaveTs + "_FAIXA"] := cFaixa
        EndIf
    Next

    For i := 1 To Len(aLinhas)
        oLin := aLinhas[i]
        cChaveTs := oLin["UNIDADE"] + "|" + oLin["TS"]
        cFaixa := oSomaPorChave[cChaveTs + "_FAIXA"]
        cChaveFaixa := oLin["UNIDADE"] + "|" + cFaixa
        If !oChaves:HasProperty(cChaveFaixa)
            oChaves[cChaveFaixa] := {}
        EndIf
        If AScan(oChaves[cChaveFaixa], {|n| n == oSomaPorChave[cChaveTs]}) == 0
            AAdd(oChaves[cChaveFaixa], oSomaPorChave[cChaveTs])
        EndIf
    Next

    Local aNomesFaixa := GetNames(oChaves)
    For i := 1 To Len(aNomesFaixa)
        aPartes := StrTokArr(aNomesFaixa[i], "|")
        Local aVals := MonOrdenarNumeros(oChaves[aNomesFaixa[i]])
        Local oRes := JsonObject():New()
        oRes["UNIDADE"] := aPartes[1]
        oRes["FAIXA"]   := aPartes[2]
        oRes["P"]       := aVals[Len(aVals)]
        oRes["P95"]     := MonPercentil(aVals, 0.95)
        AAdd(aResultado, oRes)
    Next
Return aResultado

// Regressao linear (minimos quadrados) de memoria (MB) por usuarios,
// por unidade -- devolve array de JsonObject {UNIDADE,BASE_MB,MB_POR_USUARIO}.
// So entram linhas com USUARIOS > 0 (mesmo filtro do script original).
User Function MonAnaliseMemoria(aLinhas)
    Local oPorUnidade := JsonObject():New()
    Local oLin
    Local i
    Local aResultado := {}
    Local cUnidade
    Local aXY
    Local nN
    Local nM, nB

    For i := 1 To Len(aLinhas)
        oLin := aLinhas[i]
        If oLin["USUARIOS"] <= 0
            Loop
        EndIf
        cUnidade := oLin["UNIDADE"]
        If !oPorUnidade:HasProperty(cUnidade)
            oPorUnidade[cUnidade] := {}
        EndIf
        AAdd(oPorUnidade[cUnidade], {oLin["USUARIOS"], oLin["MEMORIAKB"] / 1024})
    Next

    Local aNomesUnidade := GetNames(oPorUnidade)
    For i := 1 To Len(aNomesUnidade)
        cUnidade := aNomesUnidade[i]
        aXY := oPorUnidade[cUnidade]
        nN := Len(aXY)
        // ponytail-note: nSomaX etc PRECISAM nascer com ":= 0" na mesma
        // linha do Local -- "Local x" seguido de "x := 0" em linha
        // separada gera um slot diferente do capturado pelo codeblock do
        // AEval abaixo (bug de closure do advplc), fazendo a soma nunca
        // acumular. Visto na pratica: somaX ficava 0 mesmo com 3 pontos.
        Local nSomaX := 0
        Local nSomaY := 0
        Local nSomaXY := 0
        Local nSomaXX := 0
        AEval(aXY, {|p| nSomaX += p[1], nSomaY += p[2], nSomaXY += p[1] * p[2], nSomaXX += p[1] * p[1]})

        If nN < 2 .Or. (nN * nSomaXX - nSomaX * nSomaX) == 0
            Loop
        EndIf
        nM := (nN * nSomaXY - nSomaX * nSomaY) / (nN * nSomaXX - nSomaX * nSomaX)
        nB := (nSomaY - nM * nSomaX) / nN

        Local oRes := JsonObject():New()
        oRes["UNIDADE"]       := cUnidade
        oRes["BASE_MB"]       := nB
        oRes["MB_POR_USUARIO"] := nM
        AAdd(aResultado, oRes)
    Next
Return aResultado

// --- Rota web /analise -- mesmo padrao de MonRotaConfigForm/MonRotaDashboard
// (handler recebe oParams do WSRestServer + args fixos da chamada).

User Function MonGerarAnaliseHtml(aPicos, aMem, nDias)
    Local cHtml := "<!doctype html><html><head><meta charset='utf-8'>" + ;
        "<meta name='viewport' content='width=device-width,initial-scale=1'>" + ;
        "<title>Monitor Protheus - Analise historica</title>" + ;
        "<style>" + MonCssBase() + "</style>" + ;
        "</head><body>"
    Local i

    cHtml += "<header class='topbar'><h1>Analise historica</h1>" + ;
        "<nav><a href='/'>&larr; voltar pro dashboard</a></nav></header>"
    cHtml += "<main>"
    cHtml += "<p class='meta'>Base: ultimos " + AllTrim(Str(nDias)) + " dia(s) de coleta.</p>"

    cHtml += "<div class='card'><h2>Pico de usuarios por faixa de horario</h2>"
    If Len(aPicos) == 0
        cHtml += "<p class='empty'>Sem dados ainda -- aguarde a coleta acumular amostras.</p>"
    Else
        cHtml += "<table><tr><th>Unidade</th><th>Faixa</th><th>Pico (max)</th><th>P95</th></tr>"
        For i := 1 To Len(aPicos)
            cHtml += "<tr><td><b>" + aPicos[i]["UNIDADE"] + "</b></td><td>" + aPicos[i]["FAIXA"] + "</td>" + ;
                "<td>" + AllTrim(Str(aPicos[i]["P"])) + "</td>" + ;
                "<td>" + AllTrim(Str(Round(aPicos[i]["P95"], 1))) + "</td></tr>"
        Next
        cHtml += "</table>"
    EndIf
    cHtml += "</div>"

    cHtml += "<div class='card'><h2>Memoria por unidade (regressao linear)</h2>"
    If Len(aMem) == 0
        cHtml += "<p class='empty'>Sem dados ainda -- aguarde a coleta acumular amostras.</p>"
    Else
        cHtml += "<table><tr><th>Unidade</th><th>Base (MB)</th><th>MB por usuario</th></tr>"
        For i := 1 To Len(aMem)
            cHtml += "<tr><td><b>" + aMem[i]["UNIDADE"] + "</b></td>" + ;
                "<td>" + AllTrim(Str(Round(aMem[i]["BASE_MB"], 0))) + "</td>" + ;
                "<td>" + AllTrim(Str(Round(aMem[i]["MB_POR_USUARIO"], 1))) + "</td></tr>"
        Next
        cHtml += "</table>"
    EndIf
    cHtml += "</div>"

    cHtml += "</main></body></html>"
Return cHtml

// nDiasPadrao fixo em 30: dashboard nao tem UI pra escolher range (ponytail
// -- adicionar query param quando alguem pedir range configuravel).
User Function MonRotaAnalise(oParams)
    Local nDias := 30
    Local aArquivos := MonColetaArquivosUltimosDias(nDias)
    Local aLinhas := MonColetaLer(aArquivos)
    Local aPicos := MonAnalisePicos(aLinhas)
    Local aMem := MonAnaliseMemoria(aLinhas)
Return {"__RAW_HTTP__", "text/html", MonGerarAnaliseHtml(aPicos, aMem, nDias), 200}
