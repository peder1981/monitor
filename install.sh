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

command -v curl >/dev/null 2>&1 || { echo "curl e necessario mas nao foi encontrado" >&2; exit 1; }

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
trap 'rm -rf "$TMPDIR"' EXIT
curl -fsSL -o "$TMPDIR/$PACOTE" "$URL"
tar -xzf "$TMPDIR/$PACOTE" -C "$TMPDIR"
cp "$TMPDIR/MonitorService" "$TMPDIR/MonitorTUI" "$TMPDIR/config.example.json" "$DESTINO/"
chmod +x "$DESTINO/MonitorService" "$DESTINO/MonitorTUI"
[ -x "$DESTINO/MonitorService" ] || { echo "ERRO: MonitorService nao foi instalado corretamente" >&2; exit 1; }
[ -x "$DESTINO/MonitorTUI" ] || { echo "ERRO: MonitorTUI nao foi instalado corretamente" >&2; exit 1; }

echo
echo "Instalado em $DESTINO"
echo
echo "Proximos passos:"
echo "  1. cp $DESTINO/config.example.json $DESTINO/config.json"
echo "  2. Edite $DESTINO/config.json com suas unidades/credenciais"
echo "  3. cd $DESTINO && ./MonitorTUI   # painel interativo"
echo "     (ou ./MonitorService, pra so rodar o loop de checagem em primeiro plano)"
echo
if ! command -v MonitorTUI >/dev/null 2>&1; then
    case ":$PATH:" in
        *":$DESTINO:"*) ;;
        *) echo "Nota: $DESTINO nao esta no seu PATH. Rode com o caminho completo," \
                "ou adicione 'export PATH=\"\$PATH:$DESTINO\"' ao seu shell rc." ;;
    esac
fi
