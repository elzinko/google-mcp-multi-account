---
id: 0018
title: Cross-platform — faire tourner le projet hors macOS (Linux, Intel)
type: feature
priority: P2
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-07-24
---

## Contexte / Problème

Le chemin de production est **macOS Apple Silicon uniquement**, et ce n'est écrit
nulle part (corrigé côté README par le tag plateforme). Points de couplage OS
relevés à l'audit :

- Clé de chiffrement maître dans le **Trousseau macOS** (`bin/gwsa`).
- Présence humaine via **Touch ID** (`/usr/bin/swift` + `touchid.swift`).
- Symlink **`/opt/homebrew/bin/gwsa`** codé en dur (README, faux sur Intel/Linux).
- `stat -f %m` (BSD), `open`, surveillance de `~/Downloads` (`provision-gcp.sh`).

Seuls `test.sh` (hermétique, tourne déjà sur ubuntu-latest en CI) et
`install-claude-desktop.sh` (case Darwin/Linux) sont portables.

## Proposition

Abstraire les points OS derrière une couche mince :

- **Stockage de la clé** : Trousseau (macOS) / `secret-tool`/libsecret (Linux) ;
  fallback fichier chiffré + passphrase si aucun keyring.
- **Présence humaine** : Touch ID sur macOS, dégradé documenté ailleurs
  (strongauth optionnel, pas requis).
- **Chemins** : résoudre le préfixe via `brew --prefix` / PATH, plus de
  `/opt/homebrew` en dur.
- **Utilitaires** : remplacer `stat -f`, `open` par des équivalents portables.

## Critères d'acceptation

- [ ] Installation + `gwsa list` + une lecture Gmail fonctionnent sur Linux.
- [ ] Aucun chemin `/opt/homebrew` ni binaire macOS-only sur le chemin nominal.
- [ ] La clé de chiffrement se stocke via un backend portable (keyring Linux OK).
- [ ] CI : un smoke d'install/exécution Linux en plus des tests hermétiques.

## Notes

Portée volontairement « faire tourner », pas « parité parfaite ». Touch ID reste
un plus macOS. Voir épic [[0017]].
