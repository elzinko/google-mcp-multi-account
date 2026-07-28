# Convention « Validation » des PRs

> Référencée par `.github/PULL_REQUEST_TEMPLATE.md` (le template ne porte que le
> squelette ; le fond vit ici). Issue de `ezk-pr-pilot` / ADR-0009 (mega-city),
> adaptée à ce repo CLI + admin locale.

**Le principe : une PR doit être testable par quelqu'un qui n'a pas le contexte.**
Pas « testé ✅ », mais *quoi* a été testé, *comment* le rejouer, *quoi* reste,
et *quel signal observable* dit pass/fail.

## 1. La matrice de modalités

Chaque PR déclare où elle en est sur **chaque** modalité — `✅ fait` (avec la
méthode), `⏳ reste` (avec le plan), ou `N.A.` (avec la raison) :

| Modalité | Quoi |
|---|---|
| **CI** | le pipeline du repo (lien du run) |
| **Tests unitaires / hermétiques** | `./scripts/test.sh` — nouveaux cas listés |
| **Admin / UI locale** | `gwsa admin` + parcours réel + **commandes pour rejouer** |
| **CLI (`gwsa`)** | commandes littérales + sortie / code de sortie attendus |
| **Before / after (UI)** | captures avant/après · ou **N.A.** si aucun changement UI |
| **Preview de déploiement** | **N.A.** (pas de preview distante — outil local) |

## 2. Le bloc « Méthode de test locale » — copy-pastable

Des **commandes littérales**, dans l'ordre, depuis un worktree / clone frais :
worktree path, `gwsa admin stop` si besoin, démarrage admin, `gwsa dev …` le
cas échéant, URL à ouvrir, gestes UI. Le testeur ne doit **rien déduire**.

### Raccourci worktree / branche en cours

Une seule commande déploie le clone courant, redémarre l'admin sur le code
déployé, et affiche un résumé (id, URL, marqueur `afSearchHits`, process) :

```bash
cd <worktree-ou-clone>
./bin/gwsa dev test
```

Options utiles :

- `--no-deploy` — réutiliser le dernier déploiement de cette branche+SHA
- `--isolated` — couloir sans comptes prod (`~/.config/gws-accounts-dev`)
- `--open` — ouvrir `http://127.0.0.1:4877` dans le navigateur (macOS)

Signal pass/fail minimal : la ligne `Marqueur PR : oui — marqueur PR afSearchHits
présent` dans le résumé, et l'admin répond sur l'URL affichée.

## 3. Signaux observables pass/fail

Chaque critère a son signal : message CLI exact, page admin attendue, entrée
MCP écrite, ligne de log. « Ça marche » n'est pas un signal.

## 4. Secrets

Ne jamais coller de tokens, de `client_secret.json`, ni de sortie
`gws auth export` dans le corps de PR. Les chemins
(`~/.config/gws-accounts/`) se citent ; le contenu non.
