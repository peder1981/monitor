#include "monitor_lib.prw"
#include "monitor_broker.prw"
#include "monitor_dashboard.prw"
#include "monitor_config_ui.prw"
#include "monitor_coleta.prw"

User Function MonitorMain()
    Local cConfigPath    := "config.json"
    Local cStatePath     := "state.json"
    Local cLogPath       := "monitor.log"
    Local cDashboardPath := "dashboard.json"
    Local oConfig
    Local oConfigNovo
    Local oState
    Local aUnidades
    Local aResUnidades
    Local aResDbaccess
    Local oResLicense
    Local oResUnidade
    Local i

    oConfig := MonLoadConfig(cConfigPath)
    If !MonConfigValido(oConfig)
        ConOut("ERRO FATAL: config.json invalido (unidades/intervaloSegundos/timeoutMs)")
        MonLog(cLogPath, "ERRO FATAL: config.json invalido (unidades/intervaloSegundos/timeoutMs)")
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

    ConOut("Monitor iniciado. " + AllTrim(Str(Len(MonGetUnidades(oConfig)))) + " unidade(s), intervalo de " + AllTrim(Str(oConfig["intervaloSegundos"])) + "s.")

    While .T.
        // Hot-reload: rele config.json a cada ciclo (o dashboard web pode
        // editar "unidades" via /config, sem reiniciar o servico). Se a
        // leitura falhar ou vier invalida (arquivo sendo escrito no
        // exato instante da leitura, por exemplo), mantem o ultimo config
        // valido em memoria em vez de derrubar o loop.
        oConfigNovo := MonLoadConfig(cConfigPath)
        If MonConfigValido(oConfigNovo)
            oConfig := oConfigNovo
        Else
            MonLog(cLogPath, "AVISO: config.json invalido nesta leitura, mantendo config anterior em memoria")
        EndIf

        aUnidades    := MonGetUnidades(oConfig)
        aResUnidades := {}
        aResDbaccess := {}
        oResLicense  := Nil

        For i := 1 To Len(aUnidades)
            oResUnidade := MonProcessarUnidade(aUnidades[i]["nome"], aUnidades[i]["host"], aUnidades[i]["porta"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"], IIF(aUnidades[i]:HasProperty("endpoint"), aUnidades[i]["endpoint"], Nil))
            AAdd(aResUnidades, oResUnidade)

            If oConfig:HasProperty("portaDbaccess")
                AAdd(aResDbaccess, MonProcessarDbaccess(aUnidades[i]["nome"], aUnidades[i]["host"], oConfig["portaDbaccess"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"]))
            EndIf
        Next

        If oConfig:HasProperty("licenseServer")
            oResLicense := MonProcessarLicenseServer(oConfig["licenseServer"]["host"], oConfig["licenseServer"]["port"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
        EndIf

        MonSalvarDashboard(cDashboardPath, aResUnidades, aResDbaccess, oResLicense, oConfig["intervaloSegundos"])
        MonColetarAmostra(MonColetaArquivoHoje(), aResUnidades)
        MonSaveState(cStatePath, oState)
        Sleep(oConfig["intervaloSegundos"] * 1000)
    EndDo
Return
