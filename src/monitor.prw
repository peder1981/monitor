#include "monitor_lib.prw"

User Function MonitorMain()
    Local cConfigPath := "config.json"
    Local cStatePath  := "state.json"
    Local cLogPath    := "monitor.log"
    Local oConfig
    Local oState
    Local aUnidades
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

    If !oConfig:HasProperty("intervaloSegundos")
        ConOut("ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        Return
    EndIf
    If oConfig["intervaloSegundos"] <= 0
        ConOut("ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'intervaloSegundos' valido (> 0)")
        Return
    EndIf

    If !oConfig:HasProperty("timeoutMs")
        ConOut("ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        Return
    EndIf
    If oConfig["timeoutMs"] <= 0
        ConOut("ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        MonLog(cLogPath, "ERRO FATAL: config.json sem 'timeoutMs' valido (> 0)")
        Return
    EndIf

    oState := MonLoadState(cStatePath)

    ConOut("Monitor iniciado. " + AllTrim(Str(Len(aUnidades))) + " unidade(s), intervalo de " + AllTrim(Str(oConfig["intervaloSegundos"])) + "s.")

    While .T.
        For i := 1 To Len(aUnidades)
            MonProcessarUnidade(aUnidades[i], oConfig["iniPath"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])

            If oConfig:HasProperty("portaDbaccess")
                MonProcessarDbaccess(aUnidades[i], GetPvProfString(aUnidades[i], "Server", "", oConfig["iniPath"]), oConfig["portaDbaccess"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
            EndIf
        Next

        If oConfig:HasProperty("licenseServer")
            MonProcessarLicenseServer(oConfig["licenseServer"]["host"], oConfig["licenseServer"]["port"], oConfig["timeoutMs"], oState, cLogPath, oConfig["telegramBotToken"], oConfig["telegramChatId"])
        EndIf

        MonSaveState(cStatePath, oState)
        Sleep(oConfig["intervaloSegundos"] * 1000)
    EndDo
Return
