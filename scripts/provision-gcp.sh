#!/usr/bin/env bash
# provision-gcp.sh — provisionne le projet Google Cloud nécessaire à gws/gwsa.
#
# Le « projet » GCP créé ici est un simple conteneur administratif OAuth :
# rien n'est déployé, aucune facturation, 0 €. Tout le reste tourne en local.
#
# Automatisé      : login gcloud, VÉRIFICATION DU COMPTE ACTIF, création du
#                   projet, activation des APIs, écran de consentement (best
#                   effort par API, sinon guidé).
# Guidé (console) : création du client OAuth « Desktop app » et publication en
#                   Production — Google a fermé les APIs correspondantes. Le
#                   script ouvre les bonnes pages et récupère tout seul le JSON
#                   téléchargé dans ~/Downloads.
#
# Usage :
#   ./scripts/provision-gcp.sh                             # flow complet (interactif)
#   ./scripts/provision-gcp.sh status                      # état des lieux (lecture seule)
#   ./scripts/provision-gcp.sh --confirm-account moi@gmail.com   # mode non interactif
#
# Idempotent : relançable sans risque, chaque étape détecte l'existant.
# État persisté dans ~/.config/gws-accounts/provision.env
set -euo pipefail

GWSA_ROOT="${GWSA_ROOT:-$HOME/.config/gws-accounts}"
STATE_FILE="$GWSA_ROOT/provision.env"
SECRET_DEST="$GWSA_ROOT/client_secret.json"
APP_NAME="gws CLI perso"
APIS="gmail.googleapis.com drive.googleapis.com calendar-json.googleapis.com docs.googleapis.com sheets.googleapis.com slides.googleapis.com tasks.googleapis.com people.googleapis.com"

# ── affichage ────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; G=""; R=""; Y=""; N=""
fi
step() { echo; echo "${B}── $* ──${N}"; }
ok()   { echo "${G}✓${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
die()  { echo "${R}✗ $*${N}" >&2; exit 1; }

is_tty() { [[ -t 0 ]]; }

confirm() { # confirm <question> — vrai si oui
  local rep
  read -r -p "$1 [o/N] " rep
  [[ "$rep" =~ ^[oOyY] ]]
}

wait_enter() { is_tty && read -r -p "→ Appuie sur Entrée quand c'est fait… " _ || true; }

# ── arguments ────────────────────────────────────────────────────
MODE="run"
CONFIRM_ACCOUNT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    status) MODE="status" ;;
    --confirm-account) shift; CONFIRM_ACCOUNT="${1:-}" ;;
    --confirm-account=*) CONFIRM_ACCOUNT="${1#*=}" ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "argument inconnu : $1 (voir --help)" ;;
  esac
  shift
done

# ── helpers gcloud ───────────────────────────────────────────────
have_gcloud() { command -v gcloud >/dev/null 2>&1; }

active_account() {
  gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1
}

load_state() { [[ -f "$STATE_FILE" ]] && . "$STATE_FILE" || true; }

save_state() {
  mkdir -p "$GWSA_ROOT"
  { echo "PROJECT_ID=\"$PROJECT_ID\""; echo "OWNER_ACCOUNT=\"$ACCOUNT\""; } > "$STATE_FILE"
}

