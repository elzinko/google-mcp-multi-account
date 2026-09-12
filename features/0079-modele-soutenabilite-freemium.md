---
id: 0079
title: Modèle de soutenabilité — freemium (cœur libre + options payantes)
type: feature
priority: P3
version:
epic:
status: idea
ready:
pr:
created: 2026-08-15
---

## Contexte / Problème

Le projet devient open source (ADR-0008). Rester libre **et** soutenable dans le temps
suppose un modèle économique : financer la maintenance et le temps passé, **sans trahir
l'éthos** (souveraineté, 100 % local, jetons jamais chez un tiers).

Direction du PO (2026-08-15) : un **modèle freeware** — un cœur **gratuit** + des
**options payantes** pour soutenir le projet.

## Proposition (direction à cadrer — pas encore une spec)

Pistes classiques du libre soutenable, à évaluer contre l'éthos :
- **Open core** : cœur libre (holder, approbation, policy) ; extensions payantes
  (multi-utilisateurs / équipe, connecteurs avancés, tableaux de bord).
- **Hosted / managed** : le code reste libre et auto-hébergeable ; on **vend la commodité**
  d'un service géré (ex. un **relais aveugle** hébergé, des mises à jour signées) — jamais
  l'accès aux jetons, qui restent chez l'utilisateur.
- **Support / sponsoring** : support prioritaire, sponsors GitHub, licences entreprise.
- **Dual-license** : libre pour le perso, licence commerciale pour l'entreprise.

Tension à trancher : que rendre payant **sans** casser la promesse « souverain, rien ne
sort de chez toi » ? Le payant doit porter sur la **commodité / le service**, jamais sur
la sécurité ni la possession des données.

## Critères d'acceptation

- [ ] Un cadre décidé : ce qui est **toujours gratuit** vs **payant**, cohérent avec l'éthos.
- [ ] Compatibilité avec la licence effective (**MIT**, `LICENSE` / fiche [[0016]]) vérifiée.

## Notes

- Direction **non mûre** — capturée pour ne rien perdre ; à groomer (brainstorm dédié)
  avant d'être tirable.
- Recoupe le passage open source de l'épic [[0077]] et l'ancienne fiche licence [[0016]]
  (MIT, livrée).
- **Décision PO (2026-09-04)** : gardée en idée « un jour peut-être », **basse prio (P3)**, sans
  engagement. Un modèle économique reste très spéculatif pour un outil 100 % local mono-utilisateur.
  Capturée pour ne rien perdre, pas un objectif de roadmap.
