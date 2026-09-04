# Monitor de disponibilidade das unidades Protheus (AdvPL/AdvPP)

## Contexto

Ambiente com dezenas de unidades Protheus (uma por UF + duas unidades
especiais AF/OF), cada uma acessada via um broker TCP do SmartClient
(porta 4000 na maioria dos casos) declarado num `.ini` de conexão já
existente e mantido por outra área. O `.ini` tem uma seção por "unidade
lógica" (`TCPSP`, `TCPRJ`, `HOMOLOGSP`, `COMPSP`, `JOBSP`, etc.) — o
monitor deve olhar **só** para as seções que representam o broker
público de cada unidade: os UFs reais (`TCP` + sigla de UF do IBGE) mais
duas exceções nomeadas (`TCPAF`, `TCPOF`).

O monitor roda numa máquina Windows separada dos servidores Protheus,
compilado com o compilador AdvPP (`~/Projetos/AdvPP`, `advplc build`)
como executável standalone (`.exe`), sem depender de nenhum AppServer —
é só um binário Go com bytecode AdvPL embutido, agendado no Task
Scheduler do Windows.

Cobertura desta primeira versão: **appserver (broker TCP) de cada
unidade**, via TCP connect na porta do `.ini`. Dbaccess e license
server ficam fora do escopo agora porque não há, hoje, uma porta/URL
deles disponível neste mesmo `.ini` — ver seção "Fora de escopo".

## Arquitetura

Um único programa AdvPL (`monitor.prw`), sem threads, loop simples:

```
carregar config.json (unidades a vigiar + webhook Telegram + intervalo)
carregar estado anterior (state.json, se existir)
loop infinito:
    para cada unidade em config:
        ler Server/Port da seção correspondente no .ini do SmartClient
        lRespondeu := PING(Server, Port, nTimeoutMS)
        se lRespondeu != estado_anterior[unidade]:
            enviar Telegram (subiu/caiu, unidade, host:porta, horário)
            gravar novo estado em state.json
        logar linha em monitor.log (unidade, status, horário)
    Sleep(nIntervaloMS)
```

Sem threads: dezenas de unidades com timeout de ~2s cada, sequencial, é
no máximo dezenas de segundos por ciclo — irrelevante para um intervalo
de minutos. Não vale a complexidade de paralelizar.

## Componentes

**`config.json`** (editado à mão pelo operador, ao lado do `.exe`):
```json
{
  "iniPath": "C:\\totvs\\appserver.ini",
  "intervaloSegundos": 60,
  "timeoutMs": 3000,
  "telegramBotToken": "...",
  "telegramChatId": "...",
  "unidades": ["TCPSP", "TCPRJ", "TCPMG", "TCPGO", "TCPMT", "TCPBA",
               "TCPPE", "TCPCE", "TCPPR", "TCPPA", "TCPRS", "TCPAM",
               "TCPFB", "TCPAF", "TCPOF"]
}
```
Lista de unidades explícita e editável — nada de regex tentando
adivinhar o que é UF de verdade. Adicionar/remover unidade é editar
essa lista, sem recompilar.

**`state.json`** (escrito pelo próprio monitor, ao lado do `.exe`):
guarda o último status conhecido (`up`/`down`) de cada unidade, para
sobreviver a um restart do monitor sem reenviar alerta de algo que já
estava down antes de reiniciar.

**`monitor.log`**: uma linha por checagem, sempre (não só em mudança de
estado) — é o rastro para auditoria manual, `state.json`/Telegram são
só para alerta.

**Leitura do `.ini`**: `GetPvProfString(cUnidade, "Server", "", cIniPath)`
e `GetPvProfString(cUnidade, "Port", "", cIniPath)`, nativas do AdvPP
(`GETPVPROFSTRING`), sem parser próprio.

**Checagem TCP**: `PING(cHost, nPort, nTimeoutMs)`, nativa do AdvPP —
`net.DialTimeout` real, devolve `.T./.F.`.

**Notificação**: `FWHTTPPOST` para
`https://api.telegram.org/bot<TOKEN>/sendMessage` com corpo JSON
`{"chat_id":"...","text":"..."}`, `Content-Type: application/json`.
Falha de envio (status ≠ 200) só vai pro `monitor.log` — não há um
segundo canal de fallback nesta v1 (ver "Fora de escopo").

## Alertas: só na borda, não a cada ciclo

Alerta dispara apenas quando o novo status é diferente do guardado em
`state.json` — evita spam de "está caindo" a cada minuto enquanto a
unidade estiver fora. Ao voltar, dispara um alerta de recuperação
("TCPSP voltou, fora do ar por X min").

## Erros e robustez

- `.ini` ou seção inexistente: loga erro, trata como "sem dados",
  não derruba o loop.
- Falha ao enviar Telegram: loga erro, mantém o novo status em
  `state.json` mesmo assim (não trava re-tentando o mesmo alerta pra
  sempre — o próximo ciclo já reflete o estado real).
- Erro inesperado dentro do loop de uma unidade: `Try/Catch` por
  unidade, para uma unidade não travar a checagem das demais.

## Empacotamento e execução

```
advplc build monitor.prw -o monitor.exe   # cross-compile a partir do Linux, GOOS=windows
```
Copiar `monitor.exe`, `config.json` para a máquina Windows. Agendar via
Task Scheduler ("ao iniciar o sistema", reinício automático em caso de
crash) — sem precisar instalar como serviço Windows nem NSSM, o loop
interno com `Sleep` já mantém o processo vivo indefinidamente.

## Teste

`demo()`/self-check mínimo: um `.ini` de teste com 2 seções fake (uma
porta que responde — abrir um listener local — e uma que não
responde), roda um ciclo do loop de checagem (sem o `Sleep` infinito) e
`assert`a que o status detectado bate com o esperado para as duas.
Cobre a lógica que pode quebrar (leitura do ini + ping + comparação de
estado); não testa o envio real ao Telegram (I/O externo).

## Fora de escopo (v1)

- **Dbaccess e License Server**: não há porta/endpoint deles neste
  `.ini`. Se quiser cobrir depois, é a mesma receita (`PING` numa outra
  porta) — só falta você passar host:porta de cada um.
- Console REST do Protheus para detalhe além de "porta responde"
  (conexões ativas, uptime): não há endpoint definido ainda.
- Múltiplos canais de notificação / retry de envio.
- Paralelizar as checagens (`StartJob`) — só vale a pena se o número de
  unidades crescer a ponto do ciclo sequencial ficar longo perto do
  intervalo configurado.
