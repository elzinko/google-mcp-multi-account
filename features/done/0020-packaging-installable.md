---
id: 0020
title: Installer & mettre à jour sans clone — installeur curl puis tap Homebrew
type: feature
priority: P1
version:
epic: 0017
status: shipped
ready: 2026-08-01
pr: "#78"
created: 2026-07-24
updated: 2026-08-01
---

## Contexte / Problème

L'install et l'update d'aujourd'hui exigent un **clone git présent sur le poste** :

- Install : `git clone` → symlink `gwsa` bootstrap → `provision-gcp.sh` →
  `update.sh` (qui sert de premier install). Cf. [[0010]], [[0013]].
- Update : `gwsa update` lit les **tags git du clone** ; depuis la copie
  installée, il suit un fichier `.source` qui pointe vers le clone. Supprimer le
  clone → `gwsa update` meurt (« clone source introuvable »). Cf. [[0029]], [[0030]].

Aucun produit connu (Docker, brew, gh) ne demande de garder un clone pour se
mettre à jour. C'est **le** principal écart au standard. La mécanique interne est
pourtant excellente (versionné, symlink `current` atomique, rollback, rewire) :
il ne manque qu'un **canal de distribution découplé du clone**.

## Décision (2026-08-01)

Canal retenu, dans l'ordre : **1) installeur `curl … | bash`**, puis **2) tap
Homebrew**. Objectif : « le plus standard et simple possible » (demande utilisateur).

Le déclic qui rend ça simple : **GitHub sert déjà un tarball par tag**
(`…/archive/refs/tags/vX.Y.Z.tar.gz`) et expose l'API `…/repos/…/tags`. Donc
`install.sh` et `gwsa update` peuvent tirer une version **sans clone** et **sans
artefact de release custom** — ils réutilisent tel quel le reste de
[deploy-local.sh](../scripts/deploy-local.sh) (extraction → `current` → rewire → broker).

Contraintes héritées de [[0042]] (à respecter) : nom de connecteur **fixe**
`google-multi-account` (pas de version dans le titre — sinon reset des
permissions d'outils), bascule `current` réservée au rail **stable**.

## Proposition

**Phase 1 — installeur `curl` + update sans clone**

- `install.sh` (hébergé, `curl -fsSL … | bash`) : vérifie les prérequis (macOS,
  `python3`, `gws` via brew), télécharge le dernier tag, extrait dans
  `~/.local/share/google-mcp/<tag>/`, bascule `current`, pose `gwsa` sur le PATH,
  branche Desktop + Code, puis **imprime** les étapes OAuth/GCP restantes (renvoi
  vers `provision-gcp.sh` / `setup_status` — jamais exécutées à la place de l'humain).
- `gwsa update` : quand il n'y a pas de clone (`.git` absent **et** `.source`
  absent), tire depuis l'API GitHub + tarball ; garde le chemin clone comme
  **fallback contributeur**. Conserve `--to`, `--check`, `--force`.

**Phase 2 — tap Homebrew**

- `brew install elzinko/tap/google-mcp` / `brew upgrade` — le standard macOS.
  Formule pointant sur le tarball du tag. Dépend de [[0028]] (releases propres).

**À évaluer (hors scope immédiat)**

- Desktop Extension **`.mcpb`** : un-clic pour le **branchement Desktop** seul (ne
  couvre pas `gws`, l'OAuth, la CLI `gwsa`, le broker) — complément, pas substitut.
- Cross-platform (Linux/Intel) : [[0018]].

## Critères d'acceptation

- [x] Un utilisateur installe **sans cloner le repo** ni éditer un chemin (`curl … | bash`). — `install.sh`
- [x] `gwsa update` met à jour **sans clone présent** (tarball GitHub), clone = fallback.
- [x] Suppression du clone → l'update fonctionne encore (copie marquée `.origin`, ni `.git` ni `.source`).
- [x] Nom de connecteur inchangé (`google-multi-account`) après update (branchement partagé, pas de reset perms).
- [x] Rollback (`--to vX.Y.Z`) et `--check` conservés.
- [x] Tests hermétiques verts (fixtures `file://`, zéro réseau — section dédiée dans `test.sh`).

> **Phase 1 livrée** (branche `feat/0020-install-update-sans-clone`) : `install.sh`
> (curl · racine du repo), `scripts/lib-github-release.sh`, `deploy-local.sh --github`,
> `update.sh` bascule GitHub sans clone. **Phase 2** (tap Homebrew) : à suivre.

## Notes

- Dédoublonnage : cette fiche **absorbe** l'idée « install/update pour n'importe
  qui » parquée dans [[0042]] §B. GitHub Releases = [[0028]]. README/persona =
  [[0070]]. Site de doc en ligne = [[0072]]. Version annoncée = [[0026]].
- Épic [[0017]] (généraliser à d'autres utilisateurs). Dépend de [[0018]] pour un
  paquet non-macOS.
