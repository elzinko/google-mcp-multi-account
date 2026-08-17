# Prompt de lancement — test manuel « drive-cross-compte »

À coller dans une session Claude Code de ce repo (ou déclenché par la phrase
« lance le test manuel drive-cross-compte ») :

```text
Lance le test manuel drive-cross-compte : suis le protocole
tests/manuels/drive-cross-compte/PROTOCOLE.md pour les comptes perso et mw.
Déroule les phases dans l'ordre, demande-moi d'exécuter moi-même chaque
commande d'élicitation (unlock, grant, activation share si besoin), donne-moi
les liens à vérifier au fur et à mesure, et ne nettoie qu'après mon accord.
```

- Les alias par défaut sont **`perso`** et **`mw`** (`mag list` pour confirmer).
- Prérequis : un dossier **`ZZ-TESTS`** à la racine du Drive de **chaque** compte
  (créé par l'humain, interface web — voir PROTOCOLE.md).
- Complète le test [drive-2-comptes](../drive-2-comptes/) : ici on ajoute
  **copie cross-compte** et **partage** (le transfert de propriété est hors de
  cette version).
