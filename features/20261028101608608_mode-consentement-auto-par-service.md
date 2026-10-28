---
id: "20261028101608608"
title: Mode de consentement « auto par service » (un geste par service, libre ensuite dans la session)
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0082
status: ready
ready: 2026-10-28
pr:
created: 2026-10-28
---

## En clair

Aujourd'hui, une session a **deux** façons d'accéder à Google. **Manuel** : un geste (Touch
ID) à chaque appel. **Auto** : tout passe pendant une fenêtre de temps. On veut un **troisième
mode, au milieu : « auto par service »**. Un geste **la première fois** qu'une session touche
un service — Gmail, Drive, Agenda… — puis **tous les appels suivants de ce même service
passent sans redemander**, pour la durée de la session. Un **autre** service redemande un
geste.

C'est le mode du menu de Claude Code transposé à mag. Moins de friction que « manuel », plus
de contrôle que « auto ».

Cette fiche est **carvée** de la grosse idée [`20261018141856581`](20261018141856581_modes-consentement-et-sessions-par-projet.md)
(§A). On ne prend **que** ce mode, parce que c'est la seule brique de cet axe qui ne dépend
**pas** d'une identité de conversation portée par le client (limite externe du MCP, voir
[`0108`](0108-session-demande-sous-ensemble-droits-compte.md) et
[`0101`](0101-nom-de-session-fourni-par-le-client.md)).

## Contexte / Problème

Le consentement transactionnel (ADR-0011/0012/0013) connaît **deux** modes, lus par
`gateway/sessions.py::transactional_lease_mode()` :

- **`manuel`** — un geste signé par **acte**. Une grâce existe, mais **bornée à l'acte**
  (`gateway/api.py`, `grace_eligible = (mode == "manuel" and not _is_delegated_session(sid))`).
- **`auto`** — les **lectures** passent sous un **bail** de durée ; les **mutations** restent
  un geste par acte.

Il manque le grain **par service** : « je consens une fois pour Gmail dans cette session, puis
Gmail est libre, mais Drive redemandera ». Vérifié : aucune occurrence de `auto-par-service`
dans `gateway/` ni `admin/` — le mode n'existe pas.

**Borne de sécurité héritée, non négociable.** Le **partage Drive** (`drive permissions
create/delete`) reste **toujours signé**, même en auto-par-service — jamais couvert par la
grâce. C'est la règle déjà en place dans le modèle livré (garde-fou partage, `gateway/api.py`,
« le partage n'est jamais éligible à la grâce »). Ce mode ne la desserre pas.

## Proposition

1. **Troisième valeur de mode** : `manuel` | `auto-par-service` | `auto`. Étend le réglage lu
   par `transactional_lease_mode()` et le sélecteur admin déjà livré
   ([`20260920141424574`](done/20260920141424574_consentement-une-fois-ou-session.md)).
2. **Grâce par service, scopée à la session.** Au premier acte sur un service `S`, le geste
   normal s'applique (acte signé pour une mutation, bail pour une lecture). Une fois consenti,
   mag pose une **capacité de grâce de session** `(service=S, operation=*, resource="")`,
   bornée par **policy ∩ manifeste** (intersection ADR-0007, **sans** joker `*`). Les appels
   suivants de `S` dans la session la retrouvent et passent **sans geste**. Réutilise le
   mécanisme de grâce existant (`Capability(expires_at=0)` scopée, ADR-0013) — on **élargit**
   sa portée de l'acte au service, on n'invente pas un second système.
3. **Le partage reste exclu de la grâce.** La capacité de grâce par service **n'inclut jamais**
   `permissions:create` / `permissions:delete` : un partage redemande toujours un geste signé.
4. **Nouveau service = nouveau geste.** Un service jamais touché dans la session n'a pas de
   grâce → geste normal.
5. **Fail-closed.** Un appel non classable (service inconnu) ne bénéficie d'aucune grâce :
   geste requis, régime le plus strict (aligné sur `_classify_operation`).
6. **Journal inchangé, toujours.** Chaque accès reste journalisé avec `session_id`, dans ce
   mode comme dans les deux autres (pas de régression de traçabilité).

## Critères d'acceptation

- [ ] Le mode de consentement accepte une **troisième** valeur `auto-par-service`, réglable
      depuis l'admin, à côté de `manuel` et `auto`.
- [ ] **Premier accès à un service** dans une session → **un** geste (acte signé si mutation,
      bail si lecture).
- [ ] **Deuxième appel du même service** dans la **même** session → **passe sans geste**.
- [ ] **Nouveau service** (jamais touché dans la session) → **redemande** un geste.
- [ ] **Partage Drive toujours signé** : en `auto-par-service`, un `drive permissions
      create`/`delete` **redemande** un geste même si le service Drive a déjà été consenti.
- [ ] La grâce par service est **bornée par policy ∩ manifeste** (jamais de joker `*`) et
      **scopée à la session** (une autre session ne la voit pas).
- [ ] Le journal enregistre **chaque** accès en mode `auto-par-service` (parité avec les deux
      autres modes).
- [ ] Fail-closed : service non classable → geste requis, aucune grâce.
- [ ] Admin **clair ET sombre** ; `./scripts/test.sh` au vert, avec un test dédié qui prouve
      les quatre comportements ci-dessus (1er geste, 2ᵉ libre, nouveau service redemande,
      partage toujours signé).

## Comment vérifier

Régler une session en **`auto-par-service`**. Demander une **lecture Gmail** → un geste.
Demander une **2ᵉ lecture Gmail** → **sans** geste. Demander un **accès Drive** → **redemande**
(nouveau service). Après avoir consenti Drive, tenter un **partage Drive** → **redemande**
quand même (borne). Ouvrir une **autre** session : elle ne doit **pas** hériter de la grâce
Gmail de la première. Enfin, ouvrir le journal filtré par session et vérifier que **chaque**
accès est tracé.

Rejouable : `./scripts/test.sh` (section dédiée au mode `auto-par-service`).

## Notes

- **Pourquoi carvée séparément.** La fiche mère [`20261018141856581`](20261018141856581_modes-consentement-et-sessions-par-projet.md)
  demandait aussi « par session » / « par projet » (§C, §D, §E). Ces parties **butent** sur une
  limite externe : le MCP ne transmet pas d'identité de conversation, Claude Desktop partage
  une connexion pour tous ses chats. Elles restent **affichables mais non enforçables**, donc
  hors de ce lot. `auto-par-service` ne dépend **que** du `session_id` déjà porté (jeton
  `mag session open`), qui existe aujourd'hui.
- **Sécurité.** Ce mode **relâche** le per-acte vers le per-service-par-session : une fenêtre
  d'abus par service s'ouvre (prompt injection). Décision produit **déjà prise** par Thomas en
  demandant ce mode (fiche mère, 2026-10-18). La borne « partage toujours signé » limite le
  pire cas, comme pour le mode `auto`.
- **Socle.** [ADR-0007](../docs/adr/ADR-0007-per-session-rights.md) (intersection policy ∩
  capacités), [ADR-0013](../docs/adr/ADR-0013-consent-once-or-session.md) (grâce `expires_at=0`
  scopée, dont on élargit la portée).
