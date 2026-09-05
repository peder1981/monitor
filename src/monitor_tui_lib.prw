// TUI do monitor - renderizacao de tabela de status em ASCII

User Function MonTuiLinhaStatus(cChave, cStatus, nLatenciaMs)
    Local cCor := IIF(cStatus == "UP", "42", "196")
    Local cLatencia := IIF(nLatenciaMs < 0, "--", AllTrim(Str(nLatenciaMs, 6, 0)) + "ms")
Return PadR(cChave, 24) + " " + PadR(cStatus, 12) + " " + PadL(cLatencia, 8)

User Function MonTuiMontarTabela(oConfig, oState)
    Local aUnidades := MonGetUnidades(oConfig)
    Local cCorpo := ""
    Local cUnidade
    Local i

    For i := 1 To Len(aUnidades)
        cUnidade := aUnidades[i]
        cCorpo += MonTuiLinhaStatus(cUnidade, MonGetStatusAnterior(oState, cUnidade), MonGetLatenciaAnterior(oState, cUnidade)) + Chr(10)

        If oConfig:HasProperty("portaDbaccess")
            cCorpo += MonTuiLinhaStatus(cUnidade + "_DBACCESS", MonGetStatusAnterior(oState, cUnidade + "_DBACCESS"), MonGetLatenciaAnterior(oState, cUnidade + "_DBACCESS")) + Chr(10)
        EndIf
    Next

    If oConfig:HasProperty("licenseServer")
        cCorpo += MonTuiLinhaStatus("LICENSE_SERVER", MonGetStatusAnterior(oState, "LICENSE_SERVER"), MonGetLatenciaAnterior(oState, "LICENSE_SERVER")) + Chr(10)
    EndIf
Return cCorpo

User Function MonTuiProcessoEstaRodando(cSaidaTasklist)
Return "MonitorService.exe" $ cSaidaTasklist

User Function MonTuiVerificarServicoRodando()
    Local cSaida := ""
    Local bAcumula := {|cLinha| cSaida += cLinha + Chr(10)}

    ProcRun("tasklist", {"/FI", "IMAGENAME eq MonitorService.exe", "/FO", "CSV", "/NH"}, bAcumula)
Return MonTuiProcessoEstaRodando(cSaida)

// NOTA (achado 10 da revisao final): WaitRun() deste interpretador faz
// strings.Fields(cmdStr) antes de invocar o SO -- um split ingenuo por
// qualquer espaco em branco, sem nenhuma nocao de aspas. Envolver
// cCaminhoExe em aspas (aspas + start ["" "caminho"]) NAO resolve um
// caminho com espaco: o split ocorre ANTES de qualquer interpretacao de
// aspas, entao 'C:\Program Files\x.exe' vira dois tokens quebrados
// mesmo entre aspas. Nao ha correcao limpa usando WaitRun com uma unica
// string quando o caminho pode conter espaco; a alternativa correta
// seria expor um ProcRun/WaitRun que aceite argv como array (como o
// ProcRun ja usado em MonTuiVerificarServicoRodando) em vez de uma
// linha de comando unica. Deixado como esta -- ver achado 10 no
// relatorio de revisao final.
User Function MonTuiIniciarServico(cCaminhoExe)
    WaitRun("cmd /c start " + cCaminhoExe)
Return Nil

User Function MonTuiPararServico()
    WaitRun("taskkill /IM MonitorService.exe /F")
Return Nil
