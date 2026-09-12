---
id: 20260910170000000
title: Traduire en anglais les scripts helper opérationnels de mag + parité CLI/MCP
type: feature
priority: P2
product: google-mcp-multi-account
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-09-10
---

## En clair

La CLI `mag` parle anglais (fiche 0019). Mais `mag` shelle vers des **scripts et un backend**
qui affichent encore du français : la mise à jour, le déploiement, le bac à sable, le refus de
policy, et surtout les **messages d'exception** que les helpers d'approbation/élicitation
recopient tels quels. Résultat : selon la commande, `mag` mélange encore anglais et français.
Cette fiche finit le travail.

Origine : revue de la PR #140 (0019). Codex **et** le reviewer ont pointé, indépendamment,
que « les helpers invoqués par mag émettent encore du français ». Seul `iam-check.py` (message
autonome, 100 % traduit) est parti avec 0019. Le reste est déféré ici.

**Frontière retenue pour 0019 (leçon de la revue) :** un message ne part avec 0019 que s'il
est **entièrement anglais et autonome**. `remote-approval-cli.py` et `elicitation-cli.py` ont
été **exclus** de 0019 : traduire leur préfixe laissait le **contenu de l'exception** (construit
en français par `gateway/*.py`) en français — une sortie moitié-anglais/moitié-français, pire
que tout-français. Ils reviennent ici **avec leur source gateway**.

## Contexte / problème

`mag` invoque ces scripts, qui émettent des messages **utilisateur** encore en français :

- `scripts/remote-approval-cli.py` + `gateway/remote_approval.py` : le helper recopie le texte
  de `RemoteApprovalError` (~6 messages FR côté gateway, ex. « aucune passkey téléphone
  enrôlée »). **Traduire le helper ET la source gateway ensemble**, sinon sortie mixte.
- `scripts/elicitation-cli.py` + `gateway/elicitation.py` : idem, le helper recopie
  `ElicitationError` (~11 messages FR côté gateway). Helper + source ensemble.
- `scripts/update.sh` (~13 lignes de sortie FR) — `mag update`.
- `scripts/deploy-local.sh` (~15 lignes FR) — `mag dev deploy`.
- `scripts/sandbox.sh` (~30 lignes FR) — `mag dev …` (le plus gros).
- `scripts/policy-check.py` — le message de **refus de policy** (`mag : ✗ policy …`) affiché
  quand une opération est bloquée (chemin très visible), plus l'erreur « policy.json illisible ».

Ces scripts ont leurs **propres assertions de test** (ex. `test.sh` vérifie le texte de
l'avertissement de dépréciation dans `update.sh`) : les traduire impose de synchroniser ces
assertions, comme dans 0019.

**Question de conception à trancher (bloque une partie du scope) :**
- La valeur de log `"refus"`/`"ok"` (écrite par `policy-check.py`/`log-usage.py`) est **affichée
  dans l'admin**, qui est **en français assumé**. Faut-il angliciser cette valeur de log
  (et donc l'admin) ou la garder ? Tant que l'admin reste FR, garder `"refus"` est cohérent.
  → Le message de refus (texte CLI) peut passer en anglais **sans** toucher la valeur de log.

## Parité CLI/MCP (sous-lot)

- `gateway/profiles.py:22` (et voisins) : le backend MCP dit encore « mot réservé » là où la CLI
  dit « reserved word ». Même concept, deux canaux. À harmoniser pour la parité — mais c'est le
  **backend MCP**, pas la CLI : décider si la politique EN s'étend au canal MCP (adressé au client
  LLM, pas à un humain) ou reste CLI-only.

## Critères d'acceptation

- [ ] `remote-approval-cli.py` + `elicitation-cli.py` : sortie **entièrement** anglaise, préfixe
      ET message d'exception (donc `gateway/remote_approval.py` + `gateway/elicitation.py`
      traduits) ; assertion `test.sh` (rejeu remote-approval, ~5478) synchronisée.
- [ ] `mag update`, `mag dev deploy`, `mag dev <sandbox>` : sorties utilisateur en anglais ;
      assertions `test.sh` correspondantes synchronisées (rouge si retour au FR).
- [ ] Message de refus de policy (`mag : ✗ policy …`) en anglais ; la valeur de log `"refus"`
      traitée selon la décision de conception ci-dessus (garder si l'admin reste FR).
- [ ] Décision tranchée + documentée sur la parité MCP (`gateway/*`) : EN aussi, ou CLI-only.
- [ ] `./scripts/test.sh` vert.

## Comment vérifier

Lancer `mag update` (ou son dry-run), `mag dev deploy`, un refus de policy : les messages
s'affichent en anglais. Les tests de texte de ces scripts passent au vert.

## Hors scope

- Commentaires/docstrings du code (restent FR, choix interne — cf. 0019).
- L'interface admin (`admin/`), en français assumé (sauf si un écran devient public).
- Guides de test manuel `tests/manuels/*` (FR humain).
