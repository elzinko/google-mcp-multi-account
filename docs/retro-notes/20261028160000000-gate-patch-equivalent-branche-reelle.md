# Le gate classe RÉELLE une branche dont les commits sont déjà sur main sous d'autres hashes

Constat (2026-10-28, clôture) : `claude/changes` (580f2e6) est flaguée RÉELLE alors que ses
commits `refactor(env): émettre MAG_ …` et `docs(features): add 20261018141856581 …` existent
sur main (68406a2, b7f7985) et que `ensure_sign_bin` est déjà dans `gateway/elicitation.py` de main.
Cause probable : cherry-pick/rebase, donc hashes différents, et `unproven=features/BACKLOG.md`
(fichier régénéré) suffit à garder la branche en RÉELLE.
Idée : comparer par `git cherry` / patch-id avant de classer RÉELLE, et ignorer les fichiers générés.
