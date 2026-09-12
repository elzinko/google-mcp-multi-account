---
id: 0042
title: Version visible dans le connecteur MCP + mise à jour guidée
type: feature
priority: P2
version: V2
epic:
status: shipped
ready:
pr: "#128"
created: 2026-07-28
updated: 2026-07-28
---

> **Superseded — livrée par #128 / #78 (2026-09-04).** La visibilité de version est là (badge admin Cockpit #128 + `serverInfo` du handshake), et le parcours de mise à jour passe par `mag update --check` + l'install curl sans clone (#78). La cohabitation dogfood (2 connecteurs côte à côte) est repliée dans [[0046]]. Marquée livrée à ce titre — pas de PR propre.


## Contexte / Problème

Dans Claude Desktop → **Connecteurs** → `google-multi-account`, on voit le
**nom** de l'entrée MCP et les autorisations d'outils, **pas la version**
déployée (`v0.2.1`, `feat/…@sha`, etc.).

C'est normal que le label « MCP » n'apparaisse pas (on est déjà dans Connecteurs).
En revanche, sans version visible :

- on ne sait pas si Claude parle au **stable** (`current`) ou à un vieux dogfood ;
- après un merge sur `main` + `mag update` / nouveau tag, rien n'indique dans
  l'UI connecteur qu'une **nouvelle version est disponible** ni qu'elle a été
  prise en compte.

La fiche [[0026]] couvre l'annonce de version **via les tools** (`setup_status`)
et la détection de dérive config ↔ `current`. Celle-ci cible la **surface
humaine** Claude Desktop (et éventuellement Cursor) + le **parcours de mise à
jour** post-merge + la **cohabitation** stable / dogfood.

> **Quand l'attaquer** (parties A/B stables) : après merge de la PR V2 (#49) sur
> `main`. La cohabitation dogfood ([[0046]]) est déjà utilisable sur la branche.

## Décisions produit (2026-07-28)

### 1. Pas de version dans le **titre** du connecteur stable

`google-multi-account-1.0.0` afficherait la version dans Connecteurs, mais à
chaque bump Claude traite une **nouvelle** entrée → reset des autorisations
outils (« Personnalisé »). **Refusé** pour le chemin stable.

Nom stable **fixe** : `google-multi-account`.

### 2. Deux rails distincts (ne pas écraser le MCP du quotidien)

| Rail | Entrée MCP | Ports | Déploiement | Quand |
|------|------------|-------|-------------|-------|
| **Stable** (travail quotidien) | `google-multi-account` | broker **4878**, admin **4877** | `~/.local/share/google-mcp/current` → tag `vX.Y.Z` | Prod locale |
| **Dogfood** (branche / PR / worktree) | nom **suffixé** ex. `google-multi-account-<sandbox-id>` | broker **≥ 4882**, admin **≥ 4879** | `mag sandbox deploy --dev` ([[0046]]) | Essayer une feature **sans** toucher le stable |

**Oui**, on peut démarrer une version de dev sur un worktree / une branche
**sans abîmer** le MCP déjà en place — c'est exactement le rôle des sandboxes.
Ne **pas** faire `mag update` / basculer `current` pour tester une PR.

### 3. Comment « choisir » quelle version le LLM utilise

Aujourd'hui (Claude Desktop / Cursor) : **plusieurs entrées MCP** peuvent
coexister. Le LLM utilise celle(s) que le client expose / que tu actives dans
la conversation (souvent toutes les connecteurs allumés, ou un seul selon le
produit).

Mécanisme simple recommandé pour le dogfood humain :

1. Garder `google-multi-account` → stable, toujours là.
2. Ajouter une 2ᵉ entrée suffixée pointant vers la sandbox (binaire +
   `GWSA_BROKER_PORT` du résumé `sandbox deploy`).
3. Pour tester la nouvelle : parler au connecteur dogfood (ou désactiver
   temporairement le stable dans Connecteurs si le client mélange les tools).
4. Fin de dogfood : retirer l'entrée suffixée (admin **Clients MCP → Retirer**)
   + `mag sandbox remove <id>` — le stable continue.

**Pas** d'écrasement de l'ancienne pour le dogfood. Écrasement / bascule
`current` = uniquement le rail **stable** après release taguée (`mag update`).

