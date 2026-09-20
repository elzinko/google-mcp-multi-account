# Test E2E — Consentement « une fois / pour la session »

Protocole **guidé, vrais comptes**, pour prouver le geste de Claude Code appliqué
au transactionnel : au moment d'autoriser une écriture Drive, choisir **« une
fois »** ou **« pour la session »** — et vérifier que le partage reste toujours
signé par acte. Complète la suite hermétique `./scripts/test.sh` (qui ne touche
aucun compte réel).

Raffine le test manuel de #149. S'appuie sur
[ADR-0013](../../../docs/adr/ADR-0013-consentement-une-fois-ou-session.md).

Prompt de lancement : voir [PROMPT.md](PROMPT.md).

## Prérequis (2 min, humain)

1. Un compte dans `mag list` (ex. `perso`) avec un dossier **`ZZ-TESTS`** à la
   racine du Drive, et **deux sous-dossiers** `ZZ-TESTS/DOSSIER-A` et
   `ZZ-TESTS/DOSSIER-B` (pour prouver que la grâce est scopée au dossier exact).
2. Transactionnel **activé** et mode **manuel** :
   ```bash
   mag transactional on
   mag transactional mode manuel
   mag transactional status   # vérifier : consent enabled, lease mode manuel
   ```
3. `mag strongauth status` : Touch ID actif = le vrai geste. (Sans strongauth, le
   consentement passe quand même par le chemin signé ; le test reste valable.)
4. Jetons : si le compte n'a pas servi depuis > 7 j (app OAuth *Testing*), prévoir
   `mag add <alias>` en cours de route (erreur `exit code 2`).

## Déroulé (ce que l'agent doit faire)

Commandes agent via `GWSA_CLIENT=claude-code mag …` ou les tools MCP du serveur
transactionnel (`gma-tx` : `profiles_list`, `drive_*`, `access_request`,
`session_open_in_conversation`, `session_unlock_in_conversation`). Le choix de
portée s'exprime dans la conversation (« autorise pour la session ») ; le popup
Touch ID **affiche la portée demandée** avant que l'humain pose le doigt.

### Phase 0 — état des lieux (lecture seule)
- `mag list` : compte présent, 🔒 verrouillé.
- `mag transactional status` : consent enabled, lease mode manuel.
- Annoncer le plan et les dossiers attendus (`ZZ-TESTS/DOSSIER-A`, `/DOSSIER-B`).

### Phase 1 — « une fois » = par acte, zéro TTL (critère 1)
- Ouvrir une session. Écrire un fichier `essai-<TS>.md` dans `DOSSIER-A`, portée
  **« une fois »** → un consentement (Touch ID) **est demandé**, son texte nomme
  l'acte (écrire · compte · DOSSIER-A) et la portée **une fois**.
- **Refaire la même écriture** dans `DOSSIER-A` (« une fois ») → un **nouveau**
  consentement est demandé. *Preuve : « une fois » n'ouvre aucun droit au-delà de
  l'acte.*

### Phase 2 — « pour la session » : le même périmètre repasse (critère 2)
- Écrire un `essai-<TS>.md` dans `DOSSIER-A`, portée **« pour la session »** →
  consentement demandé, le prompt annonce la portée **session**.
- **Écrire encore** dans `DOSSIER-A` → **aucun** consentement demandé, l'écriture
  passe directement. *Preuve : la grâce couvre ce périmètre exact.*

### Phase 3 — périmètre différent = redemande (critère 2, revers)
- Écrire dans `DOSSIER-B` (jamais accordé) → consentement **redemandé**.
  *Preuve : la grâce est scopée au dossier exact, pas au service entier.*

### Phase 4 — le partage reste signé par acte (critère partage)
- Accorder `share` sur le compte (préréglage), puis **partager** un fichier de
  `DOSSIER-A` (`drive permissions create`) — même après le « pour la session » de
  la Phase 2 → consentement **demandé** (portée forcée « une fois », pas de choix
  « session »).
- Refaire un partage → consentement **encore** demandé. *Preuve : le partage n'est
  jamais couvert par la grâce, c'est la ligne rouge.*

### Phase 5 — mode réglable depuis l'admin (critère admin)
- Ouvrir `mag admin` (http://127.0.0.1:4877), panneau du sélecteur de mode.
- Basculer **manuel → auto** : une série de **lectures** dans `DOSSIER-A` se groupe
  sous **un** consentement (fenêtre auto), et le choix « une fois / session » **ne
  s'affiche plus**.
- Rebasculer **auto → manuel** : le choix réapparaît. Vérifier la **persistance**
  (le mode survit à un redémarrage) et le **repli manuel** si le réglage est absent.

### Phase 6 — la grâce meurt avec la session (critère durée de vie)
- Fermer la session (`mag session close <sid>`) **ou** attendre l'expiration.
- Réécrire dans `DOSSIER-A` → consentement **redemandé**. *Preuve : « pour la
  session » ne survit pas à la session ; aucune durée propre.*
- (Bonus durées) `mag session unlock … <minutes>` en transactionnel → **refus**,
  renvoi vers « pour la session ».

### Phase 7 — vérification humaine + nettoyage
- L'agent fournit les `webViewLink` des fichiers créés ; l'humain ouvre, connecté
  au bon compte, et confirme.
- Nettoyage réversible : l'humain met `DOSSIER-A`/`B` à la corbeille depuis Drive
  (la racine de zone reste immuable côté LLM, fiche 0037). Grâces et verrous se
  referment seuls.

## Critères de réussite
- [ ] « une fois » : la même écriture redemande à chaque fois (Phase 1).
- [ ] « pour la session » : le même dossier repasse sans geste (Phase 2).
- [ ] Un dossier différent redemande (Phase 3).
- [ ] Le partage redemande toujours, même après un « pour la session » (Phase 4).
- [ ] Mode réglable depuis l'admin, persisté, repli manuel (Phase 5).
- [ ] La grâce meurt à la fin de la session ; `unlock` par minutes refusé en
      transactionnel (Phase 6).
- [ ] Journal : les actes tracés avec `GWSA_CLIENT` (admin → journal).

## Dépannage
| Symptôme | Cause | Remède |
|---|---|---|
| `exit code 2` | Token expiré (app *Testing*, 7 j) | `mag add <alias>` puis reprendre |
| Le choix « session » n'apparaît pas | Mode `auto` actif | Repasser en `manuel` (admin ou `mag transactional mode manuel`) |
| Le 2ᵉ acte redemande alors qu'on a dit « session » | Dossier différent, ou session expirée | Vérifier le dossier exact / la session |
| Un partage passe sans geste | **Bug à remonter** — le partage doit toujours redemander | — |
| L'agent propose de déverrouiller lui-même | Interdit (CLAUDE.md) | L'humain exécute les gestes, toujours |
