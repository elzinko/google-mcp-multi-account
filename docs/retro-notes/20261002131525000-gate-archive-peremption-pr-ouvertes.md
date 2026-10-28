# Le gate d'ezk-archive se périme sur les faits time-sensibles (PRs ouvertes)

**Date :** 2026-10-02 · **Repo :** google-mcp-multi-account · **Déposé par :** clôture ezk-archive

## Symptôme vécu
Pendant une clôture `ezk-archive run`, le bloc gate du portier (`scripts/check.sh`) annonçait
`P2_PENDING: pr_open=2` et listait `[P2] pr #161` et `[P2] pr #160` comme PRs ouvertes.
Quelques minutes plus tard, un `gh pr view 160/161` live les montrait **toutes deux MERGÉES**,
et `gh pr list --state open` renvoyait `0`. Des sessions concurrentes les avaient mergées dans
l'intervalle entre l'exécution du portier et celle du sous-agent juge.

Conséquence : si le sous-agent recopie le gate tel quel, le handoff liste comme « pending » des
PRs qui n'existent plus — exactement le contre-sens de « ne rien perdre » (on fait perdre du
temps à la reprise sur du faux pending).

## Pourquoi ça arrive ici
Ce repo a des sessions parallèles rapides (cf. mémoire « Main parallèle et rapide ») et une
convention squash-merge. L'état des PRs change à la minute. Le gate est un instantané ; le
sous-agent tourne après.

## Piste pour la rétro (à débattre)
Les faits **git live** (PRs ouvertes surtout) sont déjà réputés « recalculés à chaque run »
par le gabarit de handoff — mais c'est le **portier** qui les a figés, pas le juge. Deux options :
1. Le sous-agent re-vérifie systématiquement les faits time-sensibles (PRs ouvertes) en live
   avant d'écrire le handoff, au lieu de faire confiance au `pr_open=N` du gate.
2. Le portier marque ces faits comme « instantané à T, re-vérifier » pour que le juge sache
   lesquels sont volatils.

Mesure possible : sur les prochaines clôtures, 0 PR listée en pending qui soit en fait déjà
mergée/fermée au moment où le handoff est écrit.

> Note : ce fichier est un dépôt best-effort pour le temps 1 d'`ezk-retro`. Il n'est pas
> committé automatiquement — à verser au dépôt si on veut qu'il survive à ce worktree.
