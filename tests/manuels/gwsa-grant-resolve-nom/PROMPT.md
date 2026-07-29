# Prompt de lancement — test manuel « gwsa-grant-resolve-nom »

À coller dans une session Claude Code de ce repo (ou déclenché par la phrase
« lance le test manuel gwsa-grant-resolve-nom ») :

```text
Lance le test manuel gwsa-grant-resolve-nom : suis le protocole
tests/manuels/gwsa-grant-resolve-nom/PROTOCOLE.md pour les alias perso et mw.
Déroule les phases dans l'ordre, demande-moi d'exécuter moi-même chaque
commande d'élicitation (unlock/Touch ID si requis), et ne nettoie qu'après
mon accord.
```

- Alias par défaut : `perso` et `mw` (confirmer via `gwsa list`).
- Prérequis : un dossier **`ZZ-TESTS`** à la racine du Drive de **chaque** compte.
