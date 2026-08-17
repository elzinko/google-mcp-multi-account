#!/usr/bin/env bash
# sandbox.sh — sandboxes temporaires (branche / worktree) sans toucher « current ».
#
# Complète deploy-local.sh (tags stables + symlink current) pour essayer une
# feature branch en conditions réelles. Cf. fiche 0041.
# Alias : mag sandbox …  (mag couloir … = déprécié).
#
# Usage :
#   mag sandbox deploy [--wire [desktop,code,cursor|all]] [--repo DIR] …
#   mag sandbox list [--json]
#   mag sandbox status [id]
#   mag sandbox remove [id] [--all]
#   mag sandbox wire [id] [--wire desktop,code,cursor|all]
#   mag sandbox wire [id] --remove [desktop,code,cursor|all]
#
# deploy
#   Archive HEAD (fichiers suivis uniquement ; arbre sale → avertissement).
#   Écrit VERSION + .sandbox.json sous ~/.local/share/google-mcp/<id>/.
#   id = <slug-branche>-<sha>[-dirty] (pas de préfixe « dev- »).
#   Ne modifie jamais le symlink « current » ni le broker stable 4878.
#
# --wire [cibles]
#   Branche une entrée MCP **suffixée** google-multi-account-<id> (binaire +
#   GWSA_BROKER_PORT de la sandbox). Ne touche JAMAIS l'entrée stable
#   google-multi-account @ 4878. Sans valeur : all.
#   Cibles : desktop,code,cursor (alias cd|claude-desktop, cc|claude-code) ou all.
#   Sur deploy : optionnel. Sur wire : brancher une sandbox déjà déployée
#   (sans id → sandbox de la branche courante).
#
# wire --remove [cibles]
#   Retire l'entrée MCP suffixée des clients listés seulement.
#   Sans valeur : all (desktop, code, cursor). Ne touche JAMAIS l'entrée stable.
#   Ne supprime PAS le répertoire sandbox (voir remove pour ça).
#   Ex. : mag sandbox wire --remove desktop
#         mag sandbox wire <id> --remove desktop,cursor
#
# remove
#   Nucléaire : unwire tous les clients, arrête broker/admin, puis supprime
#   le répertoire. Pour unwire sélectif sans supprimer : wire --remove …
#   Sans id → sandboxes de la branche courante.
#
# Variables (tests / override chemins config) :
#   GWSA_DESKTOP_CONFIG   claude_desktop_config.json (défaut macOS/Linux standard)
#   GWSA_CURSOR_CONFIG    ~/.cursor/mcp.json
#   GWSA_DEPLOY_ROOT      ~/.local/share/google-mcp
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_ROOT="${GWSA_DEPLOY_ROOT:-$HOME/.local/share/google-mcp}"
BROKER_BASE=4882
ADMIN_BASE=4879
STABLE_BROKER=4878
STABLE_ADMIN=4877

if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; C=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

# Manifeste sandbox (.sandbox.json) ; .couloir.json lu en compat (anciens déploiements).
manifest_path() { # manifest_path <deploy_dir> → path or empty
  local d="$1"
  if [[ -f "$d/.sandbox.json" ]]; then
    printf '%s' "$d/.sandbox.json"
  elif [[ -f "$d/.couloir.json" ]]; then
    printf '%s' "$d/.couloir.json"
  fi
}

usage() { awk 'NR==1{next} !/^#/{exit} {sub(/^# ?/,""); print}' "$0"; }

slugify() { # slugify <branch> → safe id fragment
  local s="$1"
  s="${s//\//-}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9._-')"
  s="${s#-}"
  [[ -n "$s" ]] || s="head"
  printf '%s' "${s:0:40}"
}

# Parse « desktop,code » / « all » → variables WANT_DESKTOP WANT_CODE WANT_CURSOR =1
parse_wire_targets() {
  local raw="${1:-all}" t
  WANT_DESKTOP=""; WANT_CODE=""; WANT_CURSOR=""
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr ',' ' ')"
  [[ -n "$raw" ]] || raw="all"
  for t in $raw; do
    case "$t" in
      all)
        WANT_DESKTOP=1; WANT_CODE=1; WANT_CURSOR=1
        ;;
      desktop|claude-desktop|cd)
        WANT_DESKTOP=1
        ;;
      code|claude-code|cc)
        WANT_CODE=1
        ;;
      cursor)
        WANT_CURSOR=1
        ;;
      *)
        die "cible inconnue « $t » (desktop|code|cursor|all)"
        ;;
    esac
  done
  [[ -n "$WANT_DESKTOP$WANT_CODE$WANT_CURSOR" ]] \
    || die "--wire : aucune cible (desktop|code|cursor|all)"
}

