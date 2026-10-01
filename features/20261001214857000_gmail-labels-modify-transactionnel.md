---
id: "20261001214857000"
title: gmail_labels_modify dans le modèle de session transactionnel — un seul consentement « pour la session » pour poser/retirer un libellé
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic:
status: in-progress
ready: 2026-10-01
pr:
created: 2026-10-01
---

## En clair

Poser un libellé `gc/to-delete` avec l'outil `gmail_labels_modify` est **inutilisable**
aujourd'hui : l'outil est refusé avant même d'agir, et il n'offre aucun moyen de dire
« d'accord pour toute la session ». Cette fiche le branche sur le **modèle transactionnel**
(ADR-0013) : **un seul geste Touch ID « pour la session »** suffit alors à poser ou retirer
des libellés `gc/*`, la lecture interne qui résout les noms de libellés comprise. La sécurité
ne bouge pas : le geste humain reste obligatoire, jamais de système, jamais d'envoi, jamais de
suppression.

## Si tu arrives frais

Quelques mots pour lire la suite sans contexte.

- **Transactionnel** : le mode où chaque accès Google est autorisé *au moment d'agir* par un
  geste signé (Touch ID), au lieu d'un « déverrouillage pour X minutes ». C'est le défaut
  visé par ce MCP (ADR-0011/0012/0013).
- **grant_scope** : le choix de **portée** que l'assistant relaie depuis le chat au moment
  d'autoriser un acte — `once` (ce seul acte, défaut) ou `session` (ce périmètre jusqu'à la
  fin de la session). L'humain le **lit dans le prompt Touch ID** et confirme.
- **Grâce « pour la session »** : une fois `session` consenti, un droit vit tant que la
  session vit ; un acte identique ne redemande plus de geste. Mécanique posée par ADR-0013.
- **Catégorie** : chaque appel Google est rangé (`read`, `labels`, `create`…). La policy et
  le consentement raisonnent par catégorie. `gmail_labels_modify` touche DEUX catégories :
  `read` (lister les libellés pour résoudre leurs noms) et `labels` (poser/retirer).

## Contexte / problème

L'outil `gmail_labels_modify` est arrivé en PR #156. Il **n'a jamais été branché** sur le
modèle transactionnel d'ADR-0013. Résultat : un client (le CLI `gmail-cleanerz`, ou l'agent
en conversation) ne peut pas poser un libellé. Trois faits, reproductibles :

1. **La LECTURE interne est refusée.** Pour résoudre un nom de libellé en identifiant,
   l'outil appelle `labels.list` — catégorie `gmail.read`. En transactionnel, l'autorisation
   d'un appel passe par la **capacité consentie portée par cet appel**, pas par les capacités
   persistées de la session. Sans consentement threadé, le broker refuse :
   `read « gmail » outside session capabilities (gmail:read)`.
2. **Le déverrouillage « par minutes » n'existe plus.** `session_unlock_in_conversation`
   refuse et renvoie vers « pour la session » (ADR-0013). L'ancienne échappatoire est fermée.
3. **L'outil n'expose pas `grant_scope`.** Contrairement aux mutations Drive
   (`drive_create`/`drive_update`/`drive_copy`/`drive_upload`), son schéma MCP n'a ni le
   paramètre `grant_scope` ni le threading associé. L'acte d'écriture ne peut donc **pas
   porter** le consentement « pour la session ».

Conséquence : poser un libellé exigerait aujourd'hui un octroi **hors-bande**
(`mag session grant-capability …`) par session éphémère — inutilisable en pratique.

**Difficulté propre à cet outil.** Un appel `gmail_labels_modify` = **plusieurs** appels
broker (lister, créer au besoin, modifier messages, modifier threads), de **deux catégories**
(`read` + `labels`). Les mutations Drive, elles, sont *un* appel = *un* geste. Si on gatait
chaque sous-appel séparément, un seul « poser un libellé » demanderait plusieurs Touch ID.

## Proposition

Décision d'architecture détaillée : [ADR-0014](../docs/adr/ADR-0014-gmail-labels-modify-transactionnel.md).

1. **Exposer `grant_scope`** sur `gmail_labels_modify`, comme sur les mutations Drive :
   paramètre dans l'inputSchema (`_GRANT_SCOPE_PROPERTY`), extrait au dispatch, ajouté à la
   signature `api.gmail_labels_modify`, et **threadé dans `_run`**.
