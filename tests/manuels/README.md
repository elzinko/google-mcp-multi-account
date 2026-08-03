# Tests manuels — point d'entrée

Tests **guidés, avec de vrais comptes Google**, complémentaires de la suite
automatique hermétique (`./scripts/test.sh`, qui ne touche jamais un compte
réel). Un test manuel se déroule dans une session Claude Code de ce repo :
le LLM pilote, **l'humain garde les gestes d'élicitation** (unlock, grant)
et la vérification visuelle.

## Lancer un test

Dans une session Claude Code, dire simplement :

> lance le test manuel drive-2-comptes

ou, pour le cross-compte perso ↔ mw (partage) :

> lance le test manuel drive-cross-compte

Le LLM doit alors lire le `PROTOCOLE.md` du test et le dérouler phase par
phase. Chaque test a son répertoire, qui contient **tout** :

| Fichier | Rôle |
|---|---|
| `PROMPT.md` | Le prompt de lancement (à coller tel quel, ou déclenché par la phrase ci-dessus) |
| `PROTOCOLE.md` | Les indications détaillées : phases, commandes, critères de réussite, dépannage |

## Tests disponibles

| Test | But | Durée | Prérequis humain |
|---|---|---|---|
| [drive-2-comptes](drive-2-comptes/) | Lecture + écriture + modification Drive sur **2 comptes dans un même prompt**, élicitation comprise, nettoyage réversible | ~10 min | Dossier `ZZ-TESTS` à la racine des 2 Drive concernés |
| [drive-cross-compte](drive-cross-compte/) | **Copie cross-compte** et partage entre **perso** et **mw** dans `ZZ-TESTS` (transfert de propriété hors périmètre) | ~15 min | `ZZ-TESTS` sur les 2 Drive ; activer `share` sur le compte source pour la phase partage |
| [gwsa-grant-resolve-nom](gwsa-grant-resolve-nom/) | `gwsa grant` résout un dossier **par son nom** : par compte, refus francs (introuvable / ambigu / corbeille), sans Touch ID gaspillé. N'écrit aucun fichier | ~8 min | Dossier `ZZ-TESTS` à la racine des 2 Drive + **deux** dossiers homonymes `ZZ-AMBIGU` |

## Conventions (tous les tests)

- **Bac à sable** : toute écriture Drive se fait sous un dossier `ZZ-TESTS`
  créé par l'humain à la racine du Drive concerné. Rien d'autre n'est touché —
  la policy (zones, default-deny) le garantit, et le test le vérifie.
- **Élicitation humaine** : le LLM ne déverrouille jamais un profil et ne
  s'accorde jamais de zone. Il demande ; l'humain exécute (`gwsa unlock`,
  `gwsa grant`), Touch ID si strongauth est activé.
- **Refus attendus = assertions** : un test manuel vérifie aussi que les
  barrières tiennent. Une étape « refus attendu » qui passe est un échec.
- **Nettoyage réversible** : corbeille uniquement (restaurable 30 jours),
  sur accord explicite. La suppression définitive reste un geste humain
  dans Drive.
- **Identification** : commandes shell via `GWSA_CLIENT=claude-code gwsa …`
  (jamais `gws` nu), tools MCP quand ils existent — tout est journalisé.

## Ajouter un test

Créer `tests/manuels/<nom-du-test>/` avec `PROMPT.md` + `PROTOCOLE.md`
(s'inspirer de [drive-2-comptes](drive-2-comptes/)), puis l'ajouter au
tableau ci-dessus. Rien d'autre à câbler.
