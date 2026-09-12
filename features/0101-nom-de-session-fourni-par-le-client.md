---
id: 0101
title: Nom lisible de session, fourni par le client MCP
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0082
status: idea
ready:
pr:
created: 2026-08-30
---

## En clair

On veut reconnaître une session par un **nom**, pas par un id hexadécimal. Décision prise :
le nom vient du **client MCP** (la conversation), pas d'une étiquette posée à la main dans
l'admin. La session porte alors un nom lisible, affiché et triable dans le panneau
Sessions.

> ⚠️ **Dépendance à lever avant de groomer `ready`.** Les clients actuels (Claude Desktop,
> Cursor) envoient le **nom de l'app** (`clientInfo.name`), pas un **titre de conversation**.
> Il n'existe pas, à ce jour, de canal standard MCP pour un titre par conversation. Cette
> fiche suppose donc un **moyen pour le client de transmettre ce nom** — à concevoir. Sans
> lui, il n'y a rien à afficher (repli : app cliente + id court, comme aujourd'hui).

## Contexte / problème

Le fichier de session (`gateway/sessions.py`, `SessionState`) stocke : `session_id`,
`parent_id`, `client` (l'app), dates, `unlocks`, `drive_zones`. **Pas de nom.** L'admin
affiche donc un id court + le nom de l'app. Impossible de « fonctionner par nom ».

## Proposition (à groomer)

1. **Champ `name`** sur `SessionState` (persisté dans `.sessions/<id>.json`, exposé par
   `/api/sessions`).
2. **Voie de transmission depuis le client** — le point à trancher au grooming. Pistes :
   - le nom accompagne la **création du jeton** (`mag session open --name …` / commande
     broker `session_create`) — marche si c'est le client qui ouvre la session ;
   - une **convention** : le client pose le nom via un appel dédié en début de session ;
   - un **env** transmis par le client au serveur MCP (comme `GWSA_SESSION_ID`).
   Constater ce qu'un client réel peut réellement fournir (dépendance externe : à vérifier
   sur Claude Desktop / Cursor **avant** `ready`).
3. **Affichage & tri** dans le panneau Sessions : nom en tête de carte/rangée, tri par nom
   (complète la fiche 0099 qui trie déjà par activité/client/accès).
4. **Réactivité** : le nom arrivant dans le fichier de session, l'auto-refresh de l'admin
   (poll 3 s + diff) l'affiche sans rechargement — mécanisme déjà en place (0094/0099).

## Critères d'acceptation (esquisse — à compléter au grooming)

- [ ] Une session peut porter un nom lisible fourni par le client.
- [ ] Le nom est affiché et triable dans le panneau Sessions.
- [ ] Repli propre si aucun nom fourni (app cliente + id court).
- [ ] Dépendance client **constatée** (ce qu'un client réel envoie), datée dans la fiche.

## Comment vérifier

Avec un client capable de fournir un nom : ouvrir une session, vérifier que le nom
s'affiche dans l'admin, le modifier côté client et voir la mise à jour sans recharger.
Sans nom fourni : vérifier le repli.
