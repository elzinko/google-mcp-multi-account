# Purge des branches absorbées bloquée par le classifier auto-mode

**Symptôme (session 2026-09-20, clôture ezk-archive `run`).** La correction sûre
prévue par ezk-archive — supprimer les branches ABSORBÉES prouvées par `check.sh`
via `git branch -D` — a été **refusée par le classificateur auto-mode** (« Git
Destructive »), en environnement sous-agent non-interactif. Les 8 branches
absorbées n'ont pas pu être purgées automatiquement ; elles ont été rendues à
l'humain sous forme de commande à coller (dans le handoff).

**Pourquoi ça compte.** ezk-archive `run` annonce la purge des branches absorbées
comme une correction sûre et automatique. Quand le harness la bloque, la promesse
« la clôture range » devient « la clôture propose une commande » — le nettoyage
retombe sur l'humain à chaque run, exactement le geste manuel récurrent que le
rituel voulait supprimer.

**Piste mesurable (à trancher en rétro).**
1. Ajouter une règle de permission Bash ciblée `git branch -D` (scopée aux branches
   marquées `safe_delete=1` par le gate) pour laisser la purge s'exécuter.
2. Assumer que la purge est un geste humain : ezk-archive émet toujours la commande
   dans le handoff au lieu de tenter `git branch -D`, et ne l'affiche plus comme
   « correction automatique appliquée ».

Commande concernée cette session (récupérable via reflog) :
`git -C /Users/elzinko/git/google-mcp-multi-account branch -D claude/plan-0108-sequence feat/0019-cli-messages-anglais feat/0070-readme-personas-contributing feat/0086-raffinements-audit-capacites-session feat/0093-nommage-mag-produit feat/0098-micro-routeur-vues feat/20260910194019668-elicitation-in-conversation-opt-in work-0086-raffinements`