wire_cursor_entry() { # wire_cursor_entry <name> <mcp_bin> <port>
  local name="$1" bin="$2" port="$3"
  local cfg="${GWSA_CURSOR_CONFIG:-$HOME/.cursor/mcp.json}"
  name="$name" bin="$bin" port="$port" cfg="$cfg" python3 - <<'PY'
import json, os, tempfile, time
from pathlib import Path
cfg = Path(os.environ["cfg"])
name = os.environ["name"]
entry = {
    "command": os.environ["bin"],
    "env": {"GWSA_CLIENT": "cursor", "GWSA_BROKER_PORT": os.environ["port"]},
}
data = {}
if cfg.is_file() and cfg.read_text(encoding="utf-8").strip():
    data = json.loads(cfg.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    raise SystemExit("cursor mcp.json : racine invalide")
servers = data.setdefault("mcpServers", {})
if not isinstance(servers, dict):
    raise SystemExit("cursor mcp.json : mcpServers invalide")
# rival port check (google-mcp only)
for other, srv in servers.items():
    if other == name or not isinstance(srv, dict):
        continue
    cmd = str(srv.get("command") or "")
    if Path(cmd).name != "google-mcp" or cmd == entry["command"]:
        continue
    env = srv.get("env") or {}
    if str(env.get("GWSA_BROKER_PORT", "4878")) == entry["env"]["GWSA_BROKER_PORT"]:
        raise SystemExit(f"port {entry['env']['GWSA_BROKER_PORT']} déjà pris par « {other} »")
if servers.get(name) == entry:
    print("unchanged")
else:
    servers[name] = entry
    cfg.parent.mkdir(parents=True, exist_ok=True)
    if cfg.is_file():
        bak = cfg.with_name(cfg.name + time.strftime(".bak-%Y%m%d-%H%M%S"))
        bak.write_text(cfg.read_text(encoding="utf-8"), encoding="utf-8")
    fd, tmp = tempfile.mkstemp(dir=str(cfg.parent), prefix=".mcp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, cfg)
    print("ok")
PY
}

unwire_json_entry() { # unwire_json_entry <config_path> <name>
  local cfg="$1" name="$2"
  [[ -f "$cfg" ]] || return 0
  name="$name" cfg="$cfg" python3 - <<'PY'
import json, os
from pathlib import Path
cfg = Path(os.environ["cfg"])
name = os.environ["name"]
try:
    data = json.loads(cfg.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)
servers = data.get("mcpServers")
if not isinstance(servers, dict) or name not in servers:
    raise SystemExit(0)
# Ne retirer que les entrées google-mcp (sécurité)
srv = servers[name]
cmd = str((srv or {}).get("command") or "")
if Path(cmd).name != "google-mcp" and "google-mcp" not in cmd:
    raise SystemExit(0)
del servers[name]
cfg.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("removed")
PY
}

wire_sandbox_clients() { # wire_sandbox_clients <target_dir> <id> <broker_port>
  local target="$1" id="$2" broker_port="$3"
  local entry_name="google-multi-account-${id}"
  local mcp_bin="$target/bin/google-mcp"
  local installer_d="$target/scripts/install-claude-desktop.sh"
  local installer_c="$target/scripts/install-claude-code.sh"
  local wired=""

  step "Branchement MCP (entrée « $entry_name » — stable intact)"
  [[ -x "$mcp_bin" ]] || die "binaire MCP absent : $mcp_bin"

  if [[ -n "$WANT_DESKTOP" ]]; then
    if [[ -x "$installer_d" ]]; then
      local dargs=(--name "$entry_name" --port "$broker_port")
      [[ -n "${GWSA_DESKTOP_CONFIG:-}" ]] && dargs+=(--config "$GWSA_DESKTOP_CONFIG")
      if "$installer_d" "${dargs[@]}"; then
        ok "Claude Desktop ← $entry_name @ $broker_port"
        wired=1
      else
        warn "Claude Desktop : branchement en échec"
      fi
    else
      warn "install-claude-desktop.sh absent dans la copie déployée"
    fi
  fi

  if [[ -n "$WANT_CODE" ]]; then
    if [[ -x "$installer_c" ]]; then
      if "$installer_c" --name "$entry_name" --port "$broker_port"; then
        ok "Claude Code ← $entry_name @ $broker_port"
        wired=1
      else
        warn "Claude Code : branchement en échec (claude absent ?)"
      fi
    else
      warn "install-claude-code.sh absent dans la copie déployée"
    fi
  fi

  if [[ -n "$WANT_CURSOR" ]]; then
    if out="$(wire_cursor_entry "$entry_name" "$mcp_bin" "$broker_port")"; then
      ok "Cursor ← $entry_name @ $broker_port ($out)"
      wired=1
    else
      warn "Cursor : branchement en échec"
    fi
  fi

  # Noter l'entrée dans le manifeste pour remove
  local mf
  mf="$(manifest_path "$target")"
  if [[ -n "$mf" && -n "$wired" ]]; then
    entry_name="$entry_name" mf="$mf" python3 - <<'PY'
import json, os
p = os.environ["mf"]
with open(p, encoding="utf-8") as f:
    d = json.load(f)
d["mcp_entry"] = os.environ["entry_name"]
with open(p, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  fi

  echo
  echo "  → Redémarrer le client : Cmd-Q Claude Desktop / nouveau « claude » / reload Cursor."
  echo "  → L'entrée stable « google-multi-account » (4878) n'a pas été modifiée."
}

unwire_sandbox_clients() { # unwire_sandbox_clients <sandbox-id> [entry_name]
  # Respecte WANT_DESKTOP / WANT_CODE / WANT_CURSOR si posés ; sinon tous.
  local id="$1"
  local entry="${2:-google-multi-account-${id}}"
  [[ "$entry" != "google-multi-account" ]] \
    || die "refus : ne jamais retirer l'entrée stable google-multi-account"
  local do_desk="${WANT_DESKTOP:-}" do_code="${WANT_CODE:-}" do_cur="${WANT_CURSOR:-}"
  if [[ -z "$do_desk$do_code$do_cur" ]]; then
    do_desk=1; do_code=1; do_cur=1
  fi
  local desk="${GWSA_DESKTOP_CONFIG:-}"
  if [[ -z "$desk" ]]; then
    case "$(uname -s)" in
      Darwin) desk="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
      *) desk="${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json" ;;
    esac
  fi
  local cur="${GWSA_CURSOR_CONFIG:-$HOME/.cursor/mcp.json}"
  local r
  if [[ -n "$do_desk" ]]; then
    r="$(unwire_json_entry "$desk" "$entry" 2>/dev/null || true)"
    [[ "$r" == "removed" ]] && ok "Claude Desktop : entrée « $entry » retirée"
  fi
  if [[ -n "$do_cur" ]]; then
    r="$(unwire_json_entry "$cur" "$entry" 2>/dev/null || true)"
    [[ "$r" == "removed" ]] && ok "Cursor : entrée « $entry » retirée"
  fi
  if [[ -n "$do_code" ]] && command -v claude >/dev/null 2>&1; then
    if claude mcp remove "$entry" --scope user >/dev/null 2>&1 \
       || claude mcp remove "$entry" >/dev/null 2>&1; then
      ok "Claude Code : entrée « $entry » retirée"
    fi
  fi
}

port_free() { # port_free <port>
  local p="$1"
  (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && return 1 || return 0
}

port_in_manifests() { # port_in_manifests <port> <field broker_port|admin_port>
  local want="$1" field="$2" f p
  [[ -d "$DEPLOY_ROOT" ]] || return 1
  for f in "$DEPLOY_ROOT"/*/.sandbox.json "$DEPLOY_ROOT"/*/.couloir.json; do
    [[ -f "$f" ]] || continue
    p="$(python3 - "$f" "$field" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
    print(d.get(sys.argv[2], ""))
except Exception:
    pass
PY
)"
    [[ "$p" == "$want" ]] && return 0
  done
  return 1
}

pick_port() { # pick_port <start> <field>
  local start_port="$1"
  local field="$2"
  local p="$start_port"
  [[ -n "$start_port" && -n "$field" ]] || die "pick_port : arguments manquants"
  while [[ "$p" -le 65535 ]]; do
    if port_free "$p" && ! port_in_manifests "$p" "$field"; then
      printf '%s' "$p"
      return 0
    fi
    p=$((p + 1))
  done
  die "aucun port libre à partir de $start_port"
}

read_version() { # read_version <deploy_dir>
  local d="$1"
  if [[ -s "$d/VERSION" ]]; then
    tr -d '[:space:]' < "$d/VERSION"
  else
    echo "dev"
  fi
}

mcp_config_paths() {
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' \
        "${GWSA_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}" \
        "${GWSA_CURSOR_CONFIG:-$HOME/.cursor/mcp.json}"
      ;;
    Linux)
      printf '%s\n' \
        "${GWSA_DESKTOP_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/Claude/claude_desktop_config.json}" \
        "${GWSA_CURSOR_CONFIG:-$HOME/.cursor/mcp.json}"
      ;;
    *) printf '%s\n' "${GWSA_CURSOR_CONFIG:-$HOME/.cursor/mcp.json}" ;;
  esac
}

