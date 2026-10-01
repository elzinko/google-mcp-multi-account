---
id: "20260930214101550"
title: "Spike — évaluer msgvault comme source de lecture Gmail multi-comptes"
type: chore
priority: P2
product: google-mcp-multi-account
version:
epic:
status: idea
ready:
pr:
created: 2026-09-30
---

## En clair

On se demande si on réécrit une roue qui existe. Des outils tiers (msgvault, Composio,
NanoClaw) couvrent déjà la **lecture** de Gmail. Ce spike vérifie si **msgvault** — archive
Gmail locale, multi-comptes, avec serveur MCP — suffit à notre besoin « consulter mes mails ».
Si oui, on arrête de coder la lecture et on concentre l'effort sur ce que personne ne fait :
l'**écriture sous consentement** et l'**identité par conversation**.

Note de cadrage complète : [docs/recentrage-outils-existants.md](../docs/recentrage-outils-existants.md).

## Contexte / Problème

Notre serveur MCP implémente la lecture Gmail (`gmail_list`, `gmail_get`…) en plus de la
gouvernance d'accès. Or msgvault fait déjà la lecture : plusieurs comptes Gmail dans une base
locale, recherche plein-texte, et un serveur MCP interrogeable depuis Claude. Maintenir notre
propre lecture pourrait être de l'effort perdu.

Deux inconnues bloquent la décision :
- **Fraîcheur** — msgvault est une archive *synchronisée*, donc potentiellement en retard sur
  la boîte vivante. Est-ce acceptable pour « consulter » ?
- **Multi-comptes réel** — plusieurs @gmail.com côte à côte, vraiment, et lisibles par l'agent ?

## Proposition

Spike **borné (~30 min)**, jetable, sans toucher au code :
1. Installer msgvault, archiver au moins deux comptes Gmail perso.
2. Brancher son serveur MCP dans Claude (Desktop ou Code).
3. Poser quelques questions réelles de « consultation » et juger la couverture.
4. Trancher : **go / no-go** sur « on délègue la lecture à msgvault ».

Hors périmètre : l'écriture, WhatsApp, l'intégration profonde. Ce spike ne livre pas de code —
il livre une **décision**.

## Critères d'acceptation

- [ ] msgvault installé et au moins **2 comptes Gmail** archivés localement.
- [ ] Son serveur MCP répond dans Claude à au moins **3 requêtes de consultation** réelles
      (recherche par expéditeur, par mot-clé, sur une période).
- [ ] Décision écrite **go / no-go** « déléguer la lecture à msgvault ? », datée.
- [ ] **Isolation par conversation préservée** : brancher msgvault ne doit pas contourner la
      frontière de comptes propre à chaque conversation. Nos outils exigent une session et
      isolent les droits par conversation ; msgvault est une archive **à plat** de tous les
      comptes. Si la délégation expose des comptes hors de la conversation autorisée → **no-go**.
- [ ] Limites notées : fraîcheur (retard archive vs live) et multi-comptes réel.
- [ ] Si **go** : fiche(s) de suite créée(s) — retirer seulement la **recherche / l'archive
      historique**, **garder la lecture live** (`gmail_list` / `gmail_get`) et l'écriture.
      Si **no-go** : raison consignée dans [docs/recentrage-outils-existants.md](../docs/recentrage-outils-existants.md).

## Comment vérifier

Relire la décision datée dans la fiche (ou la note de recentrage). Le spike est réussi si
quelqu'un peut lire le go/no-go **et sa justification** sans rejouer le test. Aucun test
automatique : c'est une exploration, pas une livraison.

## Notes

- Souveraineté : msgvault est local et open source — compatible avec notre contrainte 100 % local.
  Composio (courtier d'auth) est cloud par défaut, donc écarté ici.
- Ce spike ne remet pas en cause notre différenciateur (consentement par acte, identité par
  conversation) : il ne parle que de la **lecture**.
