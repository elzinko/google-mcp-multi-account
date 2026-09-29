---
id: "20260929235257000"
title: Outil MCP curaté de pose/retrait de libellé Gmail (label-only, réversible)
type: feature
priority: P2
product: google-multi-account
version:
epic:
status: in-progress
ready: 2026-09-29
pr: "#156"
created: 2026-09-29
---

## En clair

Aujourd'hui, la surface Gmail curatée du MCP s'arrête aux brouillons : on peut lire
et créer un brouillon, mais **on ne peut pas poser un libellé** sur un message. Le
projet voisin `gmail-cleanerz` en a besoin : il veut coller des libellés `gc/*`
(`gc/to-delete`, `gc/kept`, …) sur des mails pour que l'humain les voie dans Gmail
ou Thunderbird, et **supprime lui-même**. Il n'accède à Gmail **que** par ce MCP.

Cette fiche ajoute un outil `gmail_labels_modify` : il **pose et retire** des
libellés sur des messages et/ou des threads. Il crée le libellé s'il manque. Il est
**réversible** (retirer annule poser). Il **n'envoie jamais** de mail et ne
**supprime jamais** rien.

Un piège que le besoin ne voit pas : dans Gmail, **la corbeille est un libellé**
(`TRASH`), le spam aussi (`SPAM`). Poser `TRASH` reviendrait à corbeiller. L'outil
n'agit donc **que sur des libellés utilisateur** (les libellés qu'un humain crée,
type `user`) et **refuse tout libellé système**. Il est alors incapable, par
construction, de corbeiller, spammer ou archiver.

## Contexte / Problème

`gmail-cleanerz` (assistant de nettoyage Gmail) doit poser des libellés `gc/*` sur
des messages. Son ADR-0003 lui impose de passer **uniquement** par ce MCP. Or la
surface Gmail exposée s'arrête aux brouillons : `gmail_list`, `gmail_get`,
`gmail_draft_create`, `gmail_attachment_get`. **Aucun outil de pose de libellé.**

La policy est prête côté clé : `gateway/default_policy.py` a `gmail.labels: true`.

**Mais** — découverte en repérage — poser un libellé passe par l'appel Gmail
`users.messages.modify`, que `gateway/categorize.py` classe aujourd'hui en
catégorie **`update`** (pas `labels`), car la ressource opérante est `messages`,
pas `labels`. Et `gmail.update` vaut `false` par défaut. En l'état, l'outil serait
donc **refusé** par la policy. Le test `scripts/test.sh` ligne 324 le prouve
(« gmail messages modify refusé si update:false »).

## Proposition

### 1. Reclasser `messages`/`threads modify` en catégorie `labels`

Dans `gateway/categorize.py::categorize`, ajouter à la branche Gmail :
`messages modify`, `messages batchModify`, `threads modify` → **`labels`**.

C'est exact : le corps de `messages.modify` est *uniquement*
`{addLabelIds, removeLabelIds}`. Ces appels ne font que gérer des libellés. Les
faire tomber dans `labels` (déjà `true` par défaut) autorise la pose/retrait
**sans ouvrir `gmail.update`**. La source de vérité est partagée
(autorisation + audit) : les deux s'accordent sur `labels`.

Le mapping `_OPERAND_PARAM` reste **inchangé** : `messages modify` en est exclu à
dessein (deux listes add/remove = opérande ambigu, fail-closed pour une capacité
scopée). Une capacité `gmail:labels` non scopée matche ; une scopée sur un libellé
précis échoue en fermé — comportement voulu.

### 2. Nouvel outil `gmail_labels_modify`

- **Entrées** : `alias` ; `add_labels` et/ou `remove_labels` (**noms** de
  libellés) ; `message_ids` et/ou `thread_ids` (**ids** de cibles) ;
  `create_missing` (défaut `true`) ; `session`.
- **Résolution nom → id** via `labels list` (lecture). Crée les libellés manquants
  de `add_labels` (libellés `user`) si `create_missing`.
- **Application** : messages via un seul `messages batchModify` (un geste couvre le
  lot) ; threads via `threads modify` (un par thread).
- **Sortie JSON** : ids touchés + libellés posés / retirés / créés + table
  nom → id.
- Pas de `grant_scope` exposé : l'opérande d'un `messages modify` est vide
  (exclu de `_OPERAND_PARAM`), donc la grâce « pour la session » ne s'applique
  jamais — l'exposer mentirait, comme pour `gmail_draft_create`.

### 3. Garde-fous (le cœur)

- **Libellés utilisateur uniquement.** Tout nom qui résout vers un libellé système
  (type `system` : `TRASH`, `SPAM`, `INBOX`, `UNREAD`, …) est **refusé**. Denylist
  de noms appliquée **avant tout appel** (défense en profondeur) + contrôle du
  `type` après `labels list`.
- **Jamais d'op destructive.** L'outil n'émet que `labels list/create`,
  `messages batchModify`, `threads modify`. Jamais `trash`, `delete`,
  `batchDelete`, ni un envoi.
- **Policy / verrous / élicitation respectés** : l'outil compose `_run` comme les
  autres écritures ; un refus (policy, verrou) remonte à l'humain, jamais contourné.

## Critères d'acceptation

- [ ] `gmail_labels_modify` pose un ou plusieurs libellés sur des messages et/ou
      threads, et les retire (réversibilité).
- [ ] Crée le libellé (utilisateur) s'il manque, quand `create_missing` (défaut).
- [ ] Refuse tout libellé système (`TRASH`, `SPAM`, `INBOX`, …) — pose comme retrait.
- [ ] N'émet **jamais** `trash` / `delete` / `batchDelete` ni d'envoi (test qui le
      prouve sur les commandes gws construites).
- [ ] `messages modify` / `messages batchModify` / `threads modify` sont autorisés
      sous `gmail.labels: true`, refusés sous `gmail.labels: false` (policy-check).
- [ ] L'outil apparaît dans `tools/list` (surface MCP) avec un schéma clair.

## Comment vérifier

- **policy-check hermétique** (`scripts/test.sh`) : sous `labels:true, update:false`,
  `gmail users messages modify` / `batchModify` / `threads modify` → autorisés
  (exit 0). Sous `labels:false` → refusés (exit 4).
- **Arguments gws construits** (`scripts/test.sh`, section « arguments gws
  construits », `api._run` monkeypatché) : un cycle pose → retrait construit bien
  `labels list`, `labels create` (si absent), `messages batchModify` avec
  `addLabelIds`/`removeLabelIds` ; **aucune** commande ne contient `trash`/`delete`/
  `batchDelete`/`send` ni un id de libellé système.
- **Refus** : cible vide, libellés vides, add ∩ remove non vide, libellé système,
  `create_missing=false` sur libellé absent → `GatewayError`.
- **Surface MCP** : `gmail_labels_modify` dans `tools/list` avec `add_labels`,
  `remove_labels`, `message_ids`, `thread_ids`.

## Notes — d'où vient la demande

Projet consommateur : `gmail-cleanerz` (`~/git/llm/gmail-cleanerz`). Invariant côté
lui : ne jamais supprimer — il pose des libellés `gc/*`, l'humain supprime. Cet
outil sert exactement ce contrat : label-only, réversible, aucune suppression.

Contrat exact (nom, schéma d'entrée, exemple pose+retrait, n° de PR) à reporter au
projet consommateur une fois la PR ouverte.
