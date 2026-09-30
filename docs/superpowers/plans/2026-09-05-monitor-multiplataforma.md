# Monitor multiplataforma — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar o controle de processo do painel (Iniciar/Parar/Status) funcional em Windows, Linux e macOS; estender a CI pra compilar e empacotar as três plataformas; adicionar um instalador Inno Setup pro Windows; adicionar um script de instalação (`install.sh`) pra Linux/macOS; publicar tudo como assets de uma release do GitHub.

**Architecture:** `src/monitor_tui_lib.prw` ganha detecção de SO em runtime (`GetSrvInfo()[2]`) dentro das três funções de controle de processo já existentes, ramificando pra comandos Windows (já implementados) ou Linux/macOS (`ProcRun`+`sh -c`/`pgrep`/`pkill`, testado e comprovado neste plano). `.github/workflows/release.yml` passa de um job único (`windows-latest`) pra uma matriz de 3 plataformas que empacota cada uma num arquivo próprio, mais um job extra só de Windows que gera o instalador Inno Setup a partir do pacote já buildado. `install.sh` na raiz do repo, no mesmo estilo curl-pipe-sh que o próprio AdvPP já usa, detecta SO/arquitetura e baixa o pacote certo da última release.

**Tech Stack:** AdvPL via AdvPP (`advplc`, pinado em `v3.0.4` — ver `ADVPP_VERSION`, inalterado). Nativas novas usadas: `GetSrvInfo()` (detecção de SO em runtime — índice 2 do array devolve `"Windows"`/`"Linux"`/`"Mac OS"`), `Chmod` (permissão de execução, usado só em teste). GitHub Actions: matriz de 3 runners (`windows-latest`/`ubuntu-latest`/`macos-latest`), Inno Setup 6 via Chocolatey (mesmo padrão do projeto irmão `GesCon`).

**Spec:** `docs/superpowers/specs/2026-09-05-monitor-multiplataforma.md`

## Global Constraints

- Publicar como assets de **GitHub Releases** (mesmo mecanismo do `v0.1.0`), não o recurso GitHub Packages — decisão explícita do operador.
- Controle de processo do painel funciona de verdade nas três plataformas (não fica desabilitado fora do Windows).
- Facilitador Linux/macOS é só um script de instalação — **sem** integração com `systemd`/`launchd` nesta versão.
- `pgrep`/`pkill` usam `-x` (nome exato do processo — até 15 caracteres no Linux, `MonitorService` tem 14, cabe), **não** `-f` (linha de comando completa) — `-f` casa com qualquer processo cujo argv contenha a substring, incluindo o próprio shell que estiver rodando o teste (achado real desta sessão: `pkill -f MonitorServiceFake` matou o processo bash que estava rodando o teste, porque o texto do próprio comando de teste continha essa string).
- `ProcRun` (não `WaitRun`) é a nativa certa pra qualquer comando com argumento que precise ficar intacto (array de argv, sem split ingênuo por espaço) — `WaitRun` já documentado como inadequado pra isso em achado anterior.
- Um processo em segundo plano (`&`) lançado via `ProcRun("sh", {"-c", "... & echo ..."}, callback)` só retorna rápido se a saída do processo filho for redirecionada pra longe do pipe que o `ProcRun` está lendo (`> /dev/null 2>&1`) — sem isso, `ProcRun` bloqueia pela vida inteira do processo filho, mesmo ele estando "em segundo plano" do ponto de vista do shell.

---

## Arquivos deste plano

```
monitor/
  src/
    monitor_tui_lib.prw        # modificado: controle de processo cross-platform
    monitor_tui.prw            # modificado: chamada a MonTuiIniciarServico sem extensao
  tests/
    monitor_tui_lib_test.prw   # modificado: testes do caminho Linux/macOS (real neste ambiente)
  installer/
    monitor.iss                # novo: instalador Windows (Inno Setup)
  install.sh                   # novo: facilitador de instalacao Linux/macOS
  .github/workflows/
    release.yml                # modificado: matriz de 3 plataformas + job do instalador
  README.md                    # modificado: instrucoes de instalacao por plataforma
```

