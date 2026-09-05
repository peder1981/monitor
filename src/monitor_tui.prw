#include "monitor_lib.prw"
#include "monitor_tui_lib.prw"

User Function MonitorTuiMain()
    Local cConfigPath := "config.json"
    Local cStatePath  := "state.json"
    Local cLogPath    := "monitor.log"
    Local oConfig
    Local oState
    Local cTabela
    Local lSair := .F.
    Local nOpcao
    Local cLinhasLog

    oConfig := MonLoadConfig(cConfigPath)
    If oConfig == Nil
        ConOut("ERRO FATAL: nao foi possivel ler " + cConfigPath)
        Return
    EndIf

    UiAltScreenEnter()

    While !lSair
        oState := MonLoadState(cStatePath)
        cTabela := MonTuiMontarTabela(oConfig, oState)
        UiStreamBox("Monitor Protheus - Status", cTabela + Chr(10) + ;
            "Servico: " + IIF(MonTuiVerificarServicoRodando(), "RODANDO", "PARADO") + Chr(10) + Chr(10) + ;
            "[1] Iniciar servico  [2] Parar servico  [3] Ver log  [4] Sair", "39", 70)

        nOpcao := Val(FWGetText("Escolha uma opcao (1-4)", "", .F.))

        Do Case
        Case nOpcao == 1
            MonTuiIniciarServico("MonitorService")
        Case nOpcao == 2
            MonTuiPararServico()
        Case nOpcao == 3
            cLinhasLog := MemoRead(cLogPath)
            ConOut(cLinhasLog)
            FWGetText("Pressione Enter para voltar", "", .F.)
        Case nOpcao == 4
            lSair := .T.
        EndCase
    EndDo

    UiStreamReset()
    UiAltScreenExit()
Return
