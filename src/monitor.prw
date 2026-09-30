#include "monitor_lib.prw"
#include "monitor_broker.prw"
#include "monitor_dashboard.prw"

User Function MonitorMain()
    Local cConfigPath    := "config.json"
    Local cStatePath     := "state.json"
    Local cLogPath       := "monitor.log"
    Local cDashboardPath := "dashboard.json"
    Local oConfig
    Local oState
    Local aUnidades
    Local aResUnidades
    Local aResDbaccess
    Local oResLicense
    Local oResUnidade
    Local i

    oConfig := MonLoadConfig(cConfigPath)
    If oConfig == Nil
        ConOut("ERRO FATAL: nao foi possivel ler " + cConfigPath)
        MonLog(cLogPath, "ERRO FATAL: nao foi possivel ler " + cConfigPath)
        Return
    EndIf

    aUnidades := MonGetUnidades(oConfig)
    If Len(aUnidades) == 0
        ConOut("ERRO FATAL: config.json sem a chave 'unidades' ou lista vazia")
        MonLog(cLogPath, "ERRO FATAL: config.json sem a chave 'unidades' ou lista vazia")
        Return
    EndIf

    If !oConfig:HasProperty("intervaloSegundos") .Or. oConfig["intervaloSegundos"] <= 0
        ConOut("ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        Return
    EndIf

    If !oConfig:HasProperty("timeoutMs") .Or. oConfig["timeoutMs"] <= 0
        ConOut("ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        Return
    EndIf

    If oConfig:HasProperty("dashboardPorta") .And. oConfig["dashboardPorta"] > 0
        StartJob("MonServirDashboard", "", .F., oConfig["dashboardPorta"])
        ConOut("Dashboard web em http://localhost:" + AllTrim(Str(oConfig["dashboardPorta"])) + "/")
    Else
        ConOut("AVISO: dashboardPorta ausente/invalida -- dashboard web desabilitado")
        MonLog(cLogPath, "AVISO: dashboardPorta ausente/invalida -- dashboard web desabilitado")
    EndIf

    oState := MonLoadState(cStatePath)

    ConOut("Monitor iniciado. " + AllTrim(Str(Len(aUnidades))) + " unidade(s), intervalo de " + AllTrim(Str(oConfig["intervaloSegundos"])) + "s.")

    While .T.
        aResUnidades := {}
        aResDbaccess := {}
        oResLicense  := Nil

        For i := 1 To Len(aUnidades)
            oResUnidade := MonProcessarUnidade(aUnidades[i]["nome"], aUnidades[i]["host"], aUnidades[i]["porta"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
            AAdd(aResUnidades, oResUnidade)

            If oConfig:HasProperty("portaDbaccess")
                AAdd(aResDbaccess, MonProcessarDbaccess(aUnidades[i]["nome"], aUnidades[i]["host"], oConfig["portaDbaccess"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"]))
            EndIf
        Next

        If oConfig:HasProperty("licenseServer")
            oResLicense := MonProcessarLicenseServer(oConfig["licenseServer"]["host"], oConfig["licenseServer"]["port"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
        EndIf

        MonSalvarDashboard(cDashboardPath, aResUnidades, aResDbaccess, oResLicense)
        MonSaveState(cStatePath, oState)
        Sleep(oConfig["intervaloSegundos"] * 1000)
    EndDo
Return
