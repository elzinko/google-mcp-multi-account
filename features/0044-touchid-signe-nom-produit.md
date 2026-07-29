---
id: 0044
title: Sous strongauth, le dialogue Touch ID nomme « swift-frontend » au lieu du produit
type: bug
priority: P2
version:
epic:
status: in-progress
ready: 2026-07-29
pr: "#74"
created: 2026-07-29
---

## Contexte / Problème

Suite de la fiche 0032 (qui a nommé le binaire produit dans le dialogue Touch ID).
Constaté pendant le test manuel `gwsa-grant-resolve-nom` (2026-07-29) : **sous
strongauth**, la boîte système Touch ID affiche encore « **swift-frontend** » comme
demandeur, au lieu du nom produit.

Cause : 0032 a nommé le binaire pour le chemin Touch ID « simple »
(`scripts/touchid.swift`). Mais quand strongauth est actif, le geste passe par
l'**élicitation signée** (fiche 0001, `scripts/elicitation-sign.swift`), lancée via
`/usr/bin/swift` dans `gateway/elicitation.py` (`_swift_sign` / `enroll_secure`). Ce
chemin **n'utilisait aucun binaire nommé** : `GWSA_TOUCHID_BIN` était exporté par
`bin/gwsa` mais **jamais lu** côté Python (code mort depuis le passage à la
signature). macOS nommait donc le process appelant = « swift-frontend ». Comportement
identique sur `main` — ce n'est pas une régression de version, c'est un angle mort de
0032 (qui l'annonçait à demi : « la provenance dure relève de la fiche 0001 »).

## Proposition

Compiler le helper réellement utilisé sous strongauth (`elicitation-sign.swift`) en
**binaire nommé** et l'exécuter à la place de `swift <script>`, avec repli sur `swift`
si indisponible (dialogue « swift-frontend » dégradé, jamais bloquant). Le nom du
binaire devient une **source de vérité unique** (`gateway/config.py:PRODUCT_SLUG`),
réutilisée par `bin/gwsa` (compilation) et `scripts/test.sh` (assertion) ; artefact
isolé et gitignoré dans `bin/.build/` (`.gitignore` indépendant du nom).

## Critères d'acceptation

- [x] Sous strongauth, le dialogue Touch ID nomme le produit (`google-multi-account`), plus « swift-frontend »
- [x] Les deux chemins signés (`sign` **et** `enroll`) passent par le binaire nommé ; repli `swift` conservé
- [x] Nom défini à **un seul endroit** (`PRODUCT_SLUG`) — un rebrand = une ligne
- [x] Accès à la clé inchangé (mode fichier, `errSecMissingEntitlement` sur binaire non signé) : même Touch ID, même signature
- [x] Suite hermétique verte + **test de non-régression** (élicitation signée ≠ `swift` nu)

## Notes

- Découvert via le test manuel `gwsa-grant-resolve-nom` (comme 0032 est né du test drive-2-comptes).
- `PRODUCT_SLUG = "google-multi-account"` — aligné sur le nom du serveur MCP.
- Voir fiche 0032 (nommage du chemin non signé) et fiche 0001 (élicitation signée, provenance dure).
- Discussion nom écartée ici : renommer la commande `gwsa`→`gma` (filiation avec l'outil `gws` ;
  un renommage de commande est une passe dédiée, hors périmètre de ce correctif).
