# Monitor multiplataforma — build Windows/Linux/macOS, instalador e facilitadores

## Contexto

O monitor hoje só é distribuído pra Windows (CI de plataforma única,
`.github/workflows/release.yml`). O operador pediu pacotes pras três
plataformas de desktop mais populares (Windows, Linux, macOS),
publicados como assets de uma release do GitHub (não o recurso
"Packages" — confirmado com o operador: esse serve pra registros de
pacote tipo npm/container, não pra instaladores soltos), com instalador
de verdade pro Windows e um facilitador de instalação (script) pros
outros dois.

Duas descobertas técnicas relevantes, verificadas ao vivo contra o
`advplc` antes desta spec ser escrita:

1. **`GetSrvInfo()[2]`** devolve o nome do SO em tempo de execução —
   `"Windows"`, `"Linux"` ou `"Mac OS"` — permitindo o mesmo `.prw`
   decidir qual comando de SO usar sem precisar de builds separados por
   lógica (só o binário final é que já sai compilado pra cada SO).
2. **O controle de processo do painel (Iniciar/Parar/Status) hoje é
   100% específico do Windows** (`cmd /c start`, `tasklist`,
   `taskkill`). O equivalente Linux/macOS foi testado e funciona assim:
   - Iniciar desanexado: `ProcRun("sh", {"-c", cCaminho + " > /dev/null 2>&1 & echo lancado"}, bCallback)`.
     Importante: `WaitRun` não serve aqui — ele faz split ingênuo por
     espaço no comando (sem noção de aspas) antes de chamar o SO, então
     qualquer argumento com espaço quebra; `ProcRun` recebe os
     argumentos já como array, sem esse problema.
   - Sem redirecionar a saída do processo filho pra `/dev/null`, o
     `ProcRun` **bloqueia** pelo tempo de vida inteiro do processo
     filho, mesmo ele estando em segundo plano (`&`) — porque o filho
     herda o mesmo pipe de stdout que o pai está lendo, e o pipe só
     fecha quando todo mundo que o segura também fecha. Com o
     redirecionamento, `ProcRun` retorna em ~25ms, como esperado.
   - Status: `ProcRun("pgrep", {"-f", cNomeProcesso}, bCallback)` —
     saída não-vazia (uma ou mais linhas de PID) = rodando.
   - Parar: `ProcRun("pkill", {"-f", cNomeProcesso}, ...)`.
   - `pgrep`/`pkill` existem tanto no Linux quanto no macOS (BSD
     userland) — o mesmo código serve pras duas plataformas "não
     Windows".

## Decisões de escopo (confirmadas com o operador)

- **Onde publicar**: GitHub Releases (mesmo mecanismo já usado pro
  `v0.1.0`), não o recurso GitHub Packages.
- **Controle de processo cross-platform**: adaptado de verdade pra
  cada SO (não desabilitado fora do Windows) — as opções
  Iniciar/Parar/Status do painel funcionam nas três plataformas.
- **Facilitador Linux/macOS**: só um script de instalação simples
  (baixa, copia, dá permissão de execução, imprime os próximos
  passos) — **sem** integração com `systemd`/`launchd` nesta versão;
  ligar o serviço no boot continua sendo responsabilidade do operador
  (documentado, não automatizado), mesma filosofia já usada pro Task
  Scheduler do Windows.
- **Instalador Windows**: Inno Setup, seguindo o precedente já
  validado no projeto irmão `GesCon` — instala em `{autopf}\
  MonitorProtheus` (Program Files) com `PrivilegesRequired=admin` e
  `Permissions: users-modify` na pasta inteira, pra `config.json`/
  `state.json`/`monitor.log` (escritos pelo próprio programa, caminhos
  relativos, do lado do `.exe`) funcionarem sem precisar rodar como
  administrador depois da instalação — o mesmo problema de escrita em
  Program Files que o `GesCon` já resolveu, mesma solução.

## Arquitetura

### Build (CI)

`.github/workflows/release.yml` passa de um job único (`windows-latest`)
pra uma matriz de 3 plataformas, no mesmo padrão do `release.yml` do
`GesCon`:

| SO | Runner | Extensão do binário | Dependência extra |
|---|---|---|---|
| Windows | `windows-latest` | `.exe` | nenhuma |
| Linux | `ubuntu-latest` | (sem extensão) | `libgl1-mesa-dev xorg-dev` (Fyne é linkado mesmo sem uso — já documentado no README atual) |
| macOS | `macos-latest` | (sem extensão) | nenhuma |

