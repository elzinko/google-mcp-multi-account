# google-mcp-multi-account — consignes pour Claude

Projet : accès **multi-comptes** Google (Gmail, Drive, Calendar, Docs, Sheets,
Tasks) depuis des agents LLM, via le serveur MCP local (`bin/google-mcp` →
`gateway/`) et le wrapper `bin/gwsa` (admin / élicitation).

## Règles

1. **Préférer le MCP** pour lire/écrire des données (tools `profiles_list`,
   `gmail_*`, `drive_*`). Ne pas appeler `gws` nu. Si tu utilises le shell :
   `gwsa <alias> …` uniquement — jamais
   `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=… gws …` (contourne policy et verrous).
2. Découvrir les comptes : tool `profiles_list` ou `gwsa list`. En cas de doute
   sur le compte, demander à l'utilisateur.
3. Confirmer avec l'utilisateur avant tout envoi ou modification visible de
   l'extérieur. **Aucun tool MCP n'envoie de mail** (brouillons seulement).
4. Ne jamais lire, afficher ou committer `~/.config/gws-accounts/` (tokens),
   `client_secret.json`, ni la sortie de `gws auth export`.
5. Les skills `.claude/skills/gws-*` documentent la syntaxe des APIs avec des
   exemples en `gws …` : remplacer `gws` par `gwsa <alias>`, ou utiliser le MCP.
6. **Profils verrouillés = accès sur demande (élicitation).** En cas de refus
   « verrouillé » : appeler le tool `access_request` (kind=`unlock`) et
   **demander à l'utilisateur** d'exécuter la commande suggérée (ou l'admin).
   Ne JAMAIS déverrouiller / éditer `.locked` / contourner de ta propre initiative.
7. **Policy par service et par profil (default-deny).** Un service non déclaré
   est refusé. Ne pas contourner. Consulter : `gwsa policy <alias> show`.
8. **Écriture Drive = élicitation.** Si refus de zone : `access_request`
   kind=`grant` avec le dossier, puis attendre l'accord humain
   (`gwsa grant …` ou admin). Les grants expirent : redemander est normal.
9. **S'identifier dans le journal** : le MCP positionne `GWSA_CLIENT=mcp` ;
   en shell : `GWSA_CLIENT=claude-code gwsa …`.

## Commandes utiles

```bash
./scripts/provision-gcp.sh status # état du provisioning GCP (lecture seule)
node admin/server.js # interface d'admin → http://127.0.0.1:4877
gwsa list # profils + état
gwsa add <alias> # connecter un nouveau compte (navigateur) + policy prudente
gwsa <alias> auth status # état du token d'un profil
gwsa lock <alias> / gwsa unlock <alias> [min|off] # verrou « accès sur demande »
gwsa grants <alias> / gwsa grant <alias> <dossier> [h] # zones Drive temporaires
gwsa strongauth status # Touch ID exigé pour unlock/grant ?
./bin/google-mcp # serveur MCP stdio (voir docs/mcp-setup.md)
./scripts/test.sh # tests automatiques hermétiques (sans comptes réels)
```

**Tests manuels** (comptes réels, guidés) : sur une demande type « lance un
test manuel », lire `tests/manuels/README.md` — chaque test y stocke son
prompt (`PROMPT.md`) et son protocole (`PROTOCOLE.md`) ; le dérouler phase
par phase en laissant l'humain exécuter unlock/grant.

Erreur `exit code 2` (auth) sur un profil → token expiré : proposer
`gwsa add <alias>` pour reconnecter (l'app OAuth en mode Testing expire à 7 jours).

Erreur `403 … required permission to use project <id>` → le compte n'a pas le
rôle IAM `serviceUsageConsumer` sur le projet GCP de l'app OAuth : proposer à
l'utilisateur la commande `gcloud projects add-iam-policy-binding …` de
`docs/setup-oauth.md` §7 (geste admin humain — ne jamais l'exécuter soi-même).
Pour l'état complet (quels comptes manquent + la commande par compte) :
`./scripts/provision-gcp.sh status`. `gwsa add` affiche aussi la commande
automatiquement si le compte fraîchement connecté n'a pas le rôle.
