---
id: 0006
title: Harnais hybride pour les tests manuels — script pour la mécanique, LLM pour la glu
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-22
---

## Contexte / Problème

Le premier run de `tests/manuels/drive-2-comptes` (2026-07-22) a marché en
mode 100 % LLM : l'agent improvise les commandes `gwsa` phase par phase et
raconte. Ça fonctionne, mais : (a) le déroulé mécanique (créer/modifier/
recompter dans N comptes) est re-synthétisé à chaque run — variabilité et
tokens ; (b) l'affichage des résultats au fil de l'eau dépend du style de
l'agent ; (c) on aimerait un bilan structuré et comparable d'un run à l'autre.

**Décision (2026-07-22) : on garde le mode LLM pour l'instant** — il vient de
prouver sa valeur en découvrant deux bugs de setup. Cette fiche prépare
l'amélioration, sans la déclencher.

## Proposition

Mode hybride, calqué sur l'ADN du produit (l'outil vérifie, l'humain
autorise, le LLM orchestre) :

1. **`tests/manuels/drive-2-comptes/run.sh <alias>…`** : exécute les phases
   mécaniques (pré-vol, écritures horodatées, contrôles négatifs, recomptage,
   corbeille sur `--cleanup`) en supposant unlocks/grants déjà accordés ;
   sort une checklist ✓/✗ au fil de l'eau + un bilan final (liens webViewLink
   compris). Ne touche JAMAIS à unlock/grant (élicitation humaine).
2. **Le LLM reste le chef d'orchestre** : il déroule PROTOCOLE.md, fait
   éliciter unlocks/grants, lance `run.sh`, relaie la checklist, raconte.
3. Le protocole documente les deux modes ; les assertions (refus attendus)
   restent identiques dans les deux.

## Critères d'acceptation

- [ ] `run.sh perso zz` déroule écritures + négatifs + recomptage et sort un
      bilan ✓/✗ lisible, sans jamais exécuter unlock/grant.
- [ ] Échec d'une assertion (ex. un refus attendu qui passe) → exit ≠ 0 et
      ligne ✗ explicite.
- [ ] PROTOCOLE.md référence les deux modes (LLM seul / LLM + run.sh).
- [ ] Rejouable : noms horodatés, pré-vol qui signale les restes d'un run
      précédent, `--cleanup` corbeille uniquement.

## Notes

- Sœur de la fiche 0005 (même philosophie : scripter le vérifiable,
  éliciter le sensible) — cf. la question soulevée en revue : « un script de
  provisioning plutôt que demander au LLM de provisionner ».
- Garde-fou gws à respecter : `--upload` exige un chemin sous le répertoire
  courant (`.e2e-tmp/`, gitignoré).
