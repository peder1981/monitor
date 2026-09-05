// TUI do monitor - renderizacao de tabela de status em ASCII

User Function MonTuiLinhaStatus(cChave, cStatus, nLatenciaMs)
    Local cCor := IIF(cStatus == "UP", "42", "196")
Return PadR(cChave, 24) + " " + PadR(cStatus, 6) + " " + PadL(AllTrim(Str(nLatenciaMs)) + "ms", 8)

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
