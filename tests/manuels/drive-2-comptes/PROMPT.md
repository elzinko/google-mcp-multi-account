# Prompt de lancement — test manuel « drive-2-comptes »

À coller dans une session Claude Code de ce repo (ou déclenché par la phrase
« lance le test manuel drive-2-comptes ») :

```text
Lance le test manuel drive-2-comptes : suis le protocole
tests/manuels/drive-2-comptes/PROTOCOLE.md pour les comptes ALIAS1=<alias1>
et ALIAS2=<alias2>. Déroule les phases dans l'ordre, demande-moi d'exécuter
moi-même chaque commande d'élicitation (unlock, grant), donne-moi les liens
à vérifier au fur et à mesure, et ne nettoie qu'après mon accord.
```

- Remplacer `<alias1>` / `<alias2>` par 2 alias de `gwsa list`.
- Si les alias ne sont pas précisés, le LLM doit les demander avant tout.
- Prérequis : un dossier **`ZZ-TESTS`** à la racine du Drive de chacun des
  2 comptes (créé par l'humain, interface web — voir PROTOCOLE.md).
