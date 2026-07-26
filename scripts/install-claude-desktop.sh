#!/usr/bin/env bash
# install-claude-desktop.sh — branche ce serveur MCP dans Claude Desktop.
#
# Fusionne (sans rien écraser) une entrée « google-multi-account » dans le
# fichier de config de Claude Desktop, en pointant sur bin/google-mcp de CE
# clone (chemin absolu résolu tout seul) avec GWSA_CLIENT=claude-desktop.
#
# Usage :
#   ./scripts/install-claude-desktop.sh                 # branche (ou met à jour)
#   ./scripts/install-claude-desktop.sh --print         # dry-run : montre sans écrire
#   ./scripts/install-claude-desktop.sh --name autre    # nom d'entrée personnalisé
#   ./scripts/install-claude-desktop.sh --port 4881     # broker dédié à ce couloir
#   ./scripts/install-claude-desktop.sh --config PATH    # config Desktop non standard
#
# Brancher DEUX versions à la fois demande DEUX ports : le serveur MCP parle au
# broker qui écoute sur GWSA_BROKER_PORT, et le premier broker démarré sert tous
# ceux qui visent son port. Sans port distinct, le nom de l'entrée ment sur la
# version qui répond (fiche 0025) — le script refuse donc ce cas.
#
# Idempotent : relançable sans risque. Préserve les autres serveurs MCP,
# fait un backup horodaté avant toute modification, écriture atomique.
# Après coup : redémarrer Claude Desktop.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MCP_BIN="$REPO_ROOT/bin/google-mcp"
SERVER_NAME="google-multi-account"
GWSA_CLIENT="claude-desktop"
BROKER_PORT="4878"
PYTHON="/usr/bin/python3"
[[ -x "$PYTHON" ]] || PYTHON="$(command -v python3 || true)"

# ── affichage (même convention que provision-gcp.sh) ─────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

# ── arguments ────────────────────────────────────────────────────
CONFIG_PATH=""
DRY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print|--dry-run) DRY=1 ;;
    --name) shift; SERVER_NAME="${1:-}" ;;
    --name=*) SERVER_NAME="${1#*=}" ;;
    --port) shift; BROKER_PORT="${1:-}" ;;
    --port=*) BROKER_PORT="${1#*=}" ;;
    --config) shift; CONFIG_PATH="${1:-}" ;;
    --config=*) CONFIG_PATH="${1#*=}" ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu : $1 (voir --help)" ;;
  esac
  shift
done
[[ -n "$SERVER_NAME" ]] || die "--name vide"
[[ "$BROKER_PORT" =~ ^[0-9]+$ ]] && [[ "$BROKER_PORT" -ge 1024 && "$BROKER_PORT" -le 65535 ]] \
  || die "--port doit être un entier entre 1024 et 65535 (reçu : « $BROKER_PORT »)"
[[ -n "$PYTHON" ]] || die "python3 introuvable"

# ── pré-requis : le binaire MCP existe et est exécutable ─────────
[[ -x "$MCP_BIN" ]] || die "binaire MCP absent ou non exécutable : $MCP_BIN"

# ── emplacement de la config Claude Desktop selon l'OS ───────────
if [[ -z "$CONFIG_PATH" ]]; then
  case "$(uname -s)" in
    Darwin) CONFIG_PATH="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
    Linux)  CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
    *) die "OS non géré pour la détection auto : utilise --config <chemin du claude_desktop_config.json>" ;;
  esac
fi

# Version réellement branchée : le fichier VERSION vit à côté du binaire dans une
# copie déployée, et n'existe pas dans un clone de travail (qui vaut donc « dev »).
MCP_VERSION="dev"
[[ -s "$REPO_ROOT/VERSION" ]] && MCP_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"

step "Branchement de « $SERVER_NAME » dans Claude Desktop"
echo "  binaire  : $MCP_BIN"
echo "  version  : $MCP_VERSION"
echo "  broker   : port $BROKER_PORT"
echo "  config   : $CONFIG_PATH"

# ── soft-checks non bloquants ────────────────────────────────────
[[ "$(uname -s)" == "Darwin" && ! -e "/Applications/Claude.app" ]] \
  && warn "Claude.app introuvable dans /Applications — la config sera écrite quand même."

# ── merge JSON idempotent (python : lecture → fusion → écriture) ──
# Le python fait tout le travail sur le fichier et n'imprime qu'un statut
# machine (result=… / backup=… / preview=…) que bash met en forme.
set +e
out="$(
  MCP_BIN="$MCP_BIN" SERVER_NAME="$SERVER_NAME" GWSA_CLIENT="$GWSA_CLIENT" \
  BROKER_PORT="$BROKER_PORT" \
  CONFIG_PATH="$CONFIG_PATH" DRY="$DRY" "$PYTHON" - <<'PY'