---

### Task 1: Controle de processo cross-platform (`monitor_tui_lib.prw`)

**Files:**
- Modify: `src/monitor_tui_lib.prw` (`MonTuiIniciarServico`, `MonTuiPararServico`, `MonTuiVerificarServicoRodando`)
- Modify: `src/monitor_tui.prw` (chamada a `MonTuiIniciarServico`)
- Modify: `tests/monitor_tui_lib_test.prw`

**Interfaces:**
- Produces (mudança de contrato): `MonTuiIniciarServico(cNomeBase)` — `cNomeBase` agora é o nome **sem extensão** (ex: `"MonitorService"`, nunca `"MonitorService.exe"`) — a função decide sozinha se acrescenta `.exe` (Windows) ou `./` (Linux/macOS) por baixo, usando `GetSrvInfo()[2]` pra saber em qual SO está rodando.
- `MonTuiPararServico()`/`MonTuiVerificarServicoRodando()` continuam sem parâmetro (nome do processo, `"MonitorService"`, fica interno à função — igual já era antes).
- `MonTuiProcessoEstaRodando(cSaidaTasklist)` (já existe, testada) **não muda** — continua sendo só a lógica pura do caminho Windows.

- [ ] **Step 1: Escrever os testes do caminho Linux/macOS**

Este ambiente de desenvolvimento é Linux — os testes abaixo exercitam de
verdade o `ProcRun`+`sh`/`pgrep`/`pkill`, ao contrário do caminho Windows
(que já tem sua própria cobertura, indiretamente, via
`MonTuiProcessoEstaRodando`). Adicione ao final de
`tests/monitor_tui_lib_test.prw`, antes do
`ConOut("MONITOR_TUI_LIB_TEST_FIM")`:

```advpl
    // testeUnix1-4: controle de processo no caminho nao-Windows (roda de
    // verdade neste ambiente de dev/CI Linux). "MonitorService" tem 14
    // caracteres -- cabe no limite de 15 do "comm" do Linux pro `pgrep -x`
    // funcionar sem avisar de truncamento. Sobe um script de vida curta
    // (sleep 5) com esse nome, no lugar do binario real, so pra validar
    // o fluxo iniciar/verificar/parar/verificar.
    Local cSO := GetSrvInfo()[2]
    ConOut("testeUnix1_so_nao_eh_vazio=" + IIF(cSO != "", "SIM", "NAO"))

    If cSO != "Windows"
        Local lChmodOk

        MemoWrite("MonitorService", "#!/bin/sh" + Chr(10) + "sleep 5" + Chr(10))
        lChmodOk := Chmod("MonitorService", 493) // 0755 em decimal
        ConOut("testeUnix2_chmod_ok=" + IIF(lChmodOk, "SIM", "NAO"))

        MonTuiIniciarServico("MonitorService")
        ConOut("testeUnix3_rodando_apos_iniciar=" + IIF(MonTuiVerificarServicoRodando(), "SIM", "NAO"))

        MonTuiPararServico()
        Sleep(500)
        ConOut("testeUnix4_rodando_apos_parar=" + IIF(MonTuiVerificarServicoRodando(), "SIM", "NAO"))

        FErase("MonitorService")
    EndIf
```

- [ ] **Step 2: Rodar e confirmar que o comportamento atual não bate com o esperado**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected: `testeUnix1_so_nao_eh_vazio=SIM` passa (já que `GetSrvInfo()`
já existe e não depende desta task), mas `testeUnix3_rodando_apos_iniciar`
sai `NAO` (`MonTuiIniciarServico`/`MonTuiVerificarServicoRodando` ainda só
sabem falar Windows — `WaitRun("cmd /c start MonitorService")` não faz
nada útil num Linux, e `tasklist` provavelmente nem existe no PATH, então
`ProcRun` retorna sem achar nada).

