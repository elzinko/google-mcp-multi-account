---
id: "20261016104149898"
title: "Popup Touch ID vide sur session_open + client OAuth périmé dans le coffre après changement de projet GCP"
type: bug
priority: P1
product: google-mcp-multi-account
version:
epic:
status: in-progress
ready: 2026-10-16
pr: "#169"
created: 2026-10-16
---

## En clair

Deux bugs vus le même matin, au même endroit : le consentement Touch ID. Le premier rend
une popup **vide** quand une conversation ouvre une session (« session_open — . »). Le
second fait dire à Google « projet supprimé » pour trois comptes pourtant reconnectés
la veille : le coffre gardait le **client OAuth de l'ancien projet** à côté d'un jeton neuf.
Cette fiche corrige les deux, avec un test qui empêche chacun de revenir.

## Contexte / Problème

**Si tu arrives frais.** Quand un agent veut lire une boîte Gmail, la gateway demande
l'accord de l'humain par une popup macOS (Touch ID). Le texte de cette popup est composé
par un petit programme Swift, le *signeur*. Le même texte existe en Python pour vérifier
après coup ce que l'humain a vu. Les deux doivent dire la même chose. Par ailleurs, les
jetons Google de chaque compte vivent dans un *coffre* (`.vault/<alias>/`), avec une copie
du *client OAuth* (le fichier qui dit à Google « quelle application parle »).

**Bug 1 — popup vide.** Le Python connaît l'action `session_open` (« ouvrir une session pour
cette conversation »). Le Swift ne l'a pas dans sa liste et retombe sur le repli technique
`<action> — <alias> <cible>`. L'humain voit « session_open — . » et doit poser le doigt sur
une demande qu'il ne comprend pas. Le test de parité Python ↔ Swift ne couvrait pas cette
action, il est resté vert. Même trou pour `session_grant_capability`.

```
  gateway (Python)                 signeur (Swift)                popup macOS
  action = session_open   ──►   switch action { … }   ──►   « google-multi-account »
                                 (pas de cas)                 souhaite session_open — .
                                 default: "\(action) — …"
```

**Bug 2 — client OAuth périmé dans le coffre.** `mag add` recopie le client OAuth courant
dans le dossier du profil, puis obtient un jeton. La migration vers le coffre déplace le jeton,
mais ne recopiait le client OAuth **que s'il manquait**. Après un changement de projet GCP
(ancien projet supprimé, nouveau client), les comptes reconnectés gardaient donc dans le
coffre le client de l'ancien projet. gws lit le coffre : jeton neuf + client mort → Google
répond « projet supprimé ». Les comptes dont le coffre était vide au moment du re-add
(perso, zz) n'avaient pas le problème, d'où un diagnostic trompeur (« le projet est effacé »
alors que le projet courant va bien).

```
  profil/<alias>/client_secret.json   ← mag add : client du NOUVEAU projet
  .vault/<alias>/client_secret.json   ← copié une fois, figé : ANCIEN projet (supprimé)
  .vault/<alias>/credentials.enc      ← jeton neuf
  gws CONFIG_DIR = .vault/<alias>     → client ancien + jeton neuf → « projet supprimé »
```

## Proposition

- **Signeur Swift** : ajouter les cas `session_open` et `session_grant_capability` avec le
  texte exact du Python. Pas d'identifiant de session dans le texte de `session_open` : la
  session est créée **après** le consentement, elle n'existe pas encore.
- **Test de parité** : couvrir toutes les actions nommées (session_open, session_grant,
  session_grant_capability, grant, unlock ×2, add_account, revoke_descendants, project_sign,
  strongauth_off) et **refuser** tout texte qui commence par le nom brut de l'action (le repli).
- **Coffre** : la copie du client OAuth dans le coffre **suit** celle du profil (comparaison
  du contenu). Le profil est la source de vérité ; la resynchronisation se fait à chaque
  migration, donc au démarrage du broker et à chaque appel `gws_config_dir`. Les trois
  comptes touchés se réparent seuls au premier appel, sans retaper `mag add`.

Hors périmètre : le préfixe « mag : » en double dans la popup. Il a déjà été retiré par
#168 (v1.3.0) ; il ne s'affiche encore que parce que le serveur MCP de Claude Desktop a
démarré avant la mise à jour. Un redémarrage de l'app suffit.

## Critères d'acceptation

- [ ] `elicitation-sign prompt {"action":"session_open"}` affiche « ouvrir une session pour
  cette conversation », identique au Python.
- [ ] `session_grant_capability` affiche le même texte en Swift et en Python.
- [ ] Le test de parité échoue si une action nommée retombe sur le repli `<action> — …`.
- [ ] Après un `mag add` avec un nouveau client OAuth, `.vault/<alias>/client_secret.json`
  est identique au client du profil (test hermétique, trois étapes : première copie, re-add,
  resynchronisation sans nouveau jeton).
- [ ] La copie resynchronisée reste en 0600.
- [ ] Gate hermétique verte (`./scripts/test.sh`).

## Comment vérifier

```bash
./scripts/test.sh   # sections « prompt Touch ID identique Python↔Swift » et « vault : migration »
```

Sur le poste, après déploiement : redémarrer Claude Desktop, puis demander une lecture Gmail
sur `muti`. La popup d'ouverture de session doit dire « ouvrir une session pour cette
conversation » et la lecture doit passer sans « projet supprimé ».

## Notes

- Origine : session du 2026-10-16 (captures des deux popups, message « projet
  gws-multi-802ec6 supprimé » d'une autre session). Diagnostic : projet courant
  `gws-multi-eb3c98` sain (8 APIs, app publiée, 5 comptes IAM) ; seules les copies du
  coffre de muti, mw et coloc pointaient sur l'ancien projet.
- Le déploiement vers `~/.local/share/google-mcp/current` passe par une release ou un
  `mag update` ; la correction du coffre n'agit qu'une fois ce code en place.
