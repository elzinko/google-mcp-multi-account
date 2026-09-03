# PLAN — google-multi-account

> **Séquence décidée** (curée, arbitrage PO) — *quoi groomer/tirer ensuite, et dans quel ordre*.
> Ce n'est **pas** l'index : l'index trié par priorité est [BACKLOG.md](BACKLOG.md), et le gate
> technique de tirage reste `ready`. Décidé le **2026-09-03**.

## NOW — la refonte admin d'abord, l'accès fin par session ensuite

**Jalon A — Refonte admin (épic [0060](0060-admin-ux-ui-refresh.md)).** La série Cockpit, en cours.

- [0094](0094-sessions-page-dediee-reactive.md) — Sessions en page dédiée réactive · **build** *(in-progress)*
- [0107](0107-vue-compte-droits-sur-place.md) — Vue compte : droits sur place, au grain par opération · **build** *(ready)*
- reste de l'épic (0095–0104, 0106) · **à groomer** puis ordonner

**Jalon B — Accès fin par session — APRÈS le jalon A.**

- [0108](0108-session-demande-sous-ensemble-droits-compte.md) — une session demande son sous-ensemble de droits du compte · **groom** puis build

## Notes

- **0108 est P1**, mais volontairement placée **après** la refonte admin (décision PO, 2026-09-03) :
  « on peut faire sans pour l'instant ».
- Avant tout build, 0108 exige un **changement de modèle** (franchir le verrou du compte ≠ recevoir
  le joker complet ; deux portes `api.py` + broker). Le grooming devra le cadrer d'abord.
