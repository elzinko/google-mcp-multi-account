# lib/cli-link.sh — retargeting du lien PATH « mag » (+ alias gma/gwsa) sur la
# copie déployée courante. Partagé entre update.sh et deploy-local.sh (fiche
# 0081) : les deux doivent replier sur bin/gwsa puis bin/gma quand
# current/bin/mag n'existe pas — rollback à travers le renommage gma→mag
# (#114 round 5). Avant ce fichier, la logique n'existait que dans update.sh ;
# deploy-local.sh --rollback ne reciblait rien du tout.
#
# Attend que le script appelant ait déjà défini ok()/warn() (mêmes fonctions
# d'affichage dans update.sh et deploy-local.sh).
#
# Usage : source ce fichier, puis retarget_cli_links "<src_clone>" "<deploy_root>"

# resolve_cli_link — chemin du lien PATH à gérer, indépendamment de
# l'exécutabilité de sa cible actuelle.
#
# `command -v mag` IGNORE un symlink dont la cible n'existe plus (Codex #114
# round 5, finding P1). Lors d'un rollback qui bascule « current » avant que
# les liens soient reciblés, les 3 liens installés pointent alors vers un
# binaire absent : « command -v » ne renvoie plus rien, et le repli sur
# bin/gwsa ne s'applique jamais puisqu'on ne trouve même plus le lien à
# réparer. On cherche donc le LIEN lui-même (test -L, qui ne se soucie pas de
# la cible) dans les dossiers du PATH, plutôt que de demander à command -v de
# le résoudre.
resolve_cli_link() {
  if [[ -n "${GWSA_CLI_LINK:-}" ]]; then
    printf '%s' "$GWSA_CLI_LINK"
    return 0
  fi
  local dir name dirs
  IFS=':' read -ra dirs <<< "$PATH"
  for name in mag gma gwsa; do
    for dir in "${dirs[@]}"; do
      [[ -n "$dir" && -L "$dir/$name" ]] && { printf '%s' "$dir/$name"; return 0; }
    done
  done
  # dernier repli : le classique command -v (couvre un exécutable réel, ou un
  # lien dont la cible existe encore — cas courant, pas de rollback en cours).
  command -v mag 2>/dev/null || command -v gma 2>/dev/null || command -v gwsa 2>/dev/null || true
}

# retarget_cli_links <src_clone_dir> <deploy_root> — pose/rafraîchit le lien
# PATH « mag » et les alias « gma »/« gwsa » sur le binaire de la version
# COURANTE déployée (current), avec repli sur bin/gwsa puis bin/gma quand
# current/bin/mag est absent (rollback vers une release pré-renommage).
retarget_cli_links() {
  local src="$1" deploy_root="$2"
  local link expected target _name _nlink

  # Garde-fou de bac à sable : si le dépôt d'installation est surchargé (suite
  # de tests) sans que le lien à gérer soit désigné explicitement, on ne
  # touche à RIEN. Un test ne doit jamais pouvoir réécrire le mag du PATH réel
  # — c'est arrivé une fois, en retirant une garde pendant un test de mutation.
  if [[ -n "${GWSA_DEPLOY_ROOT:-}" && -z "${GWSA_CLI_LINK:-}" ]]; then
    warn "dépôt d'installation surchargé sans GWSA_CLI_LINK — lien du PATH laissé tel quel"
    return 0
  fi

  link="$(resolve_cli_link)"
  # cible = le binaire de la version installée. Rollback vers une release
  # pré-renommage : elle n'a que bin/gwsa/bin/gma — on s'y replie.
  expected="$deploy_root/current/bin/mag"
  [[ -x "$expected" ]] || expected="$deploy_root/current/bin/gwsa"
  [[ -x "$expected" ]] || expected="$deploy_root/current/bin/gma"

  [[ -n "$link" ]] || { warn "mag absent du PATH — lien non posé"; return 0; }
  [[ -x "$expected" ]] || { warn "binaire absent de la copie installée — liens inchangés"; return 0; }

  if [[ ! -L "$link" ]]; then
    warn "« $link » n'est pas un lien symbolique — laissé tel quel"
    return 0
  fi
  target="$(readlink "$link")"
  if [[ "$target" == "$expected" ]]; then
    ok "mag du PATH déjà sur la copie installée"
    # ne PAS return : on continue pour (re)poser les alias gma/gwsa manquants
  else
    case "$target" in
      "$src"/bin/mag|"$deploy_root"/*/bin/mag) ;;
      # cibles legacy d'une install antérieure (lien nommé gma/gwsa) — à migrer aussi
      "$src"/bin/gma|"$src"/bin/gwsa|"$deploy_root"/*/bin/gma|"$deploy_root"/*/bin/gwsa) ;;
      *) warn "mag du PATH pointe « $target » (hors projet) — laissé tel quel"; return 0 ;;
    esac
    if ln -sfn "$expected" "$link" 2>/dev/null; then
      ok "mag du PATH → $expected"
    else
      warn "impossible de réécrire « $link » — à refaire à la main : ln -sfn \"$expected\" \"$link\""
    fi
  fi

  # poser/rafraîchir « mag » (nom courant) + les alias dépréciés « gma »/« gwsa »
  # à côté, vers la MÊME cible $expected (repliée sur gwsa/gma au rollback) : une
  # install antérieure n'a QUE gma/gwsa, il faut donc y créer mag, sinon les
  # commandes « mag … » manqueraient au PATH après « update » (Codex #92, #114).
  for _name in mag gma gwsa; do
    _nlink="$(dirname "$link")/$_name"
    if [[ -e "$_nlink" && ! -L "$_nlink" ]]; then
      warn "« $_nlink » n'est pas un lien symbolique — laissé tel quel"
    elif ln -sfn "$expected" "$_nlink" 2>/dev/null; then
      ok "$_name du PATH → $expected"
    else
      warn "impossible de poser « $_nlink » — à faire à la main : ln -sfn \"$expected\" \"$_nlink\""
    fi
  done
}