- [ ] **Step 3: Implementar em `src/monitor_tui_lib.prw`**

Substitua as três funções existentes (`MonTuiIniciarServico`,
`MonTuiPararServico`, `MonTuiVerificarServicoRodando`) por:

```advpl
User Function MonTuiIniciarServico(cNomeBase)
    Local bNoop := {|cLinha| Nil}

    If GetSrvInfo()[2] == "Windows"
        WaitRun("cmd /c start " + cNomeBase + ".exe")
    Else
        ProcRun("sh", {"-c", "./" + cNomeBase + " > /dev/null 2>&1 & echo lancado"}, bNoop)
    EndIf
Return Nil

User Function MonTuiPararServico()
    Local bNoop := {|cLinha| Nil}

    If GetSrvInfo()[2] == "Windows"
        WaitRun("taskkill /IM MonitorService.exe /F")
    Else
        ProcRun("pkill", {"-x", "MonitorService"}, bNoop)
    EndIf
Return Nil

User Function MonTuiVerificarServicoRodando()
    Local cSaida := ""
    Local bAcumula := {|cLinha| cSaida += cLinha + Chr(10)}

    If GetSrvInfo()[2] == "Windows"
        ProcRun("tasklist", {"/FI", "IMAGENAME eq MonitorService.exe", "/FO", "CSV", "/NH"}, bAcumula)
        Return MonTuiProcessoEstaRodando(cSaida)
    EndIf

    ProcRun("pgrep", {"-x", "MonitorService"}, bAcumula)
Return Len(AllTrim(cSaida)) > 0
```

Mantenha `MonTuiProcessoEstaRodando` e `MonTuiLinhaStatus`/
`MonTuiMontarTabela` exatamente como estão — nenhuma das duas muda.

- [ ] **Step 4: Atualizar a chamada em `src/monitor_tui.prw`**

Troque a linha (dentro do `Do Case`, `Case nOpcao == 1`):

```advpl
            MonTuiIniciarServico("MonitorService.exe")
```

por:

```advpl
            MonTuiIniciarServico("MonitorService")
```

- [ ] **Step 5: Rodar e confirmar sucesso**

```bash
cd ~/Projetos/monitor/tests
~/Projetos/AdvPP/advplc run monitor_tui_lib_test.prw
```

Expected (linhas novas, e todas as anteriores — teste1 até teste15 —
continuando iguais):
```
testeUnix1_so_nao_eh_vazio=SIM
testeUnix2_chmod_ok=SIM
testeUnix3_rodando_apos_iniciar=SIM
testeUnix4_rodando_apos_parar=NAO
MONITOR_TUI_LIB_TEST_FIM
```

Confirme também com `advplc check src/monitor_tui.prw` que o arquivo
ainda compila (a mudança de Step 4 é só um literal de string, mas syntax
check é rápido e não custa nada).

- [ ] **Step 6: Commit**

```bash
cd ~/Projetos/monitor
git add src/monitor_tui_lib.prw src/monitor_tui.prw tests/monitor_tui_lib_test.prw
git commit -m "feat: controle de processo do painel funciona em Linux/macOS, nao so Windows"
```

---

### Task 2: CI de 3 plataformas + empacotamento

**Files:**
- Modify: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `src/monitor.prw`, `src/monitor_tui.prw` (Task 1, sem mudança de interface externa relevante pra este task).
- Produces: 3 artefatos de build (`monitor-windows-amd64`, `monitor-linux-amd64`, `monitor-darwin-arm64`), cada um contendo um pacote (`.zip` no Windows, `.tar.gz` nos outros dois) com `MonitorService[.exe]`, `MonitorTUI[.exe]` e `config.example.json` (mais `abrir-painel.bat` só no Windows) — consumido pela Task 3 (job do instalador, que baixa o artefato Windows).