scan_mcp_entries() { # imprime : config_path<TAB>name<TAB>command<TAB>broker_port
  local cfg name
  while IFS= read -r cfg; do
    [[ -f "$cfg" ]] || continue
    python3 - "$cfg" <<'PY' 2>/dev/null || true
import json, os, sys
cfg = sys.argv[1]
try:
    data = json.load(open(cfg, encoding="utf-8"))
except Exception:
    sys.exit(0)
servers = data.get("mcpServers") or {}
for name, srv in servers.items():
    if not isinstance(srv, dict):
        continue
    cmd = srv.get("command") or ""
    if os.path.basename(cmd) != "google-mcp":
        continue
    env = srv.get("env") or {}
    port = env.get("GWSA_BROKER_PORT", "4878")
    print("\t".join([cfg, name, cmd, str(port)]))
PY
  done < <(mcp_config_paths)
}

broker_status_line() { # broker_status_line <port> <gwsa_root>
  local port="$1" root="${2:-${GWSA_ROOT:-$HOME/.config/gws-accounts}}"
  local pidf="$root/.broker-$port.pid" pid="" listening=""
  if [[ -f "$pidf" ]]; then pid="$(cat "$pidf" 2>/dev/null || true)"; fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null \
      && ps -p "$pid" -o command= 2>/dev/null | grep -q "gateway.broker_server"; then
    echo "broker: en route (pid $pid, port $port)"
    return 0
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    echo "broker: écoute sur $port (sans pidfile reconnu)"
    return 0
  fi
  echo "broker: arrêté (port $port)"
}

