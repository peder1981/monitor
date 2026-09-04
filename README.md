# Monitor de Unidades Protheus

Vigia o broker TCP (SmartClient) de cada unidade Protheus listada num
`.ini` de conexão existente, e avisa no Telegram quando uma unidade cai
ou volta.

## Compilar

A partir de um checkout do AdvPP (https://github.com/peder1981/AdvPP):

    ./advplc build /caminho/para/monitor/src/monitor.prw -o monitor.exe

Rodando em Linux, gera um binário do SO atual. Cross-compile pra
Windows a partir do Linux (`GOOS=windows GOARCH=amd64 ./advplc build ...`)
foi testado e **não funciona**: o `build` do `advplc` embarca a UI Fyne
(mesmo pra um programa headless como este), que puxa `go-gl` com
bindings OpenGL nativos (cgo) — o build falha com:

    imports github.com/go-gl/gl/v2.1/gl: build constraints exclude all
    Go files in .../go-gl@.../v2.1/gl

Ou seja, não é falta de `GOOS`/`GOARCH` ser respeitado — o processo de
build interno do `advplc` depende de toolchain nativa (cgo + headers
GL) do SO alvo, que não está disponível cross-compilando do Linux.
**Alternativa**: compile direto na máquina Windows, com um checkout do
AdvPP e o `advplc.exe` instalado lá:

    advplc.exe build C:\caminho\para\monitor\src\monitor.prw -o monitor.exe

## Configurar

Copie `config.example.json` para `config.json` ao lado do `monitor.exe`
e preencha:

- `iniPath`: caminho completo do `.ini` de conexão do SmartClient na
  máquina Windows (ex: `C:\\totvs\\appserver.ini`).
- `telegramBotToken` / `telegramChatId`: credenciais do bot do Telegram
  que vai mandar os alertas.
- `unidades`: lista dos nomes de seção do `.ini` a vigiar (ex: `TCPSP`,
  `TCPRJ`, ...).
- `intervaloSegundos` / `timeoutMs`: frequência da checagem e timeout
  de cada tentativa de conexão TCP.

## Rodar os testes

`tests/monitor_lib_test.prw` cobre `src/monitor_lib.prw` (checagem TCP,
estado, config, log, montagem de mensagem e o ciclo de
`MonProcessarUnidade`). O `teste1` (unidade `TCPOK`) precisa de algo
escutando em `127.0.0.1:19191` antes de rodar a suite — os demais testes
usam portas que ninguém escuta de propósito, então não precisam de setup.

1. Suba um listener descartável na porta 19191 (fica escutando até você
   matar o processo com Ctrl+C):

       python3 -c "
       import socket
       s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
       s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
       s.bind(('127.0.0.1', 19191))
       s.listen(5)
       while True:
           conn, addr = s.accept()
           conn.close()
       "

2. Em outro terminal, rode a suite (ajuste o caminho do `advplc` pra onde
   ele estiver instalado):

       cd tests && /caminho/para/advplc run monitor_lib_test.prw

3. A última linha da saída deve ser `MONITOR_LIB_TEST_FIM`, sem nenhuma
   linha de erro do compilador/interpretador acima dela. Cada asserção
   individual aparece como `testeN_descricao=SIM|NAO` (ou o valor
   esperado) — releia a saída se algo não bater.

## Rodar

    monitor.exe

Fica em loop pra sempre, gerando `monitor.log` (toda checagem) e
`state.json` (último status conhecido de cada unidade) ao lado do
`.exe`. Agende no Task Scheduler do Windows como "ao iniciar o
sistema", sem precisar de serviço Windows — o `Sleep` interno já
mantém o processo vivo.
