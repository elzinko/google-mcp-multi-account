# Interface d'administration

Webapp locale pour piloter comptes, verrous, policies et zones Drive depuis le navigateur — l'alternative graphique à la CLI [`mag`](usage.md).

```bash
mag admin                 # démarre (détaché, idempotent) + ouvre http://127.0.0.1:4877
mag admin stop            # arrête ; logs dans ~/.config/gws-accounts/admin.log
```

*(équivalent manuel : `node admin/server.js` — local uniquement)*. Les
messages d'élicitation du MCP citent la commande : n'importe quel client LLM
sait donc te proposer de la démarrer quand elle est utile.

Tout se pilote depuis le navigateur : **connecter un compte** (alias + email
attendu — l'onglet Google s'ouvre avec le bon compte présélectionné et la
connexion est refusée si tu choisis le mauvais), **verrouiller/déverrouiller**
(minutes ou `off`), **éditer la policy** service par service avec préréglages
(« prudent » : Drive zones, Gmail brouillons sans envoi, Agenda lecture, Keep
lecture + création), **journal des accès** (qui a fait quoi sur quel compte —
les LLM s'identifient via la variable `GWSA_CLIENT`), **doc intégrée** (❓ :
installation, schémas de séquence, tools MCP, setup OAuth) et **gros bouton
Révoquer** (supprime les tokens du poste, accès coupé immédiatement).

Ajout d'un dossier autorisé sans jamais saisir d'ID : **🔍 recherche par nom**
(plusieurs correspondances → liste de choix avec le chemin complet) ou **📂
navigation** dans Mon Drive (Ouvrir/Choisir), puis durée : temporaire (défaut
8 h) ou permanent. *(Pourquoi des IDs en interne ? Les noms de dossiers Drive ne
sont pas uniques et changent au gré des renommages/déplacements ; l'ID est la
seule référence stable. L'interface fait la conversion nom → ID pour toi.)*

Sécurité : serveur lié à 127.0.0.1 seulement, en-tête custom obligatoire
(anti-CSRF), Origin contrôlée, aucune dépendance npm (mermaid vendorisé en
local), actions déléguées à `bin/mag` (`execFile`, jamais de shell).
