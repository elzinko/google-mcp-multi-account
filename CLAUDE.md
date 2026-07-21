# google-mcp-multi-account — consignes pour Claude

Projet : accès **multi-comptes** Google (Gmail, Drive, Calendar, Docs, Sheets,
Tasks) depuis des agents LLM, via le CLI `gws` et le wrapper `bin/gwsa`.

## Règles

1. **Toujours cibler un compte via `gwsa <alias> <commande gws…>`** (le wrapper
   est aussi dans le PATH). Ne jamais utiliser `gws` nu ici : il pointerait sur
   le profil mono-compte par défaut (`~/.config/gws`), pas sur les profils du projet.
2. Découvrir les comptes disponibles : `gwsa list`. En cas de doute sur le compte
   à utiliser pour une action, demander à l'utilisateur.
3. Confirmer avec l'utilisateur avant tout envoi ou modification visible de
   l'extérieur (envoi de mail, partage de fichier, invitation d'agenda).
4. Ne jamais lire, afficher ou committer `~/.config/gws-accounts/` (tokens),
   `client_secret.json`, ni la sortie de `gws auth export`.
5. Les skills `.claude/skills/gws-*` documentent la syntaxe des APIs avec des
   exemples en `gws …` : remplacer `gws` par `gwsa <alias>` dans ces exemples.
6. **Profils verrouillés = accès sur demande (élicitation).** Certains profils
   sont verrouillés (🔒 dans `gwsa list`) : toute commande échoue avec « profil
   verrouillé ». Ne JAMAIS déverrouiller de ta propre initiative ni contourner
   le verrou : demander à l'utilisateur, qui déverrouille lui-même avec
   `gwsa unlock <alias> [minutes]` (ou te demande explicitement de le faire).
   Le reverrouillage est automatique à l'expiration.
7. **Policy par service et par profil.** Un refus « policy <service> — … »
   signifie que le profil est restreint (ex. Drive : écriture seulement en
   zones ; Gmail : brouillons autorisés mais envoi interdit). Ne pas
   contourner ni insister. Consulter : `gwsa policy <alias> show`.
8. **Écriture Drive = élicitation obligatoire.** Par défaut, aucune zone
   d'écriture. Avant d'écrire sur Drive : vérifier les zones actives
   (`gwsa grants <alias>` + policy show), et si la cible n'y est pas,
   PROPOSER à l'utilisateur la commande exacte et l'exécuter seulement
   après son accord explicite :
   `gwsa grant <alias> "<dossier>" [heures]` (temporaire, recommandé) ou
   `gwsa policy <alias> allow "<dossier>"` (permanent). Les grants expirent
   automatiquement : c'est normal de redemander à chaque session.
9. **S'identifier dans le journal** : préfixer chaque commande par
   `GWSA_CLIENT=claude-code`, ex. `GWSA_CLIENT=claude-code gwsa perso gmail …`
   (les accès sont journalisés dans l'interface d'admin).

## Commandes utiles

```bash
./scripts/provision-gcp.sh status           # état du provisioning GCP (lecture seule)
node admin/server.js                        # interface d'admin → http://127.0.0.1:4877
gwsa list                                   # profils + état
gwsa add <alias>                            # connecter un nouveau compte (navigateur)
gwsa <alias> auth status                    # état du token d'un profil
gwsa lock <alias> / gwsa unlock <alias> [min|off]   # verrou « accès sur demande »
gwsa grants <alias> / gwsa grant <alias> <dossier> [h]  # zones Drive temporaires (élicitation)
gwsa strongauth status                      # Touch ID exigé pour unlock/grant ?
gwsa <alias> gmail users messages list --params '{"userId":"me","maxResults":5}'
gwsa <alias> calendar +agenda --today       # agenda du jour
gwsa <alias> schema gmail.users.messages.list   # schéma d'une méthode API
```

Erreur `exit code 2` (auth) sur un profil → token expiré : proposer
`gwsa add <alias>` pour reconnecter (l'app OAuth en mode Testing expire à 7 jours).