Cada plataforma gera `MonitorService[.exe]` e `MonitorTUI[.exe]`, mais
`config.example.json` — no Windows também `abrir-painel.bat`. Cada
plataforma é empacotada num arquivo próprio (`monitor-windows-amd64.zip`,
`monitor-linux-amd64.tar.gz`, `monitor-darwin-arm64.tar.gz`) e publicada
como asset da mesma release.

### Controle de processo cross-platform

Em `src/monitor_tui_lib.prw`, cada uma das três funções
(`MonTuiIniciarServico`, `MonTuiPararServico`,
`MonTuiVerificarServicoRodando`) passa a checar `GetSrvInfo()[2]` e
ramificar:

- `"Windows"` → comportamento atual, inalterado.
- qualquer outra coisa (`"Linux"`/`"Mac OS"`) → `ProcRun` com
  `sh -c`/`pgrep`/`pkill`, como descrito acima.

`MonTuiProcessoEstaRodando` (a função pura já testada) continua
servindo só o caminho Windows (decide "achou o nome do processo na
saída do `tasklist`"); o caminho Unix ganha sua própria checagem — a
saída do `pgrep` já é diretamente "tem PID = tá rodando, vazio = não
tá" — mais simples que a lógica do `tasklist`, não precisa da mesma
função de decisão.

### Instalador Windows (Inno Setup)

Novo `installer/monitor.iss`, adaptado do `installer/gescon.iss` do
`GesCon`: instala os 4 arquivos Windows em `{autopf}\MonitorProtheus`,
cria atalho no Menu Iniciar apontando pra `abrir-painel.bat` (nunca
direto pro `.exe`, mesma razão documentada no README: sem terminal
anexado o AdvPP abre uma janela Fyne em vez do console), oferece abrir
o painel ao final da instalação. Compilado na mesma etapa de CI do
Windows (`choco install innosetup`, mesmo padrão do `GesCon`), publicado
como asset extra (`Monitor-Setup-x.y.z.exe`) na mesma release.

### Facilitador Linux/macOS (`install.sh`)

Novo `install.sh` na raiz do repo, no mesmo espírito do `install.sh` do
próprio AdvPP (curl-pipe-sh): detecta SO (`uname -s`) e arquitetura
(`uname -m`), baixa o `.tar.gz` certo da última release via `curl`,
extrai `MonitorService`/`MonitorTUI`/`config.example.json` pra
`~/.local/bin` (ou outro diretório passado por variável de ambiente),
dá permissão de execução, e imprime um resumo dos próximos passos
(copiar `config.example.json` pra `config.json`, editar, rodar
`MonitorTUI`). Sem privilégio de root — instala só pro usuário atual.

## Testes

- Controle de processo cross-platform: a lógica de decisão
  (`MonTuiProcessoEstaRodando`, Windows) já tem teste automatizado; o
  caminho `pgrep`/`ProcRun` novo é testável neste próprio ambiente
  Linux de desenvolvimento (ao contrário do caminho Windows, que só dá
  pra testar de verdade lá) — a task de implementação escreve um teste
  real usando um processo de vida curta (`sleep`) como alvo.
- CI de 3 plataformas: só dá pra validar de verdade rodando o workflow
  numa tag real (like já fizemos pro `v0.1.0`) — verificação manual,
  não automatizada neste repositório.
- Instalador Inno Setup e `install.sh`: também só verificáveis de
  fato rodando numa máquina real de cada SO — o `install.sh` tem sua
  sintaxe validada com `shellcheck`/`bash -n` como verificação mínima
  automatizável.

## Fora de escopo

- Integração com `systemd`/`launchd` no facilitador de instalação —
  registrado como decisão explícita do operador, não uma omissão.
- Assinatura de código (code signing) do instalador Windows ou dos
  binários macOS (Gatekeeper vai reclamar de binário não assinado) —
  não pedido, ficaria pra uma versão futura se isso incomodar na
  prática.
- Empacotamento via gerenciador de pacote nativo (`.deb`, Homebrew
  formula, `winget`/Chocolatey) — o pedido foi por "facilitadores",
  não integração com gerenciador de pacotes; um script de instalação
  simples atende o pedido sem esse investimento extra.
