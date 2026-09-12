---
id: "20260911135931576"
title: Déverrouillage transactionnel — remplacer la fenêtre de minutes par un consentement par demande
type: feature
priority: P1
product: google-multi-account
version:
epic: 0082
status: ready
ready: 2026-09-12
pr:
created: 2026-09-11
---

## En clair

Aujourd'hui, déverrouiller un compte l'ouvre pour **N minutes** : un Touch ID, puis accès libre
pendant la fenêtre. Thomas trouve ce modèle bizarre — la durée est arbitraire, et pendant la
fenêtre la session peut tout faire sans re-valider.

Ce qu'il veut à la place : un modèle **transactionnel**. Tu valides (Touch ID), la demande en
cours s'exécute, puis le droit est **retiré**. À la demande suivante, nouveau Touch ID. Et pour
les actes **sensibles** (envoyer un mail, écrire dans Drive), un Touch ID **à chaque fois**, sans
fenêtre.

C'est plus proche d'un paiement par carte (on valide au moment d'agir) que d'un badge qui ouvre
la porte pour une heure.

## Contexte / problème

Le déverrouillage par session (`session_unlock`, [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md),
fiche [`0076`](done/0076-droits-par-session-phase-a.md) livrée) prend un paramètre **`minutes`**
(défaut 60, borné 1–1440). Une fois déverrouillé, le compte reste accessible pour la session
jusqu'à expiration, **sans re-validation**. C'est le cas aussi du mode « élicitation dans la
conversation » (fiche [`20260910194019668`](20260910194019668_elicitation-in-conversation-opt-in.md)),
qui reprend `minutes`.

Deux reproches :
- **La durée est arbitraire.** Pourquoi 60 min ? L'usage conversationnel est « je demande une
  chose, elle se fait, c'est fini » — pas « garde la porte ouverte une heure ».
- **La fenêtre est une fenêtre d'abus.** Pendant N minutes, un LLM détourné (injection) peut
  enchaîner des opérations dans les droits de la session sans nouveau geste humain.

## Proposition (à groomer AVEC l'architecte)

Repenser **la durée du droit accordé par un Touch ID**. Le popup reste le point de consentement ;
ce qui change, c'est ce qu'il ouvre.

1. **Déverrouillage transactionnel** : un Touch ID vaut pour **la demande en cours** (quelques
   requêtes), puis le droit est **retiré**. Plus de fenêtre de minutes comme mécanisme principal.
2. **Les minutes deviennent un simple filet** (fenêtre très courte, ex. 1–2 min) au cas où le
   retrait explicite n'a pas lieu — pas le mécanisme central.
3. **Touch ID par acte sensible** : envoi de mail, écriture/partage Drive → un Touch ID **à
   chaque fois**, sans fenêtre. Lecture → tolère une courte fenêtre transactionnelle.

Les **droits** (quoi est permis) restent définis par la **policy / l'admin** ; le Touch ID
confirme « oui, agis **maintenant** », dans ces droits.

## Questions ouvertes pour l'architecte (le cœur du grooming)

- **Comment borner « la demande en cours » ?** Le serveur MCP ne sait pas quand le LLM a fini de
  répondre. Pistes : fenêtre très courte (ex. 60–120 s) ; **compteur d'opérations** (N requêtes
  puis retrait) ; **retrait explicite** via un tool `session_close` que le LLM appelle en fin de
  réponse (verrou souple) ; combinaison.
- **Lecture vs écriture** : un seul modèle, ou deux régimes (lecture = fenêtre courte, écriture =
  Touch ID par acte) ?
- **Compatibilité** : garder `minutes` en repli/override, ou le retirer ? Impact sur
  `session_unlock`, le mode in-conversation, l'admin, les tests.
- **Friction vs sécurité** : où mettre le curseur par défaut pour rester utilisable au quotidien
  sans banaliser le Touch ID (fatigue de validation) ?