admin_status_line() { # admin_status_line <port> <gwsa_root>
  local port="$1" root="${2:-${GWSA_ROOT:-$HOME/.config/gws-accounts}}"
  local pidf="$root/.admin-$port.pid"
  [[ -f "$pidf" ]] || pidf="$root/.admin.pid"
  local pid=""
  if [[ -f "$pidf" ]]; then pid="$(cat "$pidf" 2>/dev/null || true)"; fi
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "admin: en route (pid $pid, http://127.0.0.1:$port)"
    return 0
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    echo "admin: écoute sur $port"
    return 0
  fi
  echo "admin: arrêté (port $port)"
}

stop_broker_port() { # stop_broker_port <port> [gwsa_root]
  local port="$1" root="${2:-${GWSA_ROOT:-$HOME/.config/gws-accounts}}"
  local pidf="$root/.broker-$port.pid" pid=""
  [[ -f "$pidf" ]] && pid="$(cat "$pidf" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null \
      && ps -p "$pid" -o command= 2>/dev/null | grep -q "gateway.broker_server"; then
    kill "$pid" 2>/dev/null || true
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [[ "$waited" -lt 25 ]]; do
      sleep 0.2; waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
    rm -f "$pidf"
    echo "  broker $port : arrêté (pid $pid)"
    return 0
  fi
  rm -f "$pidf"
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    warn "broker $port : écoute sans pidfile reconnu — arrêt manuel requis"
    return 1
  fi
  echo "  broker $port : déjà arrêté"
}

stop_admin_port() { # stop_admin_port <port> [gwsa_root]
  local port="$1" root="${2:-${GWSA_ROOT:-$HOME/.config/gws-accounts}}"
  local pidf="$root/.admin-$port.pid"
  [[ -f "$pidf" ]] || pidf="$root/.admin.pid"
  local pid=""
  [[ -f "$pidf" ]] && pid="$(cat "$pidf" 2>/dev/null || true)"
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    rm -f "$pidf"
    echo "  admin $port : arrêté (pid $pid)"
    return 0
  fi
  rm -f "$pidf"
  if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    warn "admin $port : écoute sans pidfile reconnu — arrêt manuel requis"
    return 1
  fi
  echo "  admin $port : déjà arrêté"
}

cmd_remove_one() { # cmd_remove_one <sandbox-id>
  local id="$1"
  [[ "$id" != "current" ]] || die "refus : « current » est le symlink stable — pas une sandbox jetable"
  local target="$DEPLOY_ROOT/$id"
  [[ -d "$target" ]] || die "sandbox « $id » introuvable sous $DEPLOY_ROOT"
  local mf
  mf="$(manifest_path "$target")"
  [[ -n "$mf" ]] || die "refus : « $id » n'est pas une sandbox (pas de .sandbox.json / .couloir.json) — ne pas supprimer une archive stable"
  local broker_port admin_port mcp_entry
  read -r broker_port admin_port mcp_entry < <(python3 - "$mf" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("broker_port", ""), d.get("admin_port", ""), d.get("mcp_entry") or "")
PY
)
  [[ "$broker_port" =~ ^[0-9]+$ ]] || die "manifeste invalide : broker_port manquant"
  [[ "$admin_port" =~ ^[0-9]+$ ]] || die "manifeste invalide : admin_port manquant"
  if [[ "$broker_port" == "$STABLE_BROKER" && "$admin_port" == "$STABLE_ADMIN" ]]; then
    die "refus : ports stable ($STABLE_BROKER/$STABLE_ADMIN) — id sandbox suspect"
  fi
  step "Arrêt des services sandbox « $id »"
  stop_broker_port "$broker_port"
  stop_admin_port "$admin_port"
  step "Retrait des entrées MCP branchées (tous clients)"
  # Nuclear remove : tous les clients, indépendamment d'un WANT_* résiduel.
  WANT_DESKTOP=1 WANT_CODE=1 WANT_CURSOR=1 \
    unwire_sandbox_clients "$id" "${mcp_entry:-google-multi-account-${id}}"
  step "Suppression $target"
  rm -rf "$target"
  ok "sandbox « $id » supprimée (répertoire + état local)"
}

# Sandboxes de la branche git courante (manifest.branch, <slug>-*, ou ancien dev-<slug>-*).
# HEAD détaché (ex. merge commit CI) : branch="HEAD", slug="head" — aligné sur deploy.
list_branch_sandbox_ids() {
  local branch slug name mf mb
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] || return 0
  slug="$(slugify "$branch")"
  [[ -d "$DEPLOY_ROOT" ]] || return 0
  for d in "$DEPLOY_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    mf="$(manifest_path "$d")"
    [[ -n "$mf" ]] || continue
    mb="$(python3 - "$mf" <<'PY' 2>/dev/null || true
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("branch") or "")
except Exception:
    pass
PY
)"
    # Nouveau format <slug>-<sha> ; compat anciennes sandboxes dev-<slug>-…
    if [[ "$mb" == "$branch" \
       || "$name" == "${slug}-"* \
       || "$name" == "dev-${slug}-"* ]]; then
      printf '%s\n' "$name"
    fi
  done
}

