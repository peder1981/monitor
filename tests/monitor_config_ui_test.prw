#include "../src/monitor_lib.prw"
#include "../src/monitor_broker.prw"
#include "../src/monitor_dashboard.prw"
#include "../src/monitor_config_ui.prw"

User Function MonitorConfigUiTest()
    // --- MonTokensLinha ---
    ConOut("teste1_tokens_simples=" + Str(Len(MonTokensLinha("ORTOSP 10.0.100.62 8090"))))
    ConOut("teste2_tokens_espacos_multiplos=" + Str(Len(MonTokensLinha("ORTOSP    10.0.100.62   8090"))))
    ConOut("teste3_tokens_vazio=" + Str(Len(MonTokensLinha(""))))

    // --- MonTextoParaUnidades ---
    Local cTexto := "ORTOSP 10.0.100.62 8090" + Chr(10) + "ORTORJ 10.0.100.53 8090" + Chr(10)
    Local oParsed := MonTextoParaUnidades(cTexto)

    ConOut("teste4_parse_ok=" + IIF(oParsed["OK"], "SIM", "NAO"))
    ConOut("teste5_parse_qtd=" + Str(Len(oParsed["UNIDADES"])))
    ConOut("teste6_parse_u1_nome=" + oParsed["UNIDADES"][1]["nome"])
    ConOut("teste7_parse_u1_host=" + oParsed["UNIDADES"][1]["host"])
    ConOut("teste8_parse_u1_porta=" + Str(oParsed["UNIDADES"][1]["porta"]))

    // linhas em branco no meio/fim sao ignoradas, nao viram erro
    Local cTextoComBranco := "ORTOSP 10.0.100.62 8090" + Chr(10) + Chr(10) + "  " + Chr(10) + "ORTORJ 10.0.100.53 8090"
    Local oParsed2 := MonTextoParaUnidades(cTextoComBranco)
    ConOut("teste9_ignora_linhas_brancas=" + IIF(oParsed2["OK"] .And. Len(oParsed2["UNIDADES"]) == 2, "SIM", "NAO"))

    // linha malformada (nao tem 3 tokens) vira erro, sem salvar nada
    Local oParsed3 := MonTextoParaUnidades("ORTOSP 10.0.100.62" + Chr(10) + "ORTORJ 10.0.100.53 8090")
    ConOut("teste10_linha_faltando_campo_invalida=" + IIF(oParsed3["OK"], "NAO", "SIM"))
    ConOut("teste11_erro_tem_a_linha_ruim=" + IIF("ORTOSP 10.0.100.62" $ oParsed3["ERRO"], "SIM", "NAO"))

    // porta nao numerica vira erro
    Local oParsed4 := MonTextoParaUnidades("ORTOSP 10.0.100.62 abc")
    ConOut("teste12_porta_nao_numerica_invalida=" + IIF(oParsed4["OK"], "NAO", "SIM"))

    // texto vazio (sem nenhuma unidade) vira erro -- nao pode salvar lista vazia
    Local oParsed5 := MonTextoParaUnidades("")
    ConOut("teste13_texto_vazio_invalido=" + IIF(oParsed5["OK"], "NAO", "SIM"))

    // --- MonUnidadesParaTexto (ida e volta) ---
    Local aUnidadesOrig := {}
    Local oU1 := JsonObject():New()
    Local oU2 := JsonObject():New()

    oU1["nome"] := "ORTOSP"
    oU1["host"] := "10.0.100.62"
    oU1["porta"] := 8090
    oU2["nome"] := "ORTORJ"
    oU2["host"] := "10.0.100.53"
    oU2["porta"] := 8090
    AAdd(aUnidadesOrig, oU1)
    AAdd(aUnidadesOrig, oU2)

    Local cTextoGerado := MonUnidadesParaTexto(aUnidadesOrig)
    ConOut("teste14_texto_gerado_tem_ortosp=" + IIF("ORTOSP 10.0.100.62 8090" $ cTextoGerado, "SIM", "NAO"))

    Local oParsedVolta := MonTextoParaUnidades(cTextoGerado)
    ConOut("teste15_ida_e_volta_bate=" + IIF(oParsedVolta["OK"] .And. Len(oParsedVolta["UNIDADES"]) == 2 .And. oParsedVolta["UNIDADES"][2]["nome"] == "ORTORJ", "SIM", "NAO"))

    // --- MonConfigParaJson / MonSalvarUnidadesConfig (round-trip completo) ---
    Local cConfigPath := "test_config_ui.json"

    MemoWrite(cConfigPath, '{"unidades":[{"nome":"VELHA","host":"1.2.3.4","porta":1}],' + ;
                           '"intervaloSegundos":60,"timeoutMs":1000,"dashboardPorta":9099,' + ;
                           '"dashboardSenha":"segredo123",' + ;
                           '"telegramBotToken":"TOKEN","telegramChatId":"123",' + ;
                           '"portaDbaccess":1234,"licenseServer":{"host":"10.0.200.98","port":5555}}')

    ConOut("teste16_salvou=" + IIF(MonSalvarUnidadesConfig(cConfigPath, aUnidadesOrig), "SIM", "NAO"))

    Local oConfigRecarregado := MonLoadConfig(cConfigPath)
    ConOut("teste17_unidades_atualizadas=" + Str(Len(MonGetUnidades(oConfigRecarregado))))
    ConOut("teste18_unidade1_nome=" + MonGetUnidades(oConfigRecarregado)[1]["nome"])

    // as outras chaves do config.json precisam sobreviver intactas --
    // MonSalvarUnidadesConfig so deve mexer em "unidades".
    ConOut("teste19_intervalo_preservado=" + Str(oConfigRecarregado["intervaloSegundos"]))
    ConOut("teste20_timeout_preservado=" + Str(oConfigRecarregado["timeoutMs"]))
    ConOut("teste21_dashboardporta_preservada=" + Str(oConfigRecarregado["dashboardPorta"]))
    ConOut("teste22_senha_preservada=" + oConfigRecarregado["dashboardSenha"])
    ConOut("teste23_token_preservado=" + oConfigRecarregado["telegramBotToken"])
    ConOut("teste24_chatid_preservado=" + oConfigRecarregado["telegramChatId"])
    ConOut("teste25_portadbaccess_preservada=" + Str(oConfigRecarregado["portaDbaccess"]))
    ConOut("teste26_licenseserver_preservado=" + oConfigRecarregado["licenseServer"]["host"] + ":" + Str(oConfigRecarregado["licenseServer"]["port"]))

    FErase(cConfigPath)

    // --- MonRotaConfigForm / MonRotaConfigSalvar (HTTP) ---
    Local cConfigPath2 := "test_config_ui2.json"

    MemoWrite(cConfigPath2, '{"unidades":[{"nome":"ORTOSP","host":"10.0.100.62","porta":8090}],' + ;
                            '"intervaloSegundos":60,"timeoutMs":1000,"dashboardSenha":"abc123",' + ;
                            '"telegramBotToken":"T","telegramChatId":"1"}')

    Local aResp := MonRotaConfigForm(Nil, cConfigPath2)
    ConOut("teste27_form_sentinela=" + aResp[1])
    ConOut("teste28_form_tem_ortosp=" + IIF("ORTOSP 10.0.100.62 8090" $ aResp[3], "SIM", "NAO"))

    // senha errada nao salva nada
    Local oParamsErrado := JsonObject():New()
    oParamsErrado["SENHA"] := "senhaerrada"
    oParamsErrado["UNIDADES"] := "NOVA 9.9.9.9 1111"
    Local aRespErrado := MonRotaConfigSalvar(oParamsErrado, cConfigPath2)
    ConOut("teste29_senha_errada_nao_altera=" + IIF("ORTOSP" $ MonUnidadesParaTexto(MonGetUnidades(MonLoadConfig(cConfigPath2))), "SIM", "NAO"))
    ConOut("teste30_senha_errada_avisa=" + IIF("incorreta" $ aRespErrado[3], "SIM", "NAO"))

    // senha certa salva de verdade
    Local oParamsCerto := JsonObject():New()
    oParamsCerto["SENHA"] := "abc123"
    oParamsCerto["UNIDADES"] := "NOVA 9.9.9.9 1111"
    Local aRespCerto := MonRotaConfigSalvar(oParamsCerto, cConfigPath2)
    ConOut("teste31_senha_certa_altera=" + IIF("NOVA" $ MonUnidadesParaTexto(MonGetUnidades(MonLoadConfig(cConfigPath2))), "SIM", "NAO"))
    ConOut("teste32_senha_certa_confirma=" + IIF("Salvo" $ aRespCerto[3], "SIM", "NAO"))

    // sem dashboardSenha no config: edicao fica desabilitada, nunca salva
    Local cConfigPath3 := "test_config_ui3.json"
    MemoWrite(cConfigPath3, '{"unidades":[{"nome":"ORTOSP","host":"10.0.100.62","porta":8090}],' + ;
                            '"intervaloSegundos":60,"timeoutMs":1000,' + ;
                            '"telegramBotToken":"T","telegramChatId":"1"}')
    Local oParamsSemSenha := JsonObject():New()
    oParamsSemSenha["SENHA"] := ""
    oParamsSemSenha["UNIDADES"] := "NOVA 9.9.9.9 1111"
    MonRotaConfigSalvar(oParamsSemSenha, cConfigPath3)
    ConOut("teste33_sem_senha_config_nao_altera=" + IIF("ORTOSP" $ MonUnidadesParaTexto(MonGetUnidades(MonLoadConfig(cConfigPath3))), "SIM", "NAO"))
    FErase(cConfigPath3)

    FErase(cConfigPath2)

    ConOut("MONITOR_CONFIG_UI_TEST_FIM")
Return
