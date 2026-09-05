# Monitor de Unidades Protheus

Vigia o broker TCP (SmartClient) de cada unidade Protheus listada num
`.ini` de conexão existente, e avisa no Telegram quando uma unidade cai
ou volta. Opcionalmente também vigia o dbaccess de cada unidade (mesmo
host do appserver, porta configurável) e um license server centralizado
(único para todo o ambiente) — ver `portaDbaccess`/`licenseServer` em
"Configurar" abaixo.

## Instalar

1. Baixe o zip mais recente da aba Releases deste repositório
   (`monitor-windows-amd64`) — contém `MonitorService.exe`,
   `MonitorTUI.exe`, `config.example.json` e `abrir-painel.bat`, todos
   já compilados. Nenhum toolchain (MinGW, Go, AdvPP) precisa ser
   instalado na máquina Windows que vai rodar o monitor.
2. Copie os quatro arquivos pra uma pasta fixa (ex:
   `C:\MonitorProtheus\`).
3. Copie `config.example.json` para `config.json` na mesma pasta e
   preencha (ver "Configurar" abaixo).

## Configurar

Copie `config.example.json` para `config.json` na mesma pasta dos executáveis
e preencha:

- `iniPath`: caminho completo do `.ini` de conexão do SmartClient na
  máquina Windows (ex: `C:\\totvs\\appserver.ini`).
- `telegramBotToken` / `telegramChatId`: credenciais do bot do Telegram
  que vai mandar os alertas.
- `unidades`: lista dos nomes de seção do `.ini` a vigiar (ex: `TCPSP`,
  `TCPRJ`, ...).
- `intervaloSegundos` / `timeoutMs`: frequência da checagem e timeout
  de cada tentativa de conexão TCP.
- `portaWebapp`: porta HTTP fixa (ex: `8090`) usada pra checar o appserver
  de cada unidade — o host continua vindo do `.ini` (`Server=` da seção),
  só a porta muda de "a porta do `.ini`" pra essa, fixa. A checagem faz um
  `GET` simples e mede quanto tempo demorou pra responder; qualquer status
  HTTP abaixo de 500 conta como "no ar".
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

- **Serviço de fundo**: agende `MonitorService.exe` no Task Scheduler
  do Windows como "ao iniciar o sistema", com "Start in" apontando pra
  essa mesma pasta (os arquivos `config.json`/`state.json`/
  `monitor.log` são caminhos relativos). Sobrevive a reboot e a troca
  de sessão RDP.
- **Painel de controle**: sempre abra **`abrir-painel.bat`**, nunca
  `MonitorTUI.exe` diretamente — o `.bat` garante que a interface abre
  dentro de um console de texto; aberto direto (duplo-clique), o
  interpretador entende que deve abrir uma janela gráfica em vez do
  painel ASCII. Do painel dá pra ver o status/latência de cada
  unidade, iniciar/parar o `MonitorService`, e ver as últimas linhas
  do log — tudo com teclado, sem precisar saber nenhum comando.