cmd_remove() { # mag sandbox remove [id] [--all]
  local id="" all=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) die "option inconnue « $1 » (remove [id] [--all])" ;;
      *) [[ -z "$id" ]] || die "un seul id attendu"; id="$1" ;;
    esac
    shift
  done

  if [[ -n "$id" ]]; then
    cmd_remove_one "$id"
    return 0
  fi

  # Sans id : sandboxes de la branche courante du worktree / clone.
  command -v git >/dev/null 2>&1 || die "git est requis pour remove sans id"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "pas de dépôt git dans $REPO_ROOT — précise un id : mag sandbox remove <id>"

  local branch ids=()
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  [[ -n "$branch" ]] \
    || die "impossible de résoudre HEAD — précise un id : mag sandbox list puis remove <id>"

  while IFS= read -r line; do
    [[ -n "$line" ]] && ids+=("$line")
  done < <(list_branch_sandbox_ids | sort -u)

  if [[ ${#ids[@]} -eq 0 ]]; then
    die "aucune sandbox pour la branche « $branch » — mag sandbox list"
  fi

  if [[ ${#ids[@]} -eq 1 ]]; then
    ok "branche « $branch » → sandbox ${ids[0]}"
    cmd_remove_one "${ids[0]}"
    return 0
  fi

  echo "Plusieurs sandboxes pour « $branch » :" >&2
  local x
  for x in "${ids[@]}"; do echo "  - $x" >&2; done

  if [[ -n "$all" ]]; then
    for x in "${ids[@]}"; do cmd_remove_one "$x"; done
    return 0
  fi

  if [[ -t 0 ]]; then
    printf 'Supprimer les %s ? [y/N] ' "${#ids[@]}" >&2
    local ans=""
    read -r ans || true
    [[ "$ans" == [yY] ]] || die "annulé — ou : mag sandbox remove <id> | remove --all"
    for x in "${ids[@]}"; do cmd_remove_one "$x"; done
    return 0
  fi

  die "plusieurs matches — précise un id, ou : mag sandbox remove --all"
}

# Résout un id sandbox (explicite ou branche courante) → imprime l'id unique.
resolve_sandbox_id() { # resolve_sandbox_id [id] → id
  local id="${1:-}"
  if [[ -n "$id" ]]; then
    printf '%s' "$id"
    return 0
  fi
  command -v git >/dev/null 2>&1 || die "git est requis pour résoudre la sandbox sans id"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    || die "pas de dépôt git dans $REPO_ROOT — précise un id"
  local branch ids=()
  branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  [[ -n "$branch" ]] \
    || die "impossible de résoudre HEAD — précise un id : mag sandbox list"
  while IFS= read -r line; do
    [[ -n "$line" ]] && ids+=("$line")
  done < <(list_branch_sandbox_ids | sort -u)
  if [[ ${#ids[@]} -eq 0 ]]; then
    die "aucune sandbox pour la branche « $branch » — mag sandbox list"
  fi
  if [[ ${#ids[@]} -eq 1 ]]; then
    printf '%s' "${ids[0]}"
    return 0
  fi
  echo "Plusieurs sandboxes pour « $branch » :" >&2
  local x
  for x in "${ids[@]}"; do echo "  - $x" >&2; done
  die "précise un id : mag sandbox wire <id> [--wire … | --remove …]"
}

# Consomme --wire / --remove / formes =… ; pose DO_WIRE, WIRE_SPEC, DO_REMOVE, REMOVE_SPEC.
# Après appel : if ((${#PARSE_WIRE_REST[@]})); then set -- "${PARSE_WIRE_REST[@]}"; else set --; fi
parse_wire_flag() {
  DO_WIRE=""; WIRE_SPEC=""; DO_REMOVE=""; REMOVE_SPEC=""; PARSE_WIRE_REST=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --wire)
        DO_WIRE=1
        if [[ $# -ge 2 && "$2" != -* ]]; then
          WIRE_SPEC="$2"; shift
        else
          WIRE_SPEC="all"
        fi
        ;;
      --wire=*)
        DO_WIRE=1
        WIRE_SPEC="${1#*=}"
        [[ -n "$WIRE_SPEC" ]] || WIRE_SPEC="all"
        ;;
      --remove)
        DO_REMOVE=1
        if [[ $# -ge 2 && "$2" != -* ]]; then
          REMOVE_SPEC="$2"; shift
        else
          REMOVE_SPEC="all"
        fi
        ;;
      --remove=*)
        DO_REMOVE=1
        REMOVE_SPEC="${1#*=}"
        [[ -n "$REMOVE_SPEC" ]] || REMOVE_SPEC="all"
        ;;
      *) PARSE_WIRE_REST+=("$1") ;;
    esac
    shift
  done
}

cmd_wire() { # mag sandbox wire [id] [--wire …] | --remove [desktop,code,cursor|all]
  local id=""
  parse_wire_flag "$@"
  if ((${#PARSE_WIRE_REST[@]})); then
    set -- "${PARSE_WIRE_REST[@]}"
  else
    set --
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -*) die "option inconnue « $1 » (wire [id] [--wire … | --remove …])" ;;
      *) [[ -z "$id" ]] || die "un seul id attendu"; id="$1" ;;
    esac
    shift
  done
  if [[ -n "$DO_REMOVE" && -n "$DO_WIRE" ]]; then
    die "wire : --wire et --remove sont exclusifs"
  fi
  id="$(resolve_sandbox_id "$id")"
  local target="$DEPLOY_ROOT/$id"
  [[ -d "$target" ]] || die "sandbox « $id » introuvable sous $DEPLOY_ROOT"
  local mf broker_port mcp_entry
  mf="$(manifest_path "$target")"
  [[ -n "$mf" ]] || die "« $id » n'est pas une sandbox (pas de manifeste)"

  if [[ -n "$DO_REMOVE" ]]; then
    parse_wire_targets "${REMOVE_SPEC:-all}"
    mcp_entry="$(python3 - "$mf" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("mcp_entry") or "")
PY
)"
    step "Unwire sélectif « $id » (répertoire conservé)"
    unwire_sandbox_clients "$id" "${mcp_entry:-google-multi-account-${id}}"
    ok "entrée MCP retirée des clients choisis — sandbox « $id » toujours sous $target"
    echo "  → remove nucléaire (tous clients + supprimer le répertoire) : mag sandbox remove $id"
    return 0
  fi

  parse_wire_targets "${WIRE_SPEC:-all}"
  broker_port="$(python3 - "$mf" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("broker_port", ""))
PY
)"
  [[ "$broker_port" =~ ^[0-9]+$ ]] || die "manifeste invalide : broker_port manquant"
  wire_sandbox_clients "$target" "$id" "$broker_port"
}

cmd_deploy() {
  local src="$REPO_ROOT" kind="dev" want_port="" want_admin=""
  parse_wire_flag "$@"
  if [[ -n "$DO_REMOVE" ]]; then
    die "deploy : utilise « mag sandbox wire --remove … » pour unwire (pas --remove sur deploy)"
  fi
  if ((${#PARSE_WIRE_REST[@]})); then
    set -- "${PARSE_WIRE_REST[@]}"
  else
    set --
  fi
  local do_wire="$DO_WIRE" wire_spec="${WIRE_SPEC:-all}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dev) kind="dev" ;;  # synonyme historique — deploy est toujours jetable
      --repo) shift; src="${1:-}"; [[ -d "$src" ]] || die "--repo : répertoire introuvable" ;;
      --port) shift; want_port="${1:-}" ;;
      --admin-port) shift; want_admin="${1:-}" ;;
      -h|--help) usage; exit 0 ;;
      *) die "argument inconnu « $1 » (voir --help)" ;;
    esac
    shift
  done

  command -v git >/dev/null 2>&1 || die "git est requis"
  git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || die "$src n'est pas un dépôt git"

  step "Contrôles"
  local branch sha dirty=""
  branch="$(git -C "$src" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
  sha="$(git -C "$src" rev-parse --short HEAD)"
  if [[ -n "$(git -C "$src" status --porcelain)" ]]; then
    dirty=1
    warn "arbre de travail sale — seuls les fichiers **commités** seront archivés"
  fi
  ok "branche : $branch @ $sha"

  local slug id version_label
  slug="$(slugify "$branch")"
  id="${slug}-${sha}"
  [[ -z "$dirty" ]] || id="${id}-dirty"
  version_label="${branch}@${sha} (dev)"
  [[ -z "$dirty" ]] || version_label="${version_label}, dirty"

  local target="$DEPLOY_ROOT/$id"
  local chosen_broker="" chosen_admin=""
  [[ -n "$want_port" ]] && chosen_broker="$want_port"
  [[ -n "$want_admin" ]] && chosen_admin="$want_admin"
  [[ -n "$chosen_broker" ]] || chosen_broker="$(pick_port "$BROKER_BASE" broker_port)"
  [[ -n "$chosen_admin" ]] || chosen_admin="$(pick_port "$ADMIN_BASE" admin_port)"
  [[ "$chosen_broker" =~ ^[0-9]+$ ]] || die "port broker invalide"
  [[ "$chosen_admin" =~ ^[0-9]+$ ]] || die "port admin invalide"
  local broker_port="$chosen_broker" admin_port="$chosen_admin"
  [[ "$broker_port" != "$STABLE_BROKER" ]] \
    || die "refus : le port $STABLE_BROKER est réservé au déploiement stable"

  step "Déploiement sandbox « $id »"
  mkdir -p "$DEPLOY_ROOT"
  if [[ -d "$target" ]]; then
    ok "déjà déployé — pas de réécriture ($target)"
  else
    local tmp
    tmp="$(mktemp -d "$DEPLOY_ROOT/.tmp-XXXXXX")"
    git -C "$src" archive HEAD | tar -x -C "$tmp" \
      || { rm -rf "$tmp"; die "échec git archive"; }
    printf '%s\n' "$version_label" > "$tmp/VERSION"
    printf '%s\n' "$src" > "$tmp/.source"
    SANDBOX_MANIFEST="$tmp/.sandbox.json" \
    SANDBOX_ID="$id" SANDBOX_VERSION="$version_label" SANDBOX_BRANCH="$branch" \
    SANDBOX_SHA="$sha" SANDBOX_DIRTY="${dirty:-0}" SANDBOX_KIND="$kind" \
    SANDBOX_BROKER="$broker_port" SANDBOX_ADMIN="$admin_port" SANDBOX_SRC="$src" \
    python3 - <<'PY'
import datetime, json, os
manifest = {
    "id": os.environ["SANDBOX_ID"],
    "version": os.environ["SANDBOX_VERSION"],
    "branch": os.environ["SANDBOX_BRANCH"],
    "sha": os.environ["SANDBOX_SHA"],
    "dirty": os.environ.get("SANDBOX_DIRTY") == "1",
    "kind": os.environ["SANDBOX_KIND"],
    "broker_port": int(os.environ["SANDBOX_BROKER"]),
    "admin_port": int(os.environ["SANDBOX_ADMIN"]),
    "source_repo": os.environ["SANDBOX_SRC"],
    "deployed_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
}
path = os.environ["SANDBOX_MANIFEST"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    mv "$tmp" "$target"
    ok "copie figée : $target"
  fi

  # Relire le manifeste si réutilisation (.sandbox.json ou .couloir.json)
  local mf
  mf="$(manifest_path "$target")"
  if [[ -n "$mf" ]]; then
    read -r broker_port admin_port version_label < <(python3 - "$mf" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d["broker_port"], d["admin_port"], d["version"])
PY
)
  fi

  local entry_name="google-multi-account-${id}"
  local installer="$target/scripts/install-claude-desktop.sh"
  local mcp_bin="$target/bin/google-mcp"

  step "Résumé"
  echo "  id           : $id"
  echo "  version      : $version_label"
  echo "  répertoire   : $target"
  echo "  broker       : port $broker_port"
  echo "  admin        : port $admin_port (≠ stable $STABLE_ADMIN — GWSA_ADMIN_PORT=$admin_port)"
  echo "  current      : inchangé ($(basename "$(readlink "$DEPLOY_ROOT/current" 2>/dev/null || echo aucun)" 2>/dev/null || echo aucun))"

  if [[ -n "$do_wire" ]]; then
    parse_wire_targets "$wire_spec"
    wire_sandbox_clients "$target" "$id" "$broker_port"
    step "Suite — checklist post-wire"
    cat <<EOF
1. Redémarrer les clients MCP (Cmd-Q Claude Desktop / nouveau « claude » / reload Cursor).
2. Vérifier l'entrée « $entry_name » (port $broker_port) dans le client — pas « google-multi-account » (4878).
3. Statut : ./bin/mag sandbox status $id
4. Admin sandbox : http://127.0.0.1:$admin_port
   GWSA_ADMIN_PORT=$admin_port $target/bin/mag admin

⚠ http://127.0.0.1:$STABLE_ADMIN = admin stable / worktree, PAS cette sandbox.
Le déploiement stable (broker $STABLE_BROKER) n'a pas été touché.
EOF
  else
    step "Il reste des gestes — à toi"
    cat <<EOF
1. Brancher Claude Desktop (copie déployée, PAS le clone) :

   $installer \\
     --name $entry_name \\
     --port $broker_port

   Ou en une commande : ./bin/mag sandbox wire $id --wire desktop,cursor

2. Cursor (~/.cursor/mcp.json) — même binaire et port :

   "command": "$mcp_bin"
   "env": { "GWSA_CLIENT": "cursor", "GWSA_BROKER_PORT": "$broker_port" }

3. Redémarrer le client MCP (Cmd-Q Claude Desktop, reload Cursor).

4. Vérifier :

   ./bin/mag sandbox status $id
   # admin sandbox (pas 4877) : http://127.0.0.1:$admin_port

5. Admin dédié sandbox (port $admin_port — distinct du stable $STABLE_ADMIN) :

   GWSA_ADMIN_PORT=$admin_port $target/bin/mag admin
   # ou depuis le worktree :
   # GWSA_ADMIN_PORT=$admin_port ./bin/mag admin

⚠ http://127.0.0.1:$STABLE_ADMIN = admin stable / worktree, PAS cette sandbox.

Le déploiement stable (broker $STABLE_BROKER) n'a pas été touché.
EOF
  fi
}

cmd_list() {
  local json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) json=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "argument inconnu « $1 » (list [--json])" ;;
    esac
    shift
  done

  if [[ "$json" -eq 1 ]]; then
    DEPLOY_ROOT="$DEPLOY_ROOT" STABLE_BROKER="$STABLE_BROKER" STABLE_ADMIN="$STABLE_ADMIN" python3 - <<'PY'
import json, os, socket
from pathlib import Path

root = Path(os.environ["DEPLOY_ROOT"])
stable_b = int(os.environ["STABLE_BROKER"])
stable_a = int(os.environ["STABLE_ADMIN"])

def listening(port):
    try:
        s = socket.create_connection(("127.0.0.1", int(port)), timeout=0.25)
        s.close()
        return True
    except OSError:
        return False

def manifest(d: Path):
    for name in (".sandbox.json", ".couloir.json"):
        p = d / name
        if p.is_file():
            try:
                return json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                return None
    return None

current = None
cur = root / "current"
if cur.is_symlink():
    try:
        current = Path(os.readlink(cur)).name
    except OSError:
        current = None

items = []
if root.is_dir():
    for d in sorted(root.iterdir()):
        if not d.is_dir() or d.name == "current" or d.name.startswith(".tmp-"):
            continue
        mf = manifest(d)
        is_sandbox = mf is not None
        is_current = d.name == current
        ver = ""
        vp = d / "VERSION"
        if vp.is_file():
            ver = vp.read_text(encoding="utf-8").strip()
        elif mf and mf.get("version"):
            ver = mf["version"]
        if is_sandbox:
            bp, ap = mf.get("broker_port"), mf.get("admin_port")
        elif is_current:
            bp, ap = stable_b, stable_a
        else:
            bp, ap = None, None
        items.append({
            "id": d.name,
            "path": str(d),
            "version": ver or None,
            "is_sandbox": is_sandbox,
            "is_current": is_current,
            "broker_port": bp,
            "admin_port": ap,
            "broker_up": listening(bp) if bp is not None else False,
            "admin_up": listening(ap) if ap is not None else False,
            "branch": (mf or {}).get("branch"),
            "sha": (mf or {}).get("sha"),
            "source_repo": (mf or {}).get("source_repo"),
        })
print(json.dumps({"deploy_root": str(root), "current": current, "deployments": items}, ensure_ascii=False, indent=2))
PY
    return 0
  fi

  step "Versions déployées ($DEPLOY_ROOT)"
  local found=""
  if [[ -d "$DEPLOY_ROOT" ]]; then
    for d in "$DEPLOY_ROOT"/*/; do
      [[ -d "$d" ]] || continue
      local name="$(basename "$d")"
      [[ "$name" == "current" || "$name" == .tmp-* ]] && continue
      found=1
      local ver manifest bp ap marker="" mf
      ver="$(read_version "$d")"
      mf="$(manifest_path "$d")"
      if [[ -n "$mf" ]]; then
        read -r bp ap < <(python3 - "$mf" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("broker_port", "?"), d.get("admin_port", "?"))
PY
)
        marker=" [sandbox]"
      else
        bp="?"; ap="—"
      fi
      local cur=""
      [[ -L "$DEPLOY_ROOT/current" ]] && [[ "$(basename "$(readlink "$DEPLOY_ROOT/current")")" == "$name" ]] && cur=" *"
      printf '  %s%s%s  %s  broker:%s  admin:%s  %s\n' "${cur:- }" "$name" "$marker" "$ver" "$bp" "$ap" "$d"
    done
  fi
  [[ -n "$found" ]] || warn "aucune version sous $DEPLOY_ROOT"

  step "Entrées MCP (google-mcp)"
  local any=""
  while IFS=$'\t' read -r cfg entry cmd port; do
    [[ -n "$cfg" ]] || continue
    any=1
    local repo_dir="${cmd%/bin/google-mcp}" ver="dev"
    [[ -s "$repo_dir/VERSION" ]] && ver="$(tr -d '[:space:]' < "$repo_dir/VERSION")"
    echo "  ${C}$entry${N}  port $port  version $ver"
    echo "    config : $cfg"
    echo "    binary : $cmd"
  done < <(scan_mcp_entries)
  [[ -n "$any" ]] || warn "aucune entrée google-mcp trouvée (Claude Desktop / Cursor)"
}

cmd_status() {
  local filter="${1:-}"
  local any=""
  if [[ -n "$filter" ]]; then
    local d="$DEPLOY_ROOT/$filter"
    [[ -d "$d" ]] || die "sandbox « $filter » introuvable"
    echo "${B}$filter${N}  $(read_version "$d")"
    local bp="" ap="" mf kind=""
    mf="$(manifest_path "$d")"
    if [[ -n "$mf" ]]; then
      kind="sandbox"
      read -r bp ap < <(python3 - "$mf" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("broker_port", 4882), d.get("admin_port", 4879))
PY
)
    elif [[ -L "$DEPLOY_ROOT/current" ]] \
      && [[ "$(basename "$(readlink "$DEPLOY_ROOT/current")")" == "$filter" ]]; then
      kind="stable-current"
      bp="$STABLE_BROKER"
      ap="$STABLE_ADMIN"
    else
      kind="stable-archive"
    fi
    if [[ -n "$bp" ]]; then
      echo "  $(broker_status_line "$bp")"
      echo "  $(admin_status_line "$ap")"
    else
      echo "  broker/admin : n/a (archive — seuls current + sandboxes ont des ports dédiés)"
      echo "  note: le broker stable écoute éventuellement sur $STABLE_BROKER (pas attribué à cette copie)"
    fi
    echo "  kind: $kind"
    echo "  path: $d"
    return 0
  fi

  step "Sandboxes déployées"
  [[ -d "$DEPLOY_ROOT" ]] || die "aucun déploiement dans $DEPLOY_ROOT"
  for d in "$DEPLOY_ROOT"/*/; do
    [[ -d "$d" ]] || continue
    local name="$(basename "$d")"
    [[ "$name" == "current" || "$name" == .tmp-* ]] && continue
    any=1
    echo
    cmd_status "$name"
  done
  [[ -n "$any" ]] || warn "aucune sandbox — lance : mag sandbox deploy --dev"
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    deploy) cmd_deploy "$@" ;;
    list|ls) cmd_list "$@" ;;
    status|st) cmd_status "${1:-}" ;;
    remove|rm) cmd_remove "$@" ;;
    wire) cmd_wire "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "sous-commande inconnue « $cmd » (deploy | list | status | remove | wire)" ;;
  esac
}

main "$@"