import json, os, sys, tempfile, time

DEFAULT_PORT = "4878"

cfg   = os.environ["CONFIG_PATH"]
name  = os.environ["SERVER_NAME"]
port  = os.environ["BROKER_PORT"]
# Le port est écrit MÊME quand c’est celui par défaut : le couloir doit se lire
# dans la config, pas se déduire (fiche 0025).
entry = {"command": os.environ["MCP_BIN"],
         "env": {"GWSA_CLIENT": os.environ["GWSA_CLIENT"],
                 "GWSA_BROKER_PORT": port}}
dry   = bool(os.environ.get("DRY"))

# Lecture tolérante : fichier absent ou vide → objet neuf.
data = {}
if os.path.exists(cfg):
    raw = open(cfg, encoding="utf-8").read().strip()
    if raw:
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            print(f"error=JSON invalide dans {cfg} : {e}")
            sys.exit(3)
        if not isinstance(data, dict):
            print(f"error=racine JSON inattendue (attendu un objet) dans {cfg}")
            sys.exit(3)

servers = data.setdefault("mcpServers", {})
if not isinstance(servers, dict):
    print("error=« mcpServers » n'est pas un objet dans la config existante")
    sys.exit(3)

# Garde-fou du couloir : un AUTRE serveur google-mcp qui vise déjà ce port avec
# un binaire différent. Les deux se partageraient le premier broker démarré, et
# le nom de l’entrée mentirait sur la version qui répond (fiche 0025).
# Les serveurs MCP tiers ne sont pas concernés : seul « google-mcp » est compté.
def rival_port(srv):
    env = srv.get("env") if isinstance(srv, dict) else None
    return (env or {}).get("GWSA_BROKER_PORT", DEFAULT_PORT)


for other, srv in servers.items():
    if other == name or not isinstance(srv, dict):
        continue
    cmd = srv.get("command") or ""
    if os.path.basename(cmd) != "google-mcp" or cmd == entry["command"]:
        continue
    if rival_port(srv) == port:
        print(f"error=le port {port} est déjà pris par l’entrée « {other} » "
              f"({cmd}). Deux versions sur un même port se partagent le premier "
              f"broker démarré : relance avec --port <autre port libre>")
        sys.exit(3)

existed = name in servers
if existed and servers[name] == entry:
    print("result=unchanged")
    sys.exit(0)

servers[name] = entry
rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"

if dry:
    print("result=dry")
    print("preview<<END")
    print(rendered, end="")
    print("END")
    sys.exit(0)

backup = ""
if os.path.exists(cfg):
    backup = f"{cfg}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    with open(backup, "w", encoding="utf-8") as b:
        b.write(open(cfg, encoding="utf-8").read())

cfgdir = os.path.dirname(cfg) or "."   # --config relatif nu → dossier courant
os.makedirs(cfgdir, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=cfgdir, prefix=".cdcfg-")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    f.write(rendered)
os.replace(tmp, cfg)  # écriture atomique

print("result=updated" if existed else "result=created")
if backup:
    print(f"backup={backup}")
PY
)"
rc=$?
set -e

# ── restitue le statut python en message humain ──────────────────
result=""; backup=""; error=""; preview=""; in_preview=""
while IFS= read -r line; do
  if [[ -n "$in_preview" ]]; then
    [[ "$line" == "END" ]] && { in_preview=""; continue; }
    preview+="$line"$'\n'; continue
  fi
  case "$line" in
    result=*)      result="${line#result=}" ;;
    backup=*)      backup="${line#backup=}" ;;
    error=*)       error="${line#error=}" ;;
    preview\<\<END) in_preview=1 ;;
  esac
done <<< "$out"

[[ -n "$error" ]] && die "$error"
[[ "$rc" -ne 0 && -z "$result" ]] && die "échec du merge (code $rc)"

case "$result" in
  unchanged)
    ok "Déjà branché et à jour — rien à faire." ;;
  dry)
    warn "Dry-run (--print) : aucune écriture. Contenu qui SERAIT écrit dans $CONFIG_PATH :"
    echo
    echo "$preview" ;;
  created|updated)
    [[ -n "$backup" ]] && ok "Backup : $backup"
    if [[ "$result" == created ]]; then
      ok "Entrée « $SERVER_NAME » ajoutée."
    else
      ok "Entrée « $SERVER_NAME » mise à jour."
    fi
    echo
    echo "${B}→ Redémarre Claude Desktop${N} pour charger le serveur (Cmd-Q puis relance)."
    echo "  Tools attendus : profiles_list, setup_status, gmail_list, drive_list, access_request…" ;;
  *)
    die "statut inattendu du merge : « $result »" ;;
esac
