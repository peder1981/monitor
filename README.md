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

## Rodar

    monitor.exe

Fica em loop pra sempre, gerando `monitor.log` (toda checagem) e
`state.json` (último status conhecido de cada unidade) ao lado do
`.exe`. Agende no Task Scheduler do Windows como "ao iniciar o
sistema", sem precisar de serviço Windows — o `Sleep` interno já
mantém o processo vivo.
