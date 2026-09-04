# Monitor de Unidades Protheus

Vigia o broker TCP (SmartClient) de cada unidade Protheus listada num
`.ini` de conexão existente, e avisa no Telegram quando uma unidade cai
ou volta. Opcionalmente também vigia o dbaccess de cada unidade (mesmo
host do appserver, porta configurável) e um license server centralizado
(único para todo o ambiente) — ver `portaDbaccess`/`licenseServer` em
"Configurar" abaixo.

## Instalar (sem compilar nada)

Este monitor **não precisa ser compilado**. Ele roda interpretado, direto
do `.prw`, pelo `advplc.exe` já pronto:

1. Baixe o `advplc.exe` em https://github.com/peder1981/AdvPP/releases
   (zip do Windows) — esse binário já vem com tudo que ele precisa
   embutido, não exige instalar nada mais na máquina.
2. Copie pra uma pasta na máquina Windows: `advplc.exe`,
   `src/monitor.prw`, `src/monitor_lib.prw` e o seu `config.json`
   (ver "Configurar" abaixo) — os quatro arquivos juntos, na mesma pasta.
3. Rode com `advplc.exe run monitor.prw` (ver "Rodar" abaixo).

**Por que não gerar um `monitor.exe` compilado:** `advplc build` sempre
linka a biblioteca de UI Fyne, mesmo pra um programa 100% console como
este, e Fyne exige cgo (compilador C) pra linkar — em qualquer
plataforma, Windows incluído. Na prática isso significa que
`advplc build` (rodando cross-compile do Linux, ou nativo já na própria
máquina Windows) pede um toolchain C (MinGW-w64/TDM-GCC no Windows) que
normalmente não está instalado, e falha sem gerar o executável. Isso já
foi testado dos dois jeitos:

- Cross-compile do Linux (`GOOS=windows GOARCH=amd64 ./advplc build ...`):
  falha com `imports github.com/go-gl/gl/v2.1/gl: build constraints
  exclude all Go files in .../go-gl@.../v2.1/gl` — não é o `GOOS`/`GOARCH`
  não ser respeitado, é falta de toolchain OpenGL/cgo do SO alvo.
- Nativo, direto na máquina Windows (`advplc.exe build ...`): pede pra
  instalar MinGW/gcc pelo mesmo motivo (cgo é exigido em qualquer SO,
  não só em cross-compile).

Rodar via `advplc.exe run monitor.prw` evita isso por completo: o
`advplc.exe` distribuído nas Releases já foi compilado (com Fyne e cgo)
uma única vez, pelos mantenedores do AdvPP — a máquina que só *roda* o
monitor nunca precisa de compilador nenhum. Se um dia você realmente
precisar de um `.exe` próprio (ex: renomear o processo, esconder que é
AdvPL), instale o MinGW-w64 na máquina Windows e repita o comando
`advplc.exe build src\monitor.prw -o monitor.exe` — mas isso é opcional,
não é o caminho recomendado.

## Configurar

Copie `config.example.json` para `config.json` na mesma pasta do
`advplc.exe`/`monitor.prw` e preencha:

- `iniPath`: caminho completo do `.ini` de conexão do SmartClient na
  máquina Windows (ex: `C:\\totvs\\appserver.ini`).
- `telegramBotToken` / `telegramChatId`: credenciais do bot do Telegram
  que vai mandar os alertas.
- `unidades`: lista dos nomes de seção do `.ini` a vigiar (ex: `TCPSP`,
  `TCPRJ`, ...).
- `intervaloSegundos` / `timeoutMs`: frequência da checagem e timeout
  de cada tentativa de conexão TCP.
- `portaDbaccess` (opcional): porta do dbaccess, igual pra todas as
  unidades — o host usado é o mesmo host do appserver daquela unidade,
  lido do `.ini`. Se essa chave não existir no `config.json`, o dbaccess
  não é checado.
- `licenseServer` (opcional): objeto `{"host": "...", "port": ...}` do
  license server, único pra todo o ambiente (não é por unidade). Se essa
  chave não existir, o license server não é checado.

Alertas de dbaccess saem como `TCPSP dbaccess (host:porta) caiu/voltou`
e de license server como `License Server (host:porta) caiu/voltou`; o
estado de cada um fica guardado em `state.json` sob as chaves
`<UNIDADE>_DBACCESS` e `LICENSE_SERVER`, respectivamente — não colidem
com a chave da própria unidade (appserver).

## Rodar os testes

`tests/monitor_lib_test.prw` cobre `src/monitor_lib.prw` (checagem TCP,
estado, config, log, montagem de mensagem e os ciclos de
`MonProcessarUnidade`/`MonProcessarDbaccess`/`MonProcessarLicenseServer`).
Vários testes (`teste1`, `teste35`, `teste39`, `teste40`...) precisam de
algo escutando em `127.0.0.1:19191` antes de rodar a suite — os demais
testes usam portas que ninguém escuta de propósito, então não precisam
de setup.

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

    advplc.exe run monitor.prw

Fica em loop pra sempre, gerando `monitor.log` (toda checagem) e
`state.json` (último status conhecido de cada unidade) na mesma pasta.
Agende no Task Scheduler do Windows como "ao iniciar o sistema", sem
precisar de serviço Windows — o `Sleep` interno já mantém o processo
vivo. **Importante**: configure "Start in" (diretório de trabalho) da
tarefa agendada pra essa mesma pasta — `config.json`/`state.json`/
`monitor.log` são caminhos relativos, e o Task Scheduler por padrão
inicia em `%windir%\system32`, onde o monitor não vai achar nada e sai
sem avisar em lugar nenhum visível.