- [ ] **Step 1: Reescrever `.github/workflows/release.yml`**

```yaml
name: Release

on:
  push:
    tags: ["v*"]

permissions:
  contents: write

env:
  GO_VERSION: "1.24"

jobs:
  # O advplc build embute Fyne no stub mesmo pra um programa console/TUI
  # como este, e precisa de CGO pra linkar -- por isso cada plataforma
  # compila no seu proprio runner (mesmo padrao do GesCon), nao cross-
  # compile de um so.
  build:
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            plataforma: linux-amd64
            ext: ""
            pacote: monitor-linux-amd64.tar.gz
          - os: windows-latest
            plataforma: windows-amd64
            ext: ".exe"
            pacote: monitor-windows-amd64.zip
          - os: macos-latest
            plataforma: darwin-arm64
            ext: ""
            pacote: monitor-darwin-arm64.tar.gz
    runs-on: ${{ matrix.os }}
    steps:
      - name: Checkout monitor
        uses: actions/checkout@v4
        with:
          path: monitor

      - name: Le a versao do AdvPP
        id: advpp
        shell: bash
        run: echo "versao=v$(tr -d ' \n\r' < monitor/ADVPP_VERSION)" >> "$GITHUB_OUTPUT"

      - name: Checkout AdvPP (compilador)
        uses: actions/checkout@v4
        with:
          repository: peder1981/AdvPP
          ref: ${{ steps.advpp.outputs.versao }}
          path: AdvPP

      - uses: actions/setup-go@v5
        with:
          go-version: ${{ env.GO_VERSION }}

      - name: Dependencias do Fyne (Linux)
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y libgl1-mesa-dev xorg-dev

      - name: Build advplc
        shell: bash
        run: |
          cd AdvPP
          go build -o "$RUNNER_TEMP/advplc${{ matrix.ext }}" ./cmd/advplc

      - name: Build MonitorService e MonitorTUI
        shell: bash
        env:
          ADVPP_SRC: ${{ github.workspace }}/AdvPP
        run: |
          cd monitor
          "$RUNNER_TEMP/advplc${{ matrix.ext }}" build src/monitor.prw -o "MonitorService${{ matrix.ext }}"
          "$RUNNER_TEMP/advplc${{ matrix.ext }}" build src/monitor_tui.prw -o "MonitorTUI${{ matrix.ext }}"

      - name: Empacota (Windows)
        if: runner.os == 'Windows'
        shell: bash
        run: |
          cd monitor
          7z a -tzip "${{ matrix.pacote }}" MonitorService.exe MonitorTUI.exe config.example.json abrir-painel.bat

      - name: Empacota (Linux/macOS)
        if: runner.os != 'Windows'
        shell: bash
        run: |
          cd monitor
          tar -czf "${{ matrix.pacote }}" MonitorService MonitorTUI config.example.json

      - uses: actions/upload-artifact@v4
        with:
          name: monitor-${{ matrix.plataforma }}
          path: monitor/${{ matrix.pacote }}

  release:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artefatos
      - name: Publica os binarios no release
        uses: softprops/action-gh-release@v2
        with:
          files: artefatos/**/*
          generate_release_notes: true
```

- [ ] **Step 2: Verificação manual do workflow**

Não roda de fato neste ambiente (exige push de tag real pro GitHub).
Ao integrar este plano: `git tag v0.2.0 && git push origin v0.2.0`, depois
acompanhar a aba Actions até o fim, e confirmar que os três artefatos
(`monitor-windows-amd64.zip`, `monitor-linux-amd64.tar.gz`,
`monitor-darwin-arm64.tar.gz`) aparecem na release publicada.

- [ ] **Step 3: Commit**

```bash
cd ~/Projetos/monitor
git add .github/workflows/release.yml
git commit -m "feat: CI builda e empacota Windows, Linux e macOS"
```

