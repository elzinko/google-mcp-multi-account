---
id: "20261013221927937"
title: "Test de parité admin ↔ CLI — l'admin n'expose rien que mag ne sache faire"
type: chore
priority: P2
product: google-mcp-multi-account
version:
epic: 0017
status: shipped
ready:
pr: "local (0ca160a)"
created: 2026-10-13
---

## En clair

Le principe « l'admin n'est qu'une façade » ne tient que s'il est **vérifié**. On ajoute un
test qui énumère les actions déclenchables depuis l'admin web et vérifie que chacune a son
équivalent sous `mag`. Sans ce test, la parité reste un vœu. Increment n°3 — celui qui
**ferme** l'épic onboarding.

## Contexte / Problème

L'admin (`admin/server.js`) appelle déjà le provisioning via `/api/setup` (status) et
`/api/sync-iam`. La règle d'architecture (décision 3 du
[cadrage](../20261013215354286_onboarding-pilote-cli-mag-parite-admin.md)) : un endpoint admin
ne fait que **shell une commande `mag`** (ou lire `setup_status`), jamais de logique propre.
Rien ne l'empêche aujourd'hui de dériver. Un test mécanique le garde.

## Proposition

- Recenser les endpoints de l'admin qui déclenchent une action (mutations + lectures d'état).
- Pour chacun, déclarer la commande `mag` équivalente (table `endpoint → mag …`).
- Test : chaque endpoint d'action de `server.js` est couvert par la table, et chaque commande
  citée existe réellement dans `mag`. Échec si un endpoint fait autre chose que shell `mag` /
  lire `setup_status`.

## Critères d'acceptation

- [x] Une table `endpoint admin → commande mag` existe (source unique, dans le test).
- [x] Le test échoue si un endpoint d'action n'a pas d'équivalent `mag`.
- [x] Le test échoue si une commande `mag` citée n'existe pas.
- [x] Intégré à `./scripts/test.sh` (hermétique, sans réseau).

## Comment vérifier

```bash
./scripts/test.sh    # section « parité admin ↔ CLI » verte ;
                     # retirer un équivalent mag d'un endpoint → le test rougit
```

## Notes

- Ferme l'épic onboarding une fois `mag provision` (livré) et les étapes ordonnées en place.
- Garde-fou mécanique, pas un simple commentaire : c'est ce qui rend la parité durable.
- **Le test a révélé un vrai manque** : « Tout verrouiller » de l'admin (`/api/lockall`)
  n'avait pas d'équivalent CLI → ajout de `mag lock --all`. La parité est maintenant
  *vraie*, pas seulement testée — c'est le but du garde-fou.
