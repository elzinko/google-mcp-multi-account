---
id: 0108
title: Session — demander un sous-ensemble des droits du compte (accès fin, vérifiable par session)
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0082
status: idea
ready:
pr:
created: 2026-09-03
---

## En clair

Aujourd'hui, quand une conversation a besoin d'un compte Google, elle **déverrouille le compte
en entier** — tous les services que la policy autorise. Toi, tu veux l'inverse : qu'une session
**demande seulement le sous-ensemble dont elle a besoin** (par exemple « juste lire Gmail »),
choisi **parmi ce que le compte permet en général**. On peut alors vérifier, **session par
session**, exactement à quoi chacune a touché.

La **primitive existe** : le backend sait accorder un droit fin par session
(`session_grant_capability`, service × opération × ressource, signé — [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md), fiche [`0076`](done/0076-droits-par-session-phase-a.md) livrée). Mais **elle ne suffit pas** : aujourd'hui, franchir la
porte d'un compte verrouillé **force** un accès **complet** (joker `*`), pas un sous-ensemble. Il
manque donc **deux choses** : un **changement de modèle** (séparer « franchir le verrou » de « tout
ouvrir ») **et** le parcours qui demande, accorde et montre le sous-ensemble.

> **Questions ouvertes assumées.** Cette fiche est d'abord un **« savoir si c'est possible »**.
> Deux points durs. **Un** : le protocole MCP ne transmet pas d'identifiant de conversation, et
> Claude Desktop partage **une** connexion pour tous ses chats (ADR-0007, « branché à vide ») — à
> **constater** sur un client réel. **Deux** : l'enforcement actuel équivaut « déverrouillé » à
> « accès complet » (joker `*`), donc le sous-ensemble fin exige un **changement de modèle** (cf.
> Contexte). D'où le statut `idea`.

**Pas urgent — on peut faire sans pour l'instant.** Mais c'est important. À faire **après** la
refonte admin (épic [`0060`](0060-admin-ux-ui-refresh.md)) et la fiche [`0107`](0107-vue-compte-droits-sur-place.md).

## Contexte / problème

Trois grains coexistent côté session (`gateway/sessions.py`) :

- **`session_unlock`** (`:296`) — déverrouille **un compte entier** pour la session.
- **`session_grant_drive`** — accorde une **zone d'écriture Drive**.
- **`session_grant_capability`** (`:466`) — accorde un **droit fin** (service × opération ×
  ressource), signé, non auto-élargissable.

Le grain fin **existe**, mais l'admin **ne l'expose pas** : le code le dit noir sur blanc —
« Droits fins par service (`session_grant_capability`). L'API admin ne les expose pas à ce jour »
(`admin/index.html:2915`). En pratique, le seul geste offert est le **déverrouillage du compte
entier**. D'où ton impression — juste — qu'« une session a automatiquement tous les accès ».

Le modèle voulu est pourtant clair (ADR-0007) : droits effectifs = **policy compte ∩ capacités
session** (intersection, *fail-closed*). La **policy est le plafond** ; la session ne devrait
tenir que **son** sous-ensemble demandé.

**Mais l'enforcement actuel court-circuite ce plafond** (revue Codex #129, vérifié dans le code) :

- Sur un profil **verrouillé**, `_require_access` (`gateway/broker_server.py:202`) **refuse** la
  session tant que `is_session_unlocked()` est faux. Un grant fin `gmail:read` **seul** ne franchit
  donc pas la porte.
- Or franchir la porte pose `session_full_access` (`:246`), et `check_policy` y **injecte le joker**
  `{"service":"*","operation":"*"}` (`:181`) → **tout** ce que la policy du compte autorise.
- **Second verrou avant le broker** : `gateway/api.py::_run` (`:118`) refuse **aussi** la session
  sur profil verrouillé tant que `is_session_unlocked()` est faux. Le changement de modèle doit
  couvrir **les deux portes**, pas seulement le broker.

Résultat : soit la session est verrouillée (aucun accès), soit déverrouillée (**accès complet**). Le
sous-ensemble fin n'est **pas** enforçable aujourd'hui. Il ne manque donc **pas que le parcours** :
il faut **séparer** « franchir le verrou du compte » de « recevoir le joker complet ».