# ── status (lecture seule) ───────────────────────────────────────
if [[ "$MODE" == "status" ]]; then
  step "État du provisioning"
  if have_gcloud; then ok "gcloud installé ($(gcloud --version 2>/dev/null | head -1))"
  else warn "gcloud non installé"; fi
  acct="$(have_gcloud && active_account || true)"
  [[ -n "${acct:-}" ]] && ok "compte actif : ${B}$acct${N}" || warn "aucun compte gcloud connecté"
  PROJECT_ID=""; load_state
  [[ -n "${PROJECT_ID:-}" ]] && ok "projet (état local) : $PROJECT_ID" || warn "aucun projet provisionné ($STATE_FILE absent)"
  if [[ -n "${PROJECT_ID:-}" ]] && have_gcloud && [[ -n "${acct:-}" ]]; then
    n=$(gcloud services list --enabled --project "$PROJECT_ID" --format="value(config.name)" 2>/dev/null | grep -c -F -f <(printf '%s\n' $APIS) || true)
    echo "  APIs activées : $n/8"
  fi
  [[ -f "$SECRET_DEST" ]] && ok "client_secret.json en place ($SECRET_DEST)" || warn "client_secret.json absent"

  # Dérive IAM : quels comptes connectés n'ont pas le rôle serviceUsageConsumer
  # sur le projet (sinon 403 « quota project » silencieux au 1er appel — §7).
  if [[ -n "${PROJECT_ID:-}" ]] && have_gcloud && [[ -n "${acct:-}" ]]; then
    step "Comptes connectés & accès au projet (rôle IAM)"
    authorized="$(gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.role=roles/owner OR bindings.role=roles/editor OR bindings.role=roles/serviceusage.serviceUsageConsumer" \
      --format="value(bindings.members)" 2>/dev/null | sed 's/^user://' || true)"
    any_profile=""
    for d in "$GWSA_ROOT"/*/; do
      [[ -f "$d/client_secret.json" ]] || continue
      any_profile=1
      alias_name="$(basename "$d")"
      pemail="$(GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$d" gws auth status 2>/dev/null \
        | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' | head -1 || true)"
      if [[ -z "$pemail" ]]; then
        warn "$alias_name : email indéterminé (token expiré ? → gwsa add $alias_name)"
      elif printf '%s\n' "$authorized" | grep -qixF "$pemail"; then  # -i : emails insensibles à la casse
        ok "$alias_name ($pemail) : accès projet OK"
      else
        warn "$alias_name ($pemail) : SANS rôle serviceUsageConsumer → 403 au 1er appel"
        echo "     gcloud projects add-iam-policy-binding $PROJECT_ID --member=user:$pemail --role=roles/serviceusage.serviceUsageConsumer"
      fi
    done
    [[ -n "$any_profile" ]] || echo "  (aucun compte connecté — gwsa add <alias>)"
  fi
  exit 0
fi

# ── 1. gcloud ────────────────────────────────────────────────────
step "1/7 · gcloud CLI"
if ! have_gcloud; then
  warn "gcloud n'est pas installé (nécessaire pour piloter GCP)."
  if is_tty && confirm "L'installer maintenant via Homebrew (~1 Go) ?"; then
    brew install --cask google-cloud-sdk
    hash -r
    have_gcloud || die "gcloud introuvable après installation — ouvre un nouveau terminal et relance."
  else
    die "installe-le puis relance : brew install --cask google-cloud-sdk"
  fi
fi
ok "gcloud présent"

# ── 2. Compte : login + VÉRIFICATION ─────────────────────────────
step "2/7 · Compte Google actif"
ACCOUNT="$(active_account)"
if [[ -z "$ACCOUNT" ]]; then
  echo "Aucun compte connecté — ouverture du navigateur (gcloud auth login)…"
  is_tty || die "aucun compte gcloud actif et session non interactive : lance d'abord « gcloud auth login »."
  gcloud auth login --brief --quiet
  ACCOUNT="$(active_account)"
  [[ -n "$ACCOUNT" ]] || die "échec de la connexion gcloud."
fi

echo
echo "   Compte actif : ${B}${G}$ACCOUNT${N}"
echo "   (ce compte sera le propriétaire du projet OAuth — tes autres comptes"
echo "    Gmail n'en ont pas besoin, ils ne feront que se connecter ensuite)"
echo
if [[ -n "$CONFIRM_ACCOUNT" ]]; then
  [[ "$CONFIRM_ACCOUNT" == "$ACCOUNT" ]] \
    || die "compte actif « $ACCOUNT » ≠ compte attendu « $CONFIRM_ACCOUNT ». Change avec : gcloud config set account <email> (ou gcloud auth login)."
  ok "compte confirmé (--confirm-account)"
elif is_tty; then
  if ! confirm "C'est bien le bon compte ?"; then
    echo "Comptes connus de gcloud :"; gcloud auth list --format="  value(account)"
    echo "→ Changer : « gcloud config set account <email> » (compte déjà listé)"
    echo "           ou « gcloud auth login » (nouveau compte), puis relance ce script."
    exit 2
  fi
else
  die "session non interactive : relance avec --confirm-account $ACCOUNT pour valider ce compte."
fi

# ── 3. Projet ────────────────────────────────────────────────────
step "3/7 · Projet GCP (conteneur vide — rien n'est déployé, 0 €)"
PROJECT_ID=""; load_state
if [[ -n "${PROJECT_ID:-}" ]] && gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  ok "projet existant réutilisé : $PROJECT_ID"
else
  PROJECT_ID="gws-multi-$(openssl rand -hex 3)"
  echo "Création du projet « $PROJECT_ID »…"
  gcloud projects create "$PROJECT_ID" --name="gws-multi-account" --quiet
  ok "projet créé : $PROJECT_ID"
fi
gcloud config set project "$PROJECT_ID" --quiet >/dev/null
save_state

# ── 4. APIs ──────────────────────────────────────────────────────
step "4/7 · Activation des APIs Workspace (gratuites, sans facturation)"
echo "Gmail, Drive, Calendar, Docs, Sheets, Slides, Tasks, People…"
# shellcheck disable=SC2086
gcloud services enable $APIS --project "$PROJECT_ID" --quiet
ok "8 APIs activées"

# ── 5. Écran de consentement ─────────────────────────────────────
step "5/7 · Écran de consentement OAuth"
TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
BRANDS_URL="https://oauth2.googleapis.com/v1/projects/$PROJECT_ID/brands"
consent_ok=""
if [[ -n "$TOKEN" ]]; then
  existing="$(curl -sf -H "Authorization: Bearer $TOKEN" "$BRANDS_URL" 2>/dev/null || true)"
  if echo "$existing" | grep -q '"brands"'; then
    consent_ok=1; ok "écran de consentement déjà configuré"
  else
    created="$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"applicationTitle\":\"$APP_NAME\",\"supportEmail\":\"$ACCOUNT\"}" "$BRANDS_URL" 2>/dev/null || true)"
    if echo "$created" | grep -q '"name"'; then
      consent_ok=1; ok "écran de consentement créé par API"
    fi
  fi
fi
if [[ -z "$consent_ok" ]]; then
  warn "création par API impossible (classique sur compte perso) → passage en mode guidé."
  echo "   Dans la page qui s'ouvre : ${B}Get started${N} → App name « $APP_NAME »,"
  echo "   ton email, Audience ${B}External${N}, email de contact → Create."
  open "https://console.cloud.google.com/auth/overview?project=$PROJECT_ID" 2>/dev/null || true
  wait_enter
fi

# ── 6. Client OAuth « Desktop app » (console, guidé) ─────────────
step "6/7 · Client OAuth Desktop (seule étape 100 % manuelle — API fermée par Google)"
if [[ -f "$SECRET_DEST" ]]; then
  ok "client_secret.json déjà en place : $SECRET_DEST"
else
  echo "   Dans la page qui s'ouvre : ${B}Create client${N} → type ${B}Desktop app${N}"
  echo "   → nom « gws-cli » → Create → bouton ${B}Download JSON${N}."
  echo "   Je surveille ~/Downloads et je range le fichier automatiquement…"
  open "https://console.cloud.google.com/auth/clients/create?project=$PROJECT_ID" 2>/dev/null || true
  mkdir -p "$GWSA_ROOT"
  start_ts="$(date +%s)"
  found=""
  for _ in $(seq 1 600); do
    candidate="$(ls -t "$HOME"/Downloads/client_secret*.json 2>/dev/null | head -1 || true)"
    if [[ -n "$candidate" ]]; then
      mtime="$(stat -f %m "$candidate" 2>/dev/null || echo 0)"
      if [[ "$mtime" -ge "$start_ts" ]]; then found="$candidate"; break; fi
    fi
    sleep 2
  done
  if [[ -z "$found" ]]; then
    warn "rien vu passer dans ~/Downloads après 20 min."
    if is_tty; then
      read -r -p "Chemin du client_secret_*.json téléchargé : " found
    fi
    [[ -n "$found" && -f "$found" ]] || die "client_secret.json introuvable — relance le script quand il est téléchargé."
  fi
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert 'installed' in d, 'pas un client Desktop app'" "$found" \
    || die "ce JSON n'est pas un client OAuth « Desktop app » (clé 'installed' absente). Recrée le client avec le bon type."
  mv "$found" "$SECRET_DEST"
  chmod 600 "$SECRET_DEST"
  ok "client_secret.json rangé dans $SECRET_DEST"
fi

# ── 7. Publication en Production ─────────────────────────────────
step "7/7 · Publication de l'app (évite l'expiration des tokens à 7 jours)"
echo "   Dans la page qui s'ouvre : bouton ${B}Publish app${N} → Confirm."
echo "   (App « non vérifiée » : normal pour un usage perso — chaque compte"
echo "    acceptera l'avertissement une fois à la connexion.)"
open "https://console.cloud.google.com/auth/audience?project=$PROJECT_ID" 2>/dev/null || true
wait_enter

# ── Récap ────────────────────────────────────────────────────────
step "Terminé 🎉"
ok "projet : $PROJECT_ID (propriétaire : $ACCOUNT)"
ok "état persisté : $STATE_FILE"
echo
echo "${B}Prochaine étape — connecter tes comptes :${N}"
echo "   gwsa add perso     # navigateur → choisir le compte → accepter"
echo "   gwsa add <alias>   # répéter pour chaque compte"
echo "   gwsa list"
