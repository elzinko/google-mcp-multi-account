---
id: "20261013215354286"
title: "Onboarding piloté par le CLI mag — parité CLI ⊇ admin"
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-10-13
---

## En clair

Un nouvel arrivant doit pouvoir **tout faire depuis le terminal** : monter l'app OAuth,
connecter ses comptes, voir où il en est, réparer l'accès. C'est un outil orienté
développeur. Le CLI `mag` est donc la **surface de référence** et doit porter tout
l'onboarding ; l'admin web n'est qu'une **façade** au-dessus des mêmes commandes, jamais
un sur-ensemble. Aujourd'hui ce n'est pas tout à fait vrai : le provisioning vit dans un
script à part (`provision-gcp.sh`), pas sous `mag`. Cette fiche cadre le problème et
propose le découpage.

## Contexte / Problème

Pour démarrer, un utilisateur doit enchaîner deux phases bien distinctes — et la question
« je provisionne avec un email ? » vient de leur confusion :

```
Phase A — Mettre en place l'accès   (UNE fois, le propriétaire du projet)
  gcloud login → projet GCP → APIs → écran consentement
  → client OAuth « Desktop » (console) → publier (console)
  ⚠ pas d'email ici : c'est le compte proprio qui monte l'app OAuth

Phase B — Connecter un compte        (par email, répétable)
  mag add <alias> <email>  → OAuth navigateur
  → (déjà fait) propose d'accorder le rôle IAM dans la foulée
```

Deux entorses au principe « le CLI porte tout » sont déjà en place :

1. L'entrée de la phase A est un **script séparé**, `./scripts/provision-gcp.sh`, pas une
   commande `mag`. Un nouvel arrivant ne devine pas qu'il faut lancer un script hors `mag`.
2. L'admin web appelle `provision-gcp.sh` en direct (`/api/setup`, `/api/sync-iam`). Le
   script comme moteur, c'est bon ; mais le **nom d'usage** côté humain doit rester `mag`.

Contrainte dure à assumer : deux étapes de la phase A sont **irréductiblement manuelles**
dans la console Google (créer le client OAuth « Desktop », publier l'app) — Google a fermé
les APIs. Pareil pour `gcloud auth login` et Touch ID, qui sont des gestes OS. Donc
l'onboarding est un **guide qui orchestre** (bouton quand c'est local et sûr, lien console
sinon, commande à copier), pas un bouton magique.

« Assisté par LLM » marche dans un sens précis : l'assistant lit l'état via le tool
[setup_status](done/0009-tool-mcp-setup-status.md) (lecture seule) et **propose** la
prochaine commande. Il ne lance jamais gcloud, la console ou Touch ID (doctrine du projet).

Prior art, tout livré mais phase-spécifique : chaîne d'onboarding des comptes
[0005](done/0005-onboarding-comptes-iam-elicitation.md), provisioning idempotent
[0007](done/0007-provisioning-idempotent-declaratif.md), tool
[setup_status](done/0009-tool-mcp-setup-status.md), parité CLI/MCP des helpers
[20260910170000000](done/20260910170000000_traduire-scripts-helper-mag-parite-mcp.md).
Aucune ne porte le **principe de parité** comme idée organisatrice. Cette fiche le pose,
sous l'épic [0017](0017-generaliser-autres-utilisateurs.md).

Déclencheur : session 2026-10-13. Après recréation du projet OAuth, l'onboarding a buté sur
le rôle IAM manquant (403 silencieux). Deux correctifs livrés ce jour alimentent cette
fiche : `sync-iam` gère désormais les profils verrouillés, et `mag add` propose d'accorder
le rôle IAM dans la foulée (« un seul geste »). Reste à hisser tout l'onboarding sous `mag`.

## Proposition

Principe directeur : **parité CLI ⊇ admin**. Toute capacité de l'admin existe d'abord en
CLI `mag`. Une seule source d'état (`setup_status`), deux façades (terminal + admin).

Increments proposés (à groomer/splitter en fiches filles) :

1. **`mag provision`** — replier `provision-gcp.sh` sous `mag` : le pas-à-pas guidé de la
   phase A vit dans le terminal (checklist ordonnée, état par étape, action adaptée). Le
   script reste le moteur interne.
2. **Diagnostic + réparation sous `mag`** — exposer `status` et l'équivalent `sync-iam`
   sous le nom `mag` (le script les fait déjà).
3. **Admin = façade** — garantir que l'admin n'appelle que des commandes `mag` et ne
   présente aucune capacité absente du CLI. Promouvoir le panneau 🩺 en assistant premier
   run quand le setup est incomplet (il lit déjà `setup_status`).

La version du code est déjà affichée dans l'admin ; la garder visible dans l'assistant.

## Critères d'acceptation

- [ ] Le modèle « phase A / phase B » est documenté là où l'utilisateur démarre (README /
      guide d'onboarding), sans confondre « monter l'app » et « connecter un compte ».
- [ ] `mag provision` existe et lance la phase A (au minimum en déléguant au script), avec
      un pas-à-pas lisible depuis le terminal seul.
- [ ] Le diagnostic et la réparation IAM sont atteignables sous le nom `mag`.
- [ ] L'admin n'expose aucune action d'onboarding que le CLI ne sait pas faire (parité
      vérifiée action par action).
- [ ] Un nouvel arrivant sans navigateur ouvert (terminal seul) peut aller de zéro à « un
      compte connecté avec accès IAM » en suivant uniquement des commandes `mag`.

## Comment vérifier

- Dérouler l'onboarding sur un poste vierge (ou un `GWSA_ROOT` temporaire) **sans ouvrir
  l'admin** : `mag provision` puis `mag add <alias> <email>`, jusqu'à un `status` tout vert.
- Comparer, action par action, ce que propose l'admin (`/api/setup`, `/api/sync-iam`, à
  venir) avec une commande `mag` équivalente : chaque bouton admin a son pendant CLI.
- `mag provision` relançable sans effet de bord (idempotent), comme `provision-gcp.sh`
  aujourd'hui.

## Notes

- Cette fiche est un **cadrage** (idea). La groomer déclenchera le split en fiches filles
  (increments 1–3). Enfant de l'épic [0017](0017-generaliser-autres-utilisateurs.md).
- Priorité P2 par défaut (alignée sur l'épic parent) — à confirmer par le PO.
- Garde-fou doctrine à conserver dans tout increment : l'octroi IAM et les gestes console
  restent **humains**. Le LLM voit et propose, il n'exécute jamais gcloud / console / Touch ID.