2. **Un seul consentement pour tout l'acte.** `gmail_labels_modify` porte un objet d'acte
   (interne, jamais exposé au schéma) à travers ses sous-appels. Le gate transactionnel
   reconnaît cet acte : il demande **un seul geste** (une curation de libellés EST une
   mutation → un geste, en `auto` comme en `manuel`), puis autorise chaque sous-appel sous ce
   consentement — `read` pour la résolution, `labels` pour les écritures. Le broker
   re-vérifie chacun par son `consented_cap` (Zone 1, inchangé).
3. **La lecture de résolution est couverte par le même consentement.** En mode `manuel` +
   `session`, l'acte écrit **une** grâce *account-scoped* `(gmail, labels, "")` : le périmètre
   d'une curation de libellés EST la boîte, borné par la policy `gmail.labels` et le garde-fou
   « jamais de libellé système ». Cette grâce couvre AUSSI la lecture `labels.list` de l'acte
   (sous-grant lié à l'acte) — on ne persiste **jamais** de grâce `gmail:read` large. Un acte
   suivant dans la session ne redemande alors **aucun** geste.

**Garde-fous (inchangés).** Label-only : jamais d'envoi, jamais de suppression ; les libellés
système (TRASH, SPAM, INBOX…) restent refusés (api + `categorize`). Le partage et les
brouillons n'ont toujours ni `grant_scope` ni grâce. `grant_scope=session` **encode** le « pour
la session » explicite — il ne contourne rien : le geste humain reste requis.

## Critères d'acceptation

- [ ] Le schéma MCP de `gmail_labels_modify` expose `grant_scope` (enum `once`/`session`,
      défaut `once`), et le dispatch le relaie à `api.gmail_labels_modify`.
- [ ] En `manuel`, poser `gc/to-delete` sur un thread avec `grant_scope=session` demande
      **exactement un** geste signé — lecture de résolution comprise.
- [ ] Un **second** `gmail_labels_modify` dans la même session (autre libellé, autre cible)
      ne demande **aucun** geste.
- [ ] Après le premier acte `session`, la session porte une grâce `(gmail, labels, "")` —
      et **aucune** grâce `(gmail, read, …)`.
- [ ] Geste **refusé** → l'acte lève `locked` et **aucune** cible n'est modifiée (fail-closed).
- [ ] En `auto`, `grant_scope=session` est normalisé à `once` dans le reçu signé (honnête) ;
      aucune grâce n'est écrite.
- [ ] Une **sous-session déléguée** n'écrit jamais de grâce (geste par acte).
- [ ] Non-régression : les tests existants de `gmail_labels_modify` (PR #156, non
      transactionnels) restent verts ; le partage et les brouillons n'ont toujours pas de
      `grant_scope`.

## Comment vérifier

```bash
# depuis la racine du repo — la suite hermétique couvre le branchement complet
./scripts/test.sh 2>&1 | grep -A2 "ADR-0014"
```

Scénario clé rejoué en test (mode `manuel`, élicitation mock, broker simulé) :

1. `gmail_labels_modify(alias, add_labels=["gc/to-delete"], thread_ids=["t1"], grant_scope="session")`
   → **1** appel à l'élicitation (un seul Touch ID).
2. `gmail_labels_modify(alias, add_labels=["gc/keep"], thread_ids=["t2"], grant_scope="session")`
   → **0** appel à l'élicitation (grâce active).
3. La session porte `(gmail, labels, "")` ; elle ne porte **pas** `(gmail, read, …)`.

## Notes

- Fichiers : `gateway/mcp_server.py` (schéma + dispatch), `gateway/api.py`
  (`gmail_labels_modify`, `_run`, `_transactional_gate`, nouveau `_gmail_label_act_gate`),
  `scripts/test.sh` (section « ADR-0014 »).
- S'appuie sur la plomberie d'ADR-0013 sans la dupliquer : `session_grant_capability_session_lived`,
  `session_has_capability`, `_consented_cap`, `run_elicitation_gate`, `categorize`.
- Hors périmètre (note PO) : l'install `current` (v1.1.0, sans cet outil) et les serveurs MCP
  de dev câblés dans la config Claude du PO — le PO s'en occupe séparément.
