# PLAN — google-multi-account

> **Séquence décidée** (curée, arbitrage PO) — *quoi groomer/tirer ensuite, et dans quel ordre*.
> Ce n'est **pas** l'index : l'index trié par priorité est [BACKLOG.md](BACKLOG.md), et le gate
> technique de tirage reste `ready`. Décidé le **2026-09-03**.

## NOW — la refonte admin d'abord, l'accès fin par session ensuite

**Jalon A — Finir l'admin (épic [0060](0060-admin-ux-ui-refresh.md)).** Série Cockpit : l'essentiel est **livré**, reste le fonctionnel et la dernière migration.

- [0094](0094-sessions-page-dediee-reactive.md) — Sessions en page dédiée réactive · **build** *(in-progress)*
- ~~[0107](done/0107-vue-compte-droits-sur-place.md) — Vue compte : droits sur place, au grain par opération~~ — **shipped #131** (2026-09-05)
- [0098](0098-micro-routeur-vues.md) — Micro-routeur (VIEW + poll unifiés) · **build** *(ready)* — refactor indépendant, quand on veut
- ~~[0106](done/0106-vue-compte-orientee-sessions.md) — Vue compte orientée sessions (compteur + liste des sessions)~~ — **shipped #132** (2026-09-05)
- ~~[0097](done/0097-composants-transverses.md) — Finir la migration des dialogues → design system~~ — **shipped #133** (2026-09-05)

> **Rangé au grooming (2026-09-03).** Déjà livrées par Cockpit (#128) : 0095 (tokens), 0099 (sessions
> pilote), 0102 (journal), 0103 (barre de nav), 0104 (app shell mobile). Fusionnée : ex-0100 → 0097.
> Restes mineurs capturés en idées : filtre « date » du journal, cibles tactiles 44 px mobile. Base
> technique prête mais **différée** (décision PO) : 0096 (socle de rendu sûr `html`` ``).

**Jalon B — Accès fin par session — APRÈS le jalon A.**

- [0108](0108-session-demande-sous-ensemble-droits-compte.md) — une session demande son sous-ensemble de droits du compte · **bloqué sur un spike** (identité par conversation d'un client MCP — à constater sur client réel) puis groom + build

## NEXT — robustesse updater (indépendant de l'admin)

**Jalon C — Cluster updater / renommage.** Fiches prêtes (grooming autonome 2026-09-04), à séquencer : **le socle d'abord** (0091 et 0092 réutilisent son helper de re-ciblage).

- ~~[0081](done/0081-durcir-updater-rollback-renommage.md) — socle : rollback à travers le renommage `gma→mag` (helper de re-ciblage des liens)~~ — **shipped #134** (2026-09-05) — helper `scripts/lib/cli-link.sh` prêt pour 0091/0092
- ~~[0091](done/0091-updater-rollback-ergonomique.md) — `mag revert` + message post-update + `--help` enrichi~~ — **shipped #135** (2026-09-05)
- ~~[0092](done/0092-bascule-gwsa-mag-path-refresh-terminal.md) — dépréciation douce `gwsa` + guide refresh terminal~~ — **shipped #136** (2026-09-05)
- [0028](0028-menage-des-versions-deployees.md) — ménage des versions déployées · **idée** — dépendance lâche (cible du revert de 0091)

## Notes

- **0108 est P1**, mais volontairement placée **après** la refonte admin (décision PO, 2026-09-03) :
  « on peut faire sans pour l'instant ».
- Avant tout build, 0108 exige un **changement de modèle** (franchir le verrou du compte ≠ recevoir
  le joker complet ; deux portes `api.py` + broker). Le grooming devra le cadrer d'abord.
