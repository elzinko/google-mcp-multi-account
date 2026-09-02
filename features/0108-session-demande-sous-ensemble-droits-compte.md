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

Bonne nouvelle : la **plomberie existe déjà**. Le backend sait accorder un droit fin par session
(`session_grant_capability`, service × opération × ressource, signé — [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md), fiche [`0076`](done/0076-droits-par-session-phase-a.md) livrée). Ce qui manque, c'est **le
parcours qui l'utilise** : demander ce sous-ensemble, l'accorder, puis le **montrer**.

> **Question ouverte assumée.** Cette fiche est d'abord un **« savoir si c'est possible »**. Le
> point dur est connu : le protocole MCP ne transmet pas d'identifiant de conversation, et
> Claude Desktop partage **une** connexion pour tous ses chats (ADR-0007, « branché à vide »).
> Il faut donc **constater** ce qu'un client réel peut faire porter comme jeton par conversation
> **avant** de promettre l'enforcement. D'où le statut `idea`.

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
tenir que **son** sous-ensemble demandé. Il manque le **parcours** (demande + octroi + preuve),
pas le modèle.

## Proposition (à groomer)

1. **Constat de faisabilité (spike).** Vérifier, sur un client réel (Claude Desktop, Cursor),
   ce qu'on peut faire **porter par conversation** (jeton / paramètre de session). Sans ça, pas
   d'enforcement par session — seulement de l'affichage. Résultat **daté** dans la fiche.
2. **Demande d'un sous-ensemble.** Une session demande explicitement **service × opération ×
   ressource** dans le plafond du compte (pas le compte entier). Réutilise
   `session_grant_capability` + l'élicitation signée. **Default-deny** par session.
3. **Exposer le parcours** dans l'admin et/ou le flux d'élicitation : voir ce qu'une session a
   **demandé** et ce qui lui est **accordé**, et pouvoir le révoquer.
4. **Preuve par session** : le journal montre, par session, quel service/opération a été touché
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