---

### Task 3: Instalador Windows (Inno Setup)

**Files:**
- Create: `installer/monitor.iss`
- Modify: `.github/workflows/release.yml` (novo job `installer-windows`)

**Interfaces:**
- Consumes: o artefato `monitor-windows-amd64` (zip) produzido pela Task 2.
- Produces: artefato `monitor-installer-windows` (`Monitor-Setup-<versao>.exe`), publicado pelo job `release` já existente (que já pega `artefatos/**/*` — não precisa de mudança no job `release` em si).

- [ ] **Step 1: Criar `installer/monitor.iss`**

```iss
; installer/monitor.iss -- instalador Windows do Monitor Protheus (Inno Setup 6).
;
; Compilar:  ISCC.exe /DAppVersion=1.0.9 installer\monitor.iss
; Espera, ao lado deste .iss (na raiz do checkout): MonitorService.exe,
; MonitorTUI.exe, config.example.json, abrir-painel.bat.
;
; Instala em Program Files (precisa de admin uma vez, na instalacao) mas
; libera escrita pra Usuarios na pasta inteira -- o proprio monitor grava
; config.json/state.json/monitor.log ali, caminho relativo ao lado do
; .exe, e Program Files por padrao nao aceita escrita de usuario comum.
; Mesmo problema e mesma solucao ja usados no projeto irmao GesCon.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

[Setup]
AppId={{A1B2C3D4-5E6F-4A7B-8C9D-0E1F2A3B4C5D}
AppName=Monitor Protheus
AppVersion={#AppVersion}
AppVerName=Monitor Protheus {#AppVersion}
AppPublisher=Monitor Protheus
DefaultDirName={autopf}\MonitorProtheus
DefaultGroupName=Monitor Protheus
OutputDir=.
OutputBaseFilename=Monitor-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayName=Monitor Protheus {#AppVersion}
UninstallDisplayIcon={app}\MonitorTUI.exe

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "MonitorService.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "MonitorTUI.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "config.example.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "abrir-painel.bat"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
; config.json/state.json/monitor.log sao escritos pelo proprio monitor
; direto nesta pasta -- sem isso, um usuario comum nao consegue gravar
; em Program Files depois da instalacao.
Name: "{app}"; Permissions: users-modify

[Icons]
Name: "{group}\Monitor Protheus"; Filename: "{app}\abrir-painel.bat"
Name: "{group}\Desinstalar o Monitor Protheus"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Monitor Protheus"; Filename: "{app}\abrir-painel.bat"

[Run]
Filename: "{app}\abrir-painel.bat"; Description: "Abrir o painel agora"; \
    Flags: nowait postinstall skipifsilent
```

- [ ] **Step 2: Verificação sintática mínima**

Este arquivo `.iss` só compila de verdade com o Inno Setup (Windows) —
não dá pra rodar `ISCC.exe` neste ambiente Linux. Verificação possível
aqui: conferir visualmente que todas as seções (`[Setup]`, `[Languages]`,
`[Files]`, `[Dirs]`, `[Icons]`, `[Run]`) têm a sintaxe `Chave: valor;`
consistente com o `installer/gescon.iss` do projeto irmão (mesmo formato,
já usado e comprovado em produção lá). A verificação real fica pro
Step 2 da Task 2 (a mesma tag de teste dispara também este job).

- [ ] **Step 3: Adicionar o job `installer-windows` em `.github/workflows/release.yml`**

Insira este novo job entre `build` e `release`:

```yaml
  installer-windows:
    needs: build
    runs-on: windows-latest
    steps:
      - name: Checkout monitor
        uses: actions/checkout@v4

      - uses: actions/download-artifact@v4
        with:
          name: monitor-windows-amd64
          path: dist

      - name: Extrai o zip pro instalador ler os arquivos soltos
        shell: bash
        run: |
          cd dist
          7z x monitor-windows-amd64.zip
          cp MonitorService.exe MonitorTUI.exe config.example.json abrir-painel.bat ..

      - name: Instalador Windows (Inno Setup)
        shell: bash
        run: |
          choco install innosetup --no-progress -y
          VERSAO="${GITHUB_REF_NAME#v}"
          "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" //DAppVersion="$VERSAO" installer/monitor.iss
          ls -la Monitor-Setup-*.exe

      - uses: actions/upload-artifact@v4
        with:
          name: monitor-installer-windows
          path: Monitor-Setup-*.exe
```

E troque a linha `needs: build` do job `release` (já existente) por
`needs: [build, installer-windows]`, pra release esperar os dois antes de
publicar.

- [ ] **Step 4: Verificação manual do workflow**

Coberta pelo mesmo push de tag do Step 2 da Task 2 — confirme, além dos
três pacotes, que `Monitor-Setup-<versao>.exe` também aparece como asset
da release.

- [ ] **Step 5: Commit**

```bash
cd ~/Projetos/monitor
git add installer/monitor.iss .github/workflows/release.yml
git commit -m "feat: instalador Windows via Inno Setup"
```

---

### Task 4: `install.sh` (Linux/macOS) e README final

**Files:**
- Create: `install.sh`
- Modify: `README.md`

**Interfaces:**
- Consumes: os pacotes `.tar.gz` publicados pela Task 2 (via GitHub Releases API, `latest`).

- [ ] **Step 1: Criar `install.sh`**

```sh
#!/bin/sh
# install.sh -- baixa e instala o Monitor Protheus (Linux/macOS).
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/peder1981/monitor/master/install.sh | sh
#
# Detecta SO/arquitetura, baixa o pacote da ultima release do GitHub,
# extrai MonitorService/MonitorTUI/config.example.json pro diretorio de
# destino (por padrao ~/.local/bin) e da permissao de execucao. Sem
# privilegio de root -- instala so pro usuario atual.
set -e

DESTINO="${MONITOR_INSTALL_DIR:-$HOME/.local/bin}"
REPO="peder1981/monitor"

case "$(uname -s)" in
    Linux)  PLATAFORMA="linux-amd64" ;;
    Darwin) PLATAFORMA="darwin-arm64" ;;
    *)
        echo "SO nao suportado por este instalador: $(uname -s)" >&2
        echo "Baixe manualmente em https://github.com/$REPO/releases" >&2
        exit 1
        ;;
esac

PACOTE="monitor-${PLATAFORMA}.tar.gz"
URL="https://github.com/$REPO/releases/latest/download/$PACOTE"

echo "install.sh: baixando $URL"
mkdir -p "$DESTINO"
TMPDIR=$(mktemp -d)
curl -fsSL -o "$TMPDIR/$PACOTE" "$URL"
tar -xzf "$TMPDIR/$PACOTE" -C "$TMPDIR"
cp "$TMPDIR/MonitorService" "$TMPDIR/MonitorTUI" "$TMPDIR/config.example.json" "$DESTINO/"
chmod +x "$DESTINO/MonitorService" "$DESTINO/MonitorTUI"
rm -rf "$TMPDIR"

echo
echo "Instalado em $DESTINO"
echo
echo "Proximos passos:"
echo "  1. cp $DESTINO/config.example.json $DESTINO/config.json"
echo "  2. Edite $DESTINO/config.json com suas unidades/credenciais"
echo "  3. cd $DESTINO && ./MonitorTUI   # painel interativo"
echo "     (ou ./MonitorService, pra so rodar o loop de checagem em primeiro plano)"
echo
if ! command -v "$(basename "$DESTINO")" >/dev/null 2>&1; then
    case ":$PATH:" in
        *":$DESTINO:"*) ;;
        *) echo "Nota: $DESTINO nao esta no seu PATH. Rode com o caminho completo," \
                "ou adicione 'export PATH=\"\$PATH:$DESTINO\"' ao seu shell rc." ;;
    esac
fi
```

