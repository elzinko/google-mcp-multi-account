fiches: 0060,0082,0017

# Run autonome — grooming du backlog (product-build)
Config: --mode auto · --check-ready false · --tokens lean · PAS d'implémentation ici (directive PO : collision admin/index.html)
Objectif: groomer les fiches non-ready vers ready ; tampon ready autonome (concurrence ezk-pm) ; push main. Stop seulement sur les 4 décisions humaines.

## File de grooming
- [~] 0108 — accès fin par session (épic 0082, Jalon B) → **BLOQUÉE sur spike humain** (voir notes)
- [ ] 0101 — nom de session (épic 0082) · en évaluation
- [ ] 0086 — audit/migration capacités session (épic 0082) · en évaluation
- [ ] (reste : réévaluer par priorité)

## Notes / décisions
- 2026-09-04 : PO invoque `run --mode=auto, groome tout seul`. Interprétation : grooming autonome + tampon ready (check-ready false) + push main, SANS build ici (directive « on crée les fiches et push » tient). Stop seulement sur les 4 décisions humaines.
- 2026-09-04 : **0108 SKIP (journalisé, à surfacer), pas forcée ready.** La fiche est déjà très groomée (contexte code : deux portes d'enforcement api.py:118 + broker_server.py:202, injection du joker :181/246 ; 8 critères vérifiables). Mais son critère #1 est un **constat de faisabilité sur client RÉEL** (un client MCP peut-il porter une identité par conversation ?), non constaté — slot DoR « dépendance externe constatée » NON satisfait. ADR-0007 note déjà « branché à vide » (Claude Desktop = une seule connexion). Ce constat exige un client réel + l'humain : je ne le forge pas en autonomie. Le statut `idea` posé par l'auteur reflète cette incertitude assumée. → surfacer comme spike humain.
- [ezk-pm] 2026-09-04 — DoR concurrence (check-ready false) sur 4 fiches groomées → **0086 GO**, **0070 GO**, **0090 NO-GO**, **0093 GO**. Motifs : 0086/0070/0093 remplissent les 5 critères DoR (problème, valeur, critères observables, « Comment vérifier », aucune dépendance externe bloquante) ; 0090 NO-GO car proposition « à groomer » + critères « à affiner » non verrouillés, décision de scope (scinder warning vs Testing→Production) non tranchée, et faits chiffrés Google (coûts/seuils vérif) à constater sur source datée — non fait. Réversible : re-tamponner 0090 après finalisation critères + arbitrage split.
- [ezk-pm] 2026-09-04 — DoR concurrence (check-ready false) cluster updater/rollback → **0081 GO**, **0091 GO**, **0092 GO**. Motifs : les 3 remplissent les 5 critères DoR (problème clair, valeur, critères BDD observables, « Comment vérifier », aucune dépendance EXTERNE constatée manquante). 0081 = socle interne (findings Codex #114 r5 + test hermétique). 0091/0092 portent des critères notés « à affiner » mais les décisions de scope sont VERROUILLÉES (0091 : lien `previous` posé à chaque bascule ; 0092 : dépréciation douce en 2 temps, non-régression) → verrouillage tranché = DoR OK, contrairement à 0090 laissée NO-GO. Dépendance 0091/0092 → helper de 0081 = INTERNE (séquencement), ne bloque pas la DoR ; à ordonner dans PLAN.md (0081 avant 0091/0092). Réversible : dé-tamponner si le grooming ré-ouvre une décision de scope.
- épic 0060 rangé (session précédente) : 5 shipped, ex-0100 fusionnée, 0097/0098/0106/0107 ready, plan ordonné.

## Galères & gestes (labo)
