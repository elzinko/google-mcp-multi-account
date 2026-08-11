<!-- Convention complète : docs/PR_VALIDATION.md (le template n'est qu'un squelette). -->

## Summary
<!-- Court. Le diff dit le comment ; ici, le quoi et le pourquoi. -->

## Validation — voir [docs/PR_VALIDATION.md](../docs/PR_VALIDATION.md)

| Modalité | Statut |
|---|---|
| CI | |
| Tests hermétiques (`./scripts/test.sh`) | ✅ / ⏳ / N.A. |
| Admin / UI locale | ✅ / ⏳ / N.A. |
| CLI (`gma`) | ✅ / ⏳ / N.A. |
| Before / after (UI) | ✅ liens / N.A. |
| Preview distante | **N.A.** (outil local) |

### Méthode de test locale (copy-pastable)
```bash
cd <worktree-ou-clone>
./scripts/test.sh
# commandes exactes pour rejouer la feature (gma admin, gma dev, …)
```

### Reste à valider (signaux observables)
<!-- 1 ligne par critère : l'action exacte + le signal pass/fail. -->