## Proposition (à groomer)

1. **Constat de faisabilité (spike).** Vérifier, sur un client réel (Claude Desktop, Cursor),
   ce qu'on peut faire **porter par conversation** (jeton / paramètre de session). Sans ça, pas
   d'enforcement par session — seulement de l'affichage. Résultat **daté** dans la fiche.
2. **Changement de modèle (le vrai verrou technique).** Séparer **franchir le verrou** du compte
   de **recevoir le joker complet**. Concrètement : permettre à une session de **passer les DEUX
   portes** (`gateway/api.py:118` **et** `gateway/broker_server.py:202`) en portant **seulement**
   ses capacités fines, sans que le déverrouillage ne pose `session_full_access` ni le joker `*`
   (`broker_server.py:181/246`). Sans ça, `gmail:read` seul reste inutilisable. Prévoir un **test
   « profil verrouillé »** couvrant les deux portes.
3. **Demande d'un sous-ensemble.** Une session demande explicitement **service × opération ×
   ressource** dans le plafond du compte (pas le compte entier). Réutilise
   `session_grant_capability` + l'élicitation signée. **Default-deny** par session.
4. **Exposer le parcours** dans l'admin et/ou le flux d'élicitation : voir ce qu'une session a
   **demandé** et ce qui lui est **accordé**, et pouvoir le révoquer.
5. **Preuve par session** : le journal montre, par session, quel service/opération a été touché
   (déjà loggé avec `session_id` — voir fiche [`0102`](0102-journal-page-monitoring-filtres-par-session.md)).

## Relation aux fiches voisines (pas un doublon)

- [`0076`](done/0076-droits-par-session-phase-a.md) — **livrée** : la plomberie (jeton porté,
  capacités fines signées). Cette fiche s'appuie dessus.
- [`0045`](0045-capacites-projet-signees.md) — **analyse** d'avant Phase A (état des lieux). Ici
  c'est le **parcours produit**, pas l'analyse.
- [`0106`](0106-vue-compte-orientee-sessions.md) — **affiche** les droits par session (lecture).
  Ici c'est **demander/accorder** le sous-ensemble (écriture du droit), pas seulement le montrer.
- Épic parent : [`0082`](0082-droits-par-session.md).

## Critères d'acceptation (esquisse — à compléter au grooming)

- [ ] Constat daté : ce qu'un client réel peut porter par conversation (jeton/paramètre).
- [ ] Une session peut demander un **sous-ensemble** de droits (pas le compte entier), dans le plafond de la policy.
- [ ] **Test profil verrouillé** : sur un compte verrouillé, une session portant `gmail:read` seul **passe les deux portes** (`gateway/api.py` **et** `gateway/broker_server.py`) et ne peut lire **que** Gmail — le déverrouillage n'injecte **plus** le joker `*`. (Défend contre le court-circuit du plafond relevé par la revue #129.)
- [ ] L'octroi passe par l'élicitation signée ; default-deny par session ; pas d'auto-élargissement.
- [ ] L'admin (ou le flux) montre, par session, le demandé et l'accordé, et permet la révocation.
- [ ] Le journal permet de vérifier, par session, à quoi elle a accédé.
- [ ] Clair ET sombre ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir deux sessions sur le même compte. La première demande « lire Gmail » seulement ; la
seconde « écrire dans le dossier Drive X ». Vérifier que chacune ne peut faire **que** ce qu'elle
a demandé, que l'admin le montre par session, et que le journal, filtré par session, confirme les
accès réels. Vérifier qu'un déverrouillage du compte entier n'est **plus** le seul geste possible.

## Notes

- **Séquencement** : P1, mais **après** l'épic 0060 (admin) et 0107. À porter dans `PLAN.md` au
  moment de le décider.
- **Limite de menace inchangée** (ADR-0007) : sans vault (fiche 0003), le modèle reste
  coopératif — un shell libre contourne. Cette couche **durcit**, elle ne rend pas étanche.
