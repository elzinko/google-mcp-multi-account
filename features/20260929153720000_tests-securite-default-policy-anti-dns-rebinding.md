---
id: "20260929153720000"
title: Combler deux trous de tests sécurité — invariants DEFAULT_POLICY + admin anti-DNS-rebinding
type: bug
priority: P1
product: google-multi-account
version:
epic:
status: ready
ready: 2026-09-29
pr:
created: 2026-09-29
---

## En clair

Deux garde-fous de sécurité marchent en vrai, mais **aucun test ne les protège**. Sans
test, une modification future peut les casser en silence. Cette fiche ajoute les tests
manquants — **rien que des tests**, zéro changement de comportement.

Carvé depuis la punch-list v1 [[0074]] (deux cases « tests » restées ouvertes).

## Contexte / problème

Deux protections vivantes ne sont pas couvertes :

1. **La policy par défaut** (`gateway/default_policy.py`) fixe des invariants stricts :
   Drive `delete=false`, `share=false`, `zonesOnly=true`, `writeFolders=[]` ; Gmail
   `send=false`. C'est le socle « default-deny ». **Zéro test** ne le vérifie — un
   `DEFAULT_POLICY` élargi par erreur passerait inaperçu.

2. **L'admin refuse le DNS-rebinding** : il rejette une requête dont l'en-tête `Host` ou
   `Origin` n'est pas de confiance (renvoie 403). Le code est là (`admin/server.js`,
   contrôles Host/Origin). **Seul le cas « pas d'en-tête » est testé** ; les cas
   « mauvais Host » et « mauvais Origin » ne le sont pas.

Un test qui manque, c'est une alarme débranchée : le danger est couvert aujourd'hui, mais
plus personne ne le surveille demain.

## Proposition

- **Tests `DEFAULT_POLICY`** : affirmer les invariants un par un (Drive `delete` / `share` /
  `zonesOnly` / `writeFolders`, Gmail `send`), y compris à travers le contrôleur
  `scripts/policy-check.py` si pertinent. Un élargissement accidentel doit faire rougir la
  suite.
- **Tests admin anti-DNS-rebinding** : une requête avec un **mauvais `Host`** → 403 ; une
  requête avec un **mauvais `Origin`** → 403. À côté du cas no-header déjà couvert.
- **Aucun changement de production** : on ne touche qu'aux tests.

## Critères d'acceptation

- [ ] Un test échoue si un invariant de `DEFAULT_POLICY` est relâché (Drive `delete` /
      `share` / `zonesOnly` / `writeFolders`, Gmail `send`).
- [ ] Un test admin vérifie : mauvais `Host` → 403, mauvais `Origin` → 403.
- [ ] `./scripts/test.sh` reste vert ; aucun fichier de production modifié.

## Comment vérifier

- Lancer `./scripts/test.sh` : les nouveaux tests passent.
- Preuve qu'ils mordent : relâcher un invariant en local (ex. `share=true`) → le test
  rougit ; remettre → il repasse. Ne pas committer le relâchement.

## Notes

- Reprend deux cases « À faire » de [[0074]] (volet tests) : « Tests admin
  anti-DNS-rebinding » et « Test `DEFAULT_POLICY` ». Le reste de 0074 (site DNS, hygiène
  repo, durcissements latents) reste géré dans 0074.
- Fichiers concernés : `gateway/default_policy.py`, `scripts/policy-check.py`,
  `admin/server.js` (contrôles Host/Origin), et les suites de tests correspondantes.
