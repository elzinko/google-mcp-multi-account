---
id: 0047
title: Au moment d'autoriser un accès, nommer le compte (email) — pas seulement l'alias
type: feature
priority: P2
version:
epic:
status: in-progress
ready: 2026-07-29
pr: "#75"
created: 2026-07-29
---

## Contexte / Problème

Quand l'humain **autorise** un accès (déverrouiller un profil, ouvrir une zone
Drive), les deux points de contact ne montrent que l'**alias** — jamais l'adresse
Gmail réelle :

- le message d'`access_request` renvoyé par le MCP (« Le profil « perso » est
  verrouillé… ») — [gateway/api.py:647-809](gateway/api.py) ;
- le dialogue **Touch ID** de l'élicitation signée (« gwsa : déverrouiller
  « perso » ») — [gateway/elicitation.py:114-140](gateway/elicitation.py) et
  [scripts/elicitation-sign.swift:178-206](scripts/elicitation-sign.swift).

Or c'est **le seul moment qui est une décision de sécurité** : « est-ce que
j'autorise l'agent à toucher CE compte ? ». À cet instant, `« perso »` est
abstrait ; l'email est la vérité terrain de *quelle boîte Gmail réelle j'expose*.
Partout où l'enjeu est faible (`gwsa list`, `profiles_list`, `setup_status`,
admin web), l'email **est** affiché à côté de l'alias — l'asymétrie est donc
inversée.

Régression silencieuse, pas un angle jamais envisagé : la fiche 0032 voulait
nommer le compte, et la fonction `strong_auth_reason()` ([bin/gwsa:124](bin/gwsa))
devait mettre l'**email** dans la raison Touch ID. Le passage à l'élicitation
signée (fiche 0001 / ADR-0005) est passé par-dessus et `strong_auth_reason` est
devenu **du code mort** (jamais appelé — seule référence vivante : un `grep`
d'existence dans `scripts/test.sh`).

## Proposition

Afficher l'email **à côté** de l'alias aux deux points d'autorisation, sans jamais
toucher à l'alias comme clé opérationnelle (dossier de profil, verrous, policy,
journal — ADR-0002 : l'alias reste la clé, l'email est une métadonnée).

- **Payload signé** : injecter l'email dans le payload d'élicitation
  (`build_payload` gagne un champ `email`, reconstruit au seul point de vérité
  [gateway/elicitation.py:143](gateway/elicitation.py)). L'email est alors
  **cryptographiquement lié** à la signature biométrique : le reçu enregistre le
  compte exact autorisé, pas seulement l'alias.
- **`bin/gwsa`** : calcule l'email via `profile_email <dir>` (métadonnée `.email`,
  lisible même verrouillé) et l'ajoute aux payloads `session_unlock`, `unlock`,
  `session_grant`, `grant`.
- **Texte du prompt** (Python `prompt_from_payload` **et** Swift `promptText`,
  maintenus alignés) : `« perso » (perso@gmail.com)`.
- **Message `access_request`** (MCP) : nommer le compte `« perso »
  (perso@gmail.com)` dans les branches unlock / grant / project_grant.
- **Repli gracieux** : `.email` inconnu (vieux profil, non backfillé) → alias seul,
  comportement actuel. Aucune régression.
- **Ménage** : supprimer le code mort `strong_auth_reason()` et remplacer son
  `grep` d'existence par un test de comportement réel (le prompt contient l'email).

## Critères d'acceptation

- [ ] Le dialogue Touch ID d'un unlock/grant nomme le compte : `« alias » (email)`
- [ ] Le message `access_request` (unlock, grant, project_grant) nomme le compte
- [ ] L'email est **dans le payload signé** (reçu d'élicitation → compte autorisé)
- [ ] Email inconnu → repli sur l'alias seul, sans erreur
- [ ] L'alias reste l'unique clé (dossier, verrou, policy, journal) — rien changé là
- [ ] Code mort `strong_auth_reason` retiré ; test remplacé par un test de comportement
- [ ] Suite hermétique verte (`./scripts/test.sh`), Python + Swift alignés

## Notes

- Né de la discussion « les alias sont-ils essentiels ? » (2026-07-29) : oui comme
  clé, non comme seul affichage au moment d'autoriser.
- Continuité 0032 / 0044 (« Touch ID nomme le compte et le produit »).
- ADR-0002 (email = métadonnée hors verrou), ADR-0005 (élicitation signée).
