---
id: "20261018141856581"
title: Modes de consentement choisis par session (auto / auto-par-service / manuel) + sessions regroupées par projet
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0082
status: idea
pr:
created: 2026-10-18
---

## En clair

Tu veux choisir **à l'ouverture d'une session** mag comment elle accède à Google — comme
le menu Auto / Manuel de Claude Code, mais côté mag, avec **trois modes**. En face, mag
**trace tout** (même en auto), chaque session **affiche sa config**, les sessions sont
**regroupées par projet**, et une config peut être **forcée** (par projet, voire par
session) avec un **défaut** réglable depuis l'app.

Grosse fiche capturée en **idée** : le grooming la découpera, sans doute en épic. P1, à
traiter vite.

## Contexte / Problème

Le modèle de consentement existe, mais il est **éclaté** et **pas pilotable par session** :

- Le mode (manuel / auto) est un **réglage admin global**, pas un choix **à l'ouverture de
  chaque session**. Voir [`20260920141424574`](done/20260920141424574_consentement-une-fois-ou-session.md).
- L'« auto » actuel ne couvre que les **lectures** sous fenêtre ; l'écriture et le partage
  restent signés. Le mode **« auto par service »** (un geste par service, puis libre dans
  ce service) **n'existe pas**.
- Les sessions sont listées ([`0099`](done/0099-sessions-pilote-tri-liste-vignettes.md)),
  mais **pas regroupées par projet**, et une session **n'affiche pas sa config** de mode.
- Une session ne peut **pas** se voir imposer une config **par projet** ; la seule config
  par défaut est le mode admin global.

Verrou technique de fond, à garder en tête : le MCP ne transmet pas d'identifiant de
conversation, et Claude Desktop partage **une** connexion pour tous ses chats. « Par
session » et « par projet » dépendent donc d'abord de **savoir à quelle session / quel
projet un appel appartient**. Voir [`0108`](0108-session-demande-sous-ensemble-droits-compte.md),
[`0101`](0101-nom-de-session-fourni-par-le-client.md) et le socle
[ADR-0007](../docs/adr/ADR-0007-per-session-rights.md).

## Proposition (à groomer)

### A. Les trois modes, choisis à l'ouverture de session

- **Manuel** — un geste (Touch ID) **par service ET par appel**. Le plus strict. Proche de
  l'état actuel.
- **Auto par service** — un geste **la première fois** qu'on touche un service (Gmail,
  Drive, …) ; ensuite, les appels de **ce service** passent sans redemander, pour la portée
  de la session. Un **nouveau** service redemande. Mode neuf.
- **Auto** — tout ce que mag autorise passe, pendant la **durée autorisée** (ex. 30 min),
  sans redemander. Le plus fluide. Rouvre la « fenêtre d'abus » (injection de prompt) :
  **décision produit assumée**, à **borner** (ex. garder le **partage Drive** toujours
  signé). Voir [`20260911135931576`](done/20260911135931576_deverrouillage-transactionnel-vs-minutes.md)
  et [ADR-0011](../docs/adr/ADR-0011-transactional-consent-per-session.md).

### B. Traçabilité — toujours, même en auto

Le serveur **journalise chaque accès demandé**, quel que soit le mode. S'appuie sur le
journal existant : [`0014`](done/0014-journaliser-refus-verrou-usage-jsonl.md) et
[`0102`](done/0102-journal-page-monitoring-filtres-par-session.md).

### C. Config visible (et éditable plus tard) par session

Chaque session **affiche sa configuration** : son mode, ses accès. Édition depuis la
session **plus tard** si besoin. Étend les vues sessions existantes
([`0099`](done/0099-sessions-pilote-tri-liste-vignettes.md),
[`0106`](done/0106-vue-compte-orientee-sessions.md)).

### D. Sessions regroupées par projet

Afficher le **projet** ; à l'ouverture, la **liste de ses sessions**, triées par
**dernière utilisation** (dynamique si possible). Nouveau.

### E. Forcer une config, et un défaut global

- **Forcer une config par projet** — à évaluer : **par session** peut être plus pertinent.
- **Config par défaut pour tout le monde**, réglable depuis l'app. Étend le sélecteur admin
  global déjà livré ([`20260920141424574`](done/20260920141424574_consentement-une-fois-ou-session.md)).

## Critères d'acceptation (esquisse — à compléter au grooming)

- [ ] À l'ouverture d'une session, on choisit le mode : manuel / auto-par-service / auto.
- [ ] Auto-par-service : 1er accès à un service → un geste ; appels suivants du même service
      → sans geste ; nouveau service → redemande.
- [ ] Auto : accès large pendant la durée autorisée ; la borne décidée (ex. partage toujours
      signé) tient.
- [ ] Le journal enregistre chaque accès, dans les **trois** modes.
- [ ] Une session affiche sa config (mode + accès).
- [ ] L'admin regroupe les sessions **par projet**, triées par dernière utilisation.
- [ ] Une config peut être forcée (par projet et/ou par session) ; un défaut global est
      réglable depuis l'app.
- [ ] Clair ET sombre ; `./scripts/test.sh` au vert.

## Comment vérifier

Ouvrir une session en **auto-par-service** : demander une lecture Gmail → un geste ; une 2ᵉ
lecture Gmail → **sans** geste ; demander un accès Drive → **redemande** (nouveau service).
Ouvrir une session en **manuel** → chaque appel redemande. Ouvrir une session en **auto** →
tout passe pendant la fenêtre, sauf la borne retenue. Vérifier dans le journal que **les
trois** modes tracent chaque accès. Dans l'admin, voir les sessions **groupées par projet**,
triées par dernière utilisation, et la **config de chaque session**.

## Notes

- Vient de la session du 2026-10-18 (Thomas), à partir du menu de modes de Claude Code
  (Auto / Manuel).
- **Taille** : dépasse largement 6 critères et 2 surfaces (serveur, admin, modèle de
  consentement). À **découper au grooming** — probablement en épic, sous
  [`0082`](0082-droits-par-session.md), à côté de
  [`0108`](0108-session-demande-sous-ensemble-droits-compte.md) et
  [`0101`](0101-nom-de-session-fourni-par-le-client.md).
- **Dépendance dure** : l'identité de session / projet portée par le client
  ([`0101`](0101-nom-de-session-fourni-par-le-client.md),
  [`0108`](0108-session-demande-sous-ensemble-droits-compte.md), ADR-0007). Sans elle,
  « par session » et « par projet » restent de l'affichage, pas de l'enforcement.
- **Recoupements (pas des doublons)** : modes & durée →
  [`20260911135931576`](done/20260911135931576_deverrouillage-transactionnel-vs-minutes.md),
  [`20260920141424574`](done/20260920141424574_consentement-une-fois-ou-session.md) ;
  sous-ensemble de droits →
  [`0108`](0108-session-demande-sous-ensemble-droits-compte.md) ; journal →
  [`0014`](done/0014-journaliser-refus-verrou-usage-jsonl.md),
  [`0102`](done/0102-journal-page-monitoring-filtres-par-session.md) ; vues sessions →
  [`0099`](done/0099-sessions-pilote-tri-liste-vignettes.md),
  [`0106`](done/0106-vue-compte-orientee-sessions.md).
