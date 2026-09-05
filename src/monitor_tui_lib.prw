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

    If GetSrvInfo()[2] == "Windows"
        ProcRun("tasklist", {"/FI", "IMAGENAME eq MonitorService.exe", "/FO", "CSV", "/NH"}, bAcumula)
        Return MonTuiProcessoEstaRodando(cSaida)
    EndIf

    ProcRun("pgrep", {"-x", "MonitorService"}, bAcumula)
Return Len(AllTrim(cSaida)) > 0

User Function MonTuiIniciarServico(cNomeBase)
    Local bNoop := {|cLinha| Nil}

    If GetSrvInfo()[2] == "Windows"
        WaitRun("cmd /c start " + cNomeBase + ".exe")
    Else
        ProcRun("sh", {"-c", "./" + cNomeBase + " > /dev/null 2>&1 & echo lancado"}, bNoop)
    EndIf
Return Nil

User Function MonTuiPararServico()
    Local bNoop := {|cLinha| Nil}

    If GetSrvInfo()[2] == "Windows"
        WaitRun("taskkill /IM MonitorService.exe /F")
    Else
        ProcRun("pkill", {"-x", "MonitorService"}, bNoop)
    EndIf
Return Nil