- **Anti-injection** : en quoi le transactionnel réduit-il réellement la surface par rapport à la
  fenêtre ? (à énoncer noir sur blanc dans l'ADR).

> **Décision d'architecture prise (2026-09-11)** — les questions ci-dessus sont tranchées dans
> [ADR-0011](../docs/adr/ADR-0011-consentement-transactionnel-par-session.md) : bail de lecture
> court **auto-refermé** (TTL ~90 s ET budget ~20 ops) + **acte sensible signé à usage unique**
> (écriture/envoi/partage : Touch ID par acte), `minutes` **déprécié/écrêté**, retrait **jamais**
> dépendant du LLM.

## Modes de consentement (vision Thomas, 2026-09-11)

Plutôt qu'un réglage unique, exposer des **modes** que l'utilisateur choisit — c'est lui qui règle
le curseur friction / sécurité :

- **Mode manuel** — Touch ID à **chaque opération**, lecture comme écriture. Le plus strict.
- **Mode auto** — lecture en **bail court** (Touch ID par compte, ADR-0011), mais **acte sensible
  toujours signé** (envoi mail, écriture/partage Drive : Touch ID par acte, **même en auto** —
  c'est irréversible/sortant). Le plus fluide, sans banaliser l'irréversible.

Ces modes **se posent par-dessus** ADR-0011 : ils règlent le curseur, l'ADR fixe la mécanique
lecture/écriture. **Pas de « durée » comme réglage** : le mode auto n'ouvre pas « N minutes » mais
un bail court auto-refermé. « Fermer avec la session » n'est **pas détectable** par le MCP (il ne
sait pas quand la conversation finit — ADR-0007) ; le bail court **est** le proxy réaliste.

## Contrainte de déploiement : version dev séparée + rollback (exigence Thomas)

Le projet est **utilisé pour d'autres usages** : cette évolution ne doit **jamais casser
l'existant qui marche**.

- **Développer sur une version dev** = un serveur MCP **séparé** (ex. `gma-feat` → binaire de la
  branche), qui **n'écrase pas** `google-multi-account` (prod, `current`). Déjà en place et validé
  cette session (Code + Desktop).
- **Déployer avec rollback** : mécanisme `current` → tag versionné (v1.1.0 → v1.x) ; rollback =
  re-pointer `current` sur le tag précédent. Natif au projet.
- **Opt-in, off par défaut** : comme le mode in-conversation, ce changement de modèle reste
  activable/désactivable — rien ne change au comportement stable tant qu'il n'est pas choisi.

## Relation aux fiches voisines

- [`20260910194019668`](20260910194019668_elicitation-in-conversation-opt-in.md) — le mode
  in-conversation ; c'est là que le modèle de durée se ressent le plus (popups déclenchés par le
  LLM). Cette fiche **complète** le modèle de durée sous-jacent.
- [`0108`](0108-session-demande-sous-ensemble-droits-compte.md) — le *quoi* on accorde
  (sous-ensemble de droits). Ici c'est le *combien de temps / à quelle granularité temporelle*.
- Épic parent [`0082`](0082-droits-par-session.md) ; socle [ADR-0007](../docs/adr/ADR-0007-droits-par-session.md).

## Incrément 1 (ce sprint) — le cœur ADR-0011, sur `main`

Objectif : poser la **mécanique** d'ADR-0011 dans la couche session/gate, sans la couche « modes ».

**Dans le périmètre :**
- Registre de session : remplacer la fenêtre `minutes` par un **bail de lecture** borné — TTL ~90 s
  **ET** budget ~20 ops, première limite atteinte → referme —, calculé côté broker à chaque appel.
- Point de contrôle `_run` : router selon **lecture** (bail actif ? sinon Touch ID « lire maintenant »
  ouvre un bail) vs **mutation** (Touch ID signé lié à l'acte, usage unique via `consume_nonce` —
  aucune fenêtre).
- **Mapping tool → lecture|mutation** explicite et **fail-closed** (tool non classé = mutation).
- `session_unlock` : `minutes` **déprécié + écrêté** au plafond du bail (compat, pas de casse d'API).
- Retrait **jamais** dépendant du LLM (TTL/budget seuls) ; `session_close` **hors périmètre** (optim. ultérieure).

**Hors périmètre (incréments suivants) :** la couche **modes auto/manuel** (par-dessus) ; l'adaptation du
mode **in-conversation** (`session_unlock_in_conversation`, sur #142 — suit une fois #142 mergé, même
socle) ; la **calibration** des défauts et l'**allowlist** de comptes sensibles.

**Base :** `main` (le socle sessions/`_run`/minutes y vit). Opt-in / rollback natifs (version dev
`gma-feat` séparée, `current` → tag).

## Critères d'acceptation (incrément 1)

- [ ] Le registre de session porte un **bail de lecture** (TTL **et** budget) au lieu d'une fenêtre
  `minutes` ; il se referme seul (TTL écoulé **ou** budget épuisé) — testé (hermétique).
- [ ] `_run` : une **lecture** sous bail actif passe (budget −1) ; bail fermé → refus sauf nouveau
  consentement — testé.
- [ ] Une **mutation** (écriture / envoi / partage / suppression) exige un **acte signé dédié** (usage
  unique) ; un 2ᵉ acte identique redemande un geste — testé.
- [ ] Tool **non classé** → traité en **mutation** (fail-closed) — testé.
- [ ] `session_unlock` accepte encore `minutes` mais l'**écrête** au plafond du bail — testé (non-régression API).
- [ ] `./scripts/test.sh` au vert (aucune régression).

## Comment vérifier

Depuis une conversation : demander une lecture → un Touch ID → la lecture se fait → vérifier que
le droit est **retiré** juste après (une 2ᵉ lecture redemande un Touch ID, ou selon le mécanisme
retenu). Puis demander un **envoi de mail** → un Touch ID **dédié** à cet acte, même si une
lecture vient d'être validée.

## Notes

- Vient de la session du 2026-09-11 (Thomas, sur le mode in-conversation) : « à partir du moment
  où l'on accepte, on peut y accéder, faire quelques requêtes, puis on retire le droit… puis à
  chaque demande liée au MCP, on repasse le Touch ID ». À groomer avec l'architecte, puis ADR.
- Ne pas confondre avec [`0108`](0108-session-demande-sous-ensemble-droits-compte.md) (périmètre
  des droits) : ici c'est la **temporalité** du consentement.