- [ ] **Step 2: Verificação sintática**

```bash
cd ~/Projetos/monitor
bash -n install.sh && echo "sintaxe OK"
shellcheck install.sh || echo "shellcheck nao instalado ou com avisos -- revisar manualmente"
chmod +x install.sh
```

Expected: `bash -n` não deve reportar erro nenhum (`sintaxe OK`). Se
`shellcheck` estiver disponível e apontar algo real (não estilístico),
corrija antes de prosseguir; avisos puramente estilísticos podem ser
ignorados.

- [ ] **Step 3: Atualizar `README.md`**

Reescreva a seção "Instalar" (que hoje só descreve o zip do Windows) pra
cobrir as três plataformas:

```markdown
## Instalar

**Windows**: baixe `Monitor-Setup-x.y.z.exe` da aba Releases e rode —
instala em `Program Files\MonitorProtheus`, cria atalho no Menu Iniciar
apontando pro painel. Alternativa sem instalador: baixe
`monitor-windows-amd64.zip`, extraia numa pasta de sua escolha.

**Linux/macOS**: rode

    curl -fsSL https://raw.githubusercontent.com/peder1981/monitor/master/install.sh | sh

Instala em `~/.local/bin` (sem precisar de root). Pra escolher outro
diretório: `MONITOR_INSTALL_DIR=/outro/caminho curl -fsSL ... | sh`.
Alternativa sem o script: baixe `monitor-linux-amd64.tar.gz` ou
`monitor-darwin-arm64.tar.gz` da aba Releases e extraia manualmente.

Nenhuma das três plataformas precisa instalar toolchain nenhum (MinGW,
Go, AdvPP) — os binários já saem compilados da CI.
```

Ajuste também a seção "Rodar" pra mencionar que, fora do Windows, não
existe um equivalente do Task Scheduler documentado nesta versão —
adicione uma frase curta: "Em Linux/macOS, deixar o `MonitorService`
sempre ligado no boot (via `systemd`/`launchd`/`cron @reboot`) fica por
sua conta nesta versão — não temos um facilitador pra isso ainda,
só pro Windows (Task Scheduler)."

- [ ] **Step 4: Commit**

```bash
cd ~/Projetos/monitor
git add install.sh README.md
git commit -m "feat: install.sh para Linux/macOS, README com instrucoes das 3 plataformas"
```

---

## Self-Review (feito ao escrever este plano)

- **Cobertura da spec:** detecção de SO + controle de processo cross-platform (Task 1, testado de verdade no caminho Linux deste ambiente), CI de 3 plataformas com empacotamento (Task 2), instalador Windows Inno Setup (Task 3), facilitador Linux/macOS (Task 4). Itens "fora de escopo" da spec (systemd/launchd, code signing, `.deb`/Homebrew/winget) — nenhuma task tenta implementá-los, como esperado.
- **Placeholders:** nenhum "TBD"/"implementar depois" — todo passo tem conteúdo completo. Onde a verificação real só é possível numa máquina/CI que este ambiente não tem (workflow do GitHub Actions, `.iss` do Inno Setup, `install.sh` baixando de uma release que ainda não existe), o plano diz isso explicitamente e prescreve uma verificação manual concreta.
- **Consistência de tipos:** `MonTuiIniciarServico` muda de contrato (recebe nome sem extensão) de forma consistente entre a Task 1 (implementação) e sua única chamadora, `src/monitor_tui.prw` (também atualizada na mesma task). O nome do processo (`"MonitorService"`, 14 caracteres) é o mesmo usado em `MonTuiPararServico`/`MonTuiVerificarServicoRodando` (Task 1) e nos nomes de arquivo gerados pela CI (Task 2) e pelo instalador (Task 3) — sem inconsistência de nome entre as tasks.