### 4. Comment marche `mag update` aujourd'hui (stable)

**Pas** un téléchargement d'asset GitHub (`.tar.gz` de release). Flux actuel :

1. Clone git local (chemin noté dans `.source` de la copie installée)
2. `git fetch --tags` → dernier tag `v*` (ou `--to vX.Y.Z`)
3. `deploy-local.sh --tag …` → `git archive` → `~/.local/share/google-mcp/vX.Y.Z/`
4. Symlink `current` → cette version ; recycle le broker **4878**
5. Rebranche Claude Desktop **seulement** si l'entrée ne pointe pas déjà vers
   `…/current/bin/google-mcp` (nom d'entrée inchangé)

Évolution possible plus tard (hors scope immédiat) : install depuis une release
GitHub **sans** clone — pour « n'importe qui ». Le modèle mental reste le même :
bascule `current`, nom MCP fixe.

## Ce qu'on sait déjà (limites produit Claude)

- Le nom affiché dans Connecteurs = la **clé** `mcpServers.<name>` du JSON.
- Le handshake MCP `initialize` / `serverInfo` peut porter une version : à
  vérifier si Claude l'affiche (souvent non dans Connecteurs).

## Proposition (à groomer — post-merge)

### A — Visibilité version (humain + agent)

| Surface | Idée |
|---|---|
| Tool MCP | Étendre [[0026]] : `setup_status` affiche `version`, binaire, port |
| Admin | Badge version (déjà en V2 sandbox) aussi sur admin stable 4877 |
| Connecteurs | Ne pas compter dessus pour la version ; doc claire |

### B — Mise à jour stable « pour n'importe qui »

1. `mag update --check` / admin / `setup_status.next_actions` : « v0.3.0 dispo »
2. `mag update` : bascule `current`, **sans** renommer `google-multi-account`
3. Redémarrer Claude Desktop ; vérifier version via tool / admin

### C — Activation dogfood (déjà en place via [[0046]], à polir)

- Documenter le duo stable + entrée suffixée
- Boutons admin déjà : Retirer entrée MCP jetable ; Supprimer sandbox
- Éventuel : « Activer / désactiver » plus explicite dans l'admin (plus tard)

## Critères d'acceptation (esquisse)

- [x] Décision écrite : nom stable fixe ; pas de version dans le titre connecteur
- [x] Décision écrite : dogfood = sandbox parallèle + suffixe ; pas d'écrasement `current`
- [x] Documenté : update actuel = tags git + `git archive`, pas tar.gz GitHub
- [ ] Signal fiable « quelle version répond » (tool et/ou admin stable)
- [ ] Parcours « nouvelle version dispo → `mag update` → vérif » testable
- [ ] Doc dogfood : 2 connecteurs côte à côte + comment choisir / nettoyer
- [x] Lien / non-doublon clarifié avec [[0026]] — **frontière** posée des deux
      côtés : 0026 = surface *agent* (annonce version via tools + dérive
      config↔`current`) ; 0042 = surface *humaine* (Connecteurs/admin, parcours
      de mise à jour, cohabitation stable/dogfood).

## Pour toi, en pratique (aujourd'hui)

```bash
# Quotidien — ne pas toucher
# Connecteur : google-multi-account → …/current/bin/google-mcp @ 4878

# Essayer cette PR / worktree — SANS casser le quotidien
cd /chemin/worktree
./bin/mag sandbox deploy --dev
# → id du type feat-v2-local-deploy-<sha>
# → brancher une 2ᵉ entrée MCP (nom suffixé) sur le broker imprimé
# → stable reste sur 4878

# Fin de test — unwire un client seulement :
./bin/mag sandbox wire --remove desktop
# Ou nucléaire (tous clients + supprimer le répertoire) :
./bin/mag sandbox remove <id>
```

Quand la V2 est **mergée** et taguée : `mag update` sur le rail stable (écrase
seulement `current`, pas le dogfood).

## Notes

- Découvert en dogfood V2 (2026-07-28) : Connecteurs = nom + permissions, zéro version.
- Dépendances : [[0026]], [[0029]], [[0030]], [[0028]], [[0046]].
