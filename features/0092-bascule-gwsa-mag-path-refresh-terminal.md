---
id: 0092
title: Finaliser la bascule gwsa→mag côté PATH + guider le refresh du terminal
type: feature
priority: P2
version:
epic:
status: todo
ready: 2026-09-04
pr:
created: 2026-08-29
---

## En clair

Le renommage `gma → mag` est en place ; l'updater pose déjà `mag` dans le PATH. Restent deux
trous d'**UX** : rien ne dit à l'utilisateur que `gwsa` est déprécié au profit de `mag`, et rien
ne guide le **refresh du terminal** (le shell garde l'ancien chemin en cache, `mag` peut sembler
introuvable). On livre la **dépréciation douce** (`gwsa` marche encore + avertissement) et le
guide de refresh. **Aucun utilisateur cassé.**

## Contexte / Problème

Le renommage `gma → mag` (PR #114) est sur `main`. **Une fois sur une release qui le
contient**, l'updater pose déjà `mag` dans le PATH : `scripts/update.sh` (`link_cli`)
crée `mag` à chaque update — y compris dans le cas « déjà à jour » et pour une install
qui n'avait que `gma`/`gwsa` (Codex #114). **Ce n'est donc PAS à refaire.**

Restent deux trous, non traités aujourd'hui :

1. **Le lien `gwsa` reste exposé sans le dire.** `link_cli` **conserve** `gma`/`gwsa`
   comme repli, mais rien ne signale à l'utilisateur que le nom canonique est désormais
   `mag`.
2. **Le refresh du terminal n'est pas guidé.** Après bascule, le shell garde en cache
   l'ancien chemin ; `mag` peut sembler « introuvable » et `gwsa` répondre encore tant
   qu'on n'a pas fait `hash -r` ou ouvert un nouveau shell. Rien ne le dit.

Cas limite à couvrir (celui vécu en test 2026-08-29) : une mise à jour **exécutée par une
release PRÉ-#114** lance l'**ancien** `update.sh`, qui ne connaît pas `mag` → `mag` reste
absent tant qu'on n'est pas passé par une release ≥ #114. À expliquer dans le message de sortie.

## Stratégie retenue — NON-RÉGRESSION d'abord (décidé le 2026-08-29)

**On ne casse aucun utilisateur existant** (dont le mainteneur), qui tape `gwsa`
aujourd'hui — scripts, habitudes, muscle-memory. Donc **dépréciation en douceur**, en deux
temps :

- **Prochaine release (mineure, additive)** : `mag` devient le nom canonique **et
  `gwsa`/`gma` continuent de fonctionner**, avec un **message de dépréciation** au premier
  usage (« `gwsa` est déprécié — utilise `mag` »). Zéro commande cassée.
- **Release MAJEURE ultérieure** (annoncée, une fois les utilisateurs migrés) : **retrait
  effectif** de `gwsa`/`gma` exposés. C'est un breaking change assumé → bump majeur + note
  de version. Le repli **interne** pour le rollback (cf. [[0081]]) est conservé même alors.

Cette fiche livre le **1er temps** (dépréciation douce + guide refresh). Le 2e temps
(retrait dur) est une sous-tâche distincte, à créer au moment voulu.

## Proposition (à groomer)

- **Exposer `mag`** : déjà assuré par `link_cli` (#114) — ne rien réimplémenter.
- **Déprécier `gwsa`/`gma`** sans les retirer : les garder invocables, mais afficher un
  **avertissement de dépréciation** au premier usage (une fois par session, non bloquant),
  pointant vers `mag`.
- **Détecter le cache shell obsolète** : si `mag` n'est pas encore résolu (ou `gwsa` répond
  encore un ancien chemin), afficher un encart clair — « ouvre un nouveau terminal, ou
  lance `hash -r` ».
- **Message de fin d'update** : annoncer le nom canonique `mag`, la commande à retaper, et
  le cas « update depuis une release pré-#114 » (repasser par `update` une fois sur ≥ #114).
- Garder le **binaire/alias interne** `gwsa`/`gma` pour le repli **rollback** (cf. [[0081]]).

## Critères d'acceptation (BDD, à affiner)

- **Given** une install sur `gwsa`, sur une release ≥ #114 **When** update **Then** `mag`
  est dans le PATH **et** `gwsa` **répond toujours** (aucune régression) en affichant un
  avertissement de dépréciation vers `mag`.
- **Given** un utilisateur qui continue de taper `gwsa <cmd>` **Then** la commande
  **fonctionne** exactement comme avant (le warning ne bloque ni ne change la sortie utile).
- **Given** un shell qui a mis `gwsa`/`mag` en cache **Then** l'updater détecte le cas et
  guide le refresh (nouveau terminal / `hash -r`).
- **Given** un rollback vers une version pré-renommage **Then** les commandes restent
  invocables (cohérent avec [[0081]] — repli interne conservé).

## Comment vérifier

Sur une install `gwsa`, release ≥ #114, lancer `update` : `mag` est dans le PATH **et** `gwsa`
répond toujours, avec un avertissement de dépréciation vers `mag`. Retaper `gwsa <cmd>` : marche
exactement comme avant (le warning ne bloque ni ne change la sortie). Sur un shell au cache
obsolète : l'updater détecte le cas et guide le refresh (`hash -r` / nouveau terminal).

## Notes

- Complète [[0081]] (bugs de liens au rollback) côté **dépréciation en douceur** et **UX
  du refresh terminal**. Ne recrée pas la pose de `mag` (déjà livrée #114).
- **Retrait dur de `gwsa`** = fiche/sous-tâche séparée + **release majeure** (breaking),
  décision humaine, annoncée. Pas dans ce lot.
- Cluster updater/renommage : [[0081]] / [[0091]] / 0092 / [[0028]] — épic commun à envisager.
