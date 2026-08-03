---
id: 0059
title: gwsa ne résout plus un dossier par son nom depuis le vault (grant / policy zone)
type: bug
priority: P1
version:
epic:
status: shipped
ready:
pr: "#77"
created: 2026-07-29
---

## Contexte / Problème

Depuis la migration des credentials vers le vault (fiche 0001, commit
`4304a1e`, 28/07), **`gwsa grant <alias> <NOM_DE_DOSSIER>` échoue toujours** :

```
$ GWSA_CLIENT=claude-code gwsa grant perso ZZ-TESTS 1
gwsa : dossier « ZZ-TESTS » introuvable ou ambigu — donne son ID (fin de l'URL du dossier dans Drive)
```

…alors que le dossier existe, est unique, et est parfaitement trouvé par le
MCP (`drive_list` avec la requête exacte de `resolve_folder` renvoie 1 fichier).

**Cause.** `resolve_folder()` (`bin/gwsa:84-101`) appelle `gws` avec
`GOOGLE_WORKSPACE_CLI_CONFIG_DIR="$(profile_dir "$alias")"`. Or les tokens ne
sont plus là :

| Répertoire | Contenu |
|---|---|
| `~/.config/gws-accounts/<alias>/` | `policy.json`, `session-grants.json`, `token_cache.json` — **pas** de `credentials.enc` |
| `~/.config/gws-accounts/.vault/<alias>/` | **`credentials.enc`** |

Le broker lit `gws_config_dir()` (`gateway/broker_server.py:88` →
`gateway/vault.py:112`) et fonctionne. `bin/gwsa` est resté sur `profile_dir`.
`gws` n'est donc pas authentifié, sort en erreur, et l'erreur est **avalée par
`2>/dev/null`** : la sortie vide est interprétée comme « introuvable ou
ambigu ». Le message accuse le dossier de l'utilisateur alors que le problème
est l'authentification.

`resolve_folder` n'a pas bougé depuis le commit initial (`e5462e2`) — c'est le
sol qui s'est dérobé sous lui.

**Portée.** Deux commandes utilisateur passent par `resolve_folder` :

- `cmd_grant` (`bin/gwsa:432`) — accorder une zone Drive par nom
- `cmd_policy … zone` (`bin/gwsa:347`) — déclarer une zone par nom

Et le même pattern (`CONFIG_DIR=profile_dir` + `gws`) subsiste ailleurs dans
`bin/gwsa` : ligne 169 (`profile_email`, déjà rustiné en cache-only par
`a798714` / `f6ab2ff` — même cause), ligne 225 (probe IAM après `add`),
ligne 1506 (`auth logout`), ligne 1589. À auditer d'un bloc.

Découvert en déroulant le test manuel
`tests/manuels/gwsa-grant-resolve-nom/` (Phase 2), sur `perso` et `mw`.

**L'invariant existait déjà.** La fiche [0015](done/0015-email-metadonnee-persistee-hors-verrou.md)
(*« Email de profil = métadonnée persistée — **zéro exécution gws hors
broker** »*, shipped) a posé exactement cette règle, et `scripts/test.sh:1049`
la garde… mais seulement pour `gateway/`. `bin/gwsa` n'a jamais été mis en
conformité : `resolve_folder` est un `gws` hors broker qui a survécu. Le bug
n'est pas une surprise, c'est une dette qui a fini par échoir.

## Proposition

1. **Faire passer `resolve_folder` par le broker**, conformément à la fiche
   0015 — c'est la correction de fond : le broker sait où sont les tokens,
   applique la policy et journalise. À défaut (si le broker n'est pas joignable
   au moment d'un `grant`), **une seule source de vérité pour le CONFIG_DIR** :
   un helper shell qui appelle `gateway.vault.gws_config_dir(alias)` via
   `$SYS_PYTHON`, utilisé par **tous** les appels `gws` de `bin/gwsa`.
2. **Ne plus avaler l'erreur.** `2>/dev/null` transforme une panne d'auth en
   « dossier introuvable ». Distinguer les deux : si `gws` échoue, le dire
   (« profil non authentifié — `gwsa add <alias>` »), ne pas accuser le dossier.
3. **Test de non-régression** dans `scripts/test.sh` : l'invariant existant
   (« aucun `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` dans `gateway/` hors broker »,
   `scripts/test.sh:1049`) ne couvre pas `bin/gwsa`. L'étendre.

## Critères d'acceptation

- [ ] `gwsa grant <alias> ZZ-TESTS 1` résout le nom et affiche `« ZZ-TESTS » (<ID>)`.
- [ ] Le même nom résout vers un **ID différent** sur deux comptes (pas de fuite inter-profils).
- [ ] `gwsa policy <alias> zone <NOM>` résout aussi.
- [ ] Un profil non authentifié donne un message d'auth, **pas** « dossier introuvable ».
- [ ] Nom introuvable / ambigu : toujours refusés, message inchangé, **sans Touch ID**.
- [ ] Les autres appels `gws` de `bin/gwsa` sont audités et passent par le même helper.
- [ ] `scripts/test.sh` échoue si un appel `gws` de `bin/gwsa` repart sur `profile_dir`.
- [ ] Le test manuel `gwsa-grant-resolve-nom` passe de bout en bout.

## Notes

- Introduit par la fiche [0001](0001-elicitation-signee-strongauth-v2.md) (vault) ;
  voir [0003](0003-vault-credentials-hors-perimetre-agent.md).
- Le contournement immédiat pour l'utilisateur : donner l'**ID** du dossier au
  lieu de son nom (branche ID de `resolve_folder`, qui a un fallback
  `${name:-$target}`). Effet de bord du même bug : le message affiche alors
  l'ID brut au lieu du nom, puisque la récupération du nom échoue elle aussi.
- Le test manuel qui a attrapé le bug est versionné dans
  `tests/manuels/gwsa-grant-resolve-nom/`.
