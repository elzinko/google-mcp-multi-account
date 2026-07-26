---
id: 0030
title: Poste de commande versionné — gwsa update/release et le lien PATH sur la copie installée
type: feature
priority: P1
version:
epic:
status: in-progress
ready: 2026-07-26
pr:
created: 2026-07-26
---

## Contexte / Problème

**Deux défauts, un même sujet : la porte d'entrée.**

**1. Les verbes sont éparpillés.** Publier et mettre à jour vivent dans
`scripts/release.sh` et `scripts/update.sh` (fiche 0029), alors que tout le
reste du poste de commande humain est dans `gwsa` — `gwsa list`, `gwsa lock`,
`gwsa admin`, `gwsa broker`. Rien ne répond à « quelles commandes existent ? »
depuis un seul endroit. C'est le besoin qu'un `npm run` couvrirait dans un
projet JS, sauf qu'ici le CLI existe déjà : il suffit de l'utiliser.

**2. Le poste de commande n'est pas versionné.** Le `gwsa` du PATH est un lien
vers le **clone**, posé par l'étape 1 du quickstart :

```
/opt/homebrew/bin/gwsa -> /Users/…/git/google-mcp-multi-account/bin/gwsa
```

C'est exactement la dérive que la fiche 0023 a corrigée pour le serveur MCP,
restée en place pour l'autre moitié du système :

| | Code exécuté | Versionné ? |
|---|---|---|
| Serveur MCP | `~/.local/share/google-mcp/current/` | oui |
| `gwsa` du PATH | le clone | non |

La copie déployée embarque pourtant son propre `gwsa` — personne ne le pointe.
Conséquence : `gwsa unlock perso` exécute le code du clone, y compris son
`policy-check.py`, sur les comptes du couloir stable. Le broker, lui, utilise
le `gwsa` déployé (`deploy-local.sh` l'appelle par `current/bin/gwsa`). Deux
copies en jeu selon la porte d'entrée — inoffensif tant que le clone est sur
`main`, faux dès qu'on développe une branche.

## Proposition

1. **`gwsa update`** et **`gwsa release`** : fines enveloppes qui délèguent aux
   scripts (`exec`), plus les deux mots dans les réservés et dans `gwsa help`.
2. **`gwsa release` depuis une copie installée** : elle n'a pas de `.git`, mais
   `deploy-local.sh` y note le clone source dans `.source` — même relais que
   `update.sh`. Sans `.source` : refus qui dit quoi faire.
3. **`update.sh` rebranche le lien PATH sur `current`**, comme il rebranche
   déjà l'entrée Claude Desktop. Prudent par construction : il ne touche qu'un
   **lien symbolique** dont la cible est un `bin/gwsa` du clone source ou d'une
   version déployée. Un fichier réel ou une cible inconnue est laissé tel quel,
   avec un avertissement.
4. Quickstart : le lien du clone reste l'amorçage (avant tout déploiement),
   `update.sh` prend le relais ensuite. À dire dans le README.

## Critères d'acceptation

- [x] `gwsa update` et `gwsa release` délèguent aux scripts, arguments compris.
- [x] `update` et `release` sont des mots réservés (`gwsa add update` refusé).
- [x] `gwsa help` liste les deux verbes.
- [x] `gwsa release` depuis une copie installée retrouve le clone via `.source` ;
      sans `.source`, refus explicite.
- [x] `update.sh` fait pointer le `gwsa` du PATH sur `current/bin/gwsa`.
- [x] Il ne touche PAS : un fichier réel, ni un lien dont la cible est
      étrangère au projet — avertissement, et rien de cassé.
- [x] Relancé, il ne réécrit pas un lien déjà correct (idempotent).
- [x] `./scripts/test.sh` vert, sans jamais toucher au vrai `/opt/homebrew/bin`.

## Notes

- Décision de conception : **pas de npm/pnpm**. Ce qu'il apporterait ici est
  déjà couvert (`npm version` = `release.sh`, publication sans objet sur un
  dépôt privé installé localement) ; ce qu'il coûterait ne l'est pas — une
  seconde source de vérité pour la version (`package.json` contre le tag git),
  et une dépendance de plus dans un projet dont l'argument est zéro dépendance
  tierce, avec des interpréteurs en chemin absolu (`/usr/bin/python3`, protégé
  par SIP) précisément pour qu'un binaire du PATH ne puisse pas désactiver le
  contrôleur de policy.
- `resolve_repo_dir` de `gwsa` suit déjà le lien : pointer le PATH sur `current`
  suffit, la résolution se fait à chaque appel.
