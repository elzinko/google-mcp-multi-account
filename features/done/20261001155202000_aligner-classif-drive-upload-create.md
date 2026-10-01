---
id: "20261001155202000"
title: Classification « drive files upload » — aligner policy-check sur create, comme le gate et l'audit
type: bug
priority: P3
product: google-multi-account
version:
epic:
status: shipped
ready: 2026-10-01
pr: "#159"
created: 2026-10-01
---

## En clair

Un même appel Drive est rangé dans **deux cases différentes** selon qui le regarde.
Un `drive files upload` est vu comme une **création** par trois composants
(`categorize`, le gate transactionnel, l'audit) mais comme une **modification** par le
vérificateur d'accès `policy-check`. Même classe de bug que la PR #157 (le jumeau
corbeille) et que la PR #156 (Gmail) : quand la classification diffère d'un côté à
l'autre, un acte peut être autorisé ou signé de travers.

**Latent aujourd'hui** — plus encore que #157. La méthode `upload` **n'existe pas** comme
sous-commande gws : un upload réel passe par `drive files create --upload <média>`
(méthode `create`), et le tool MCP `drive_upload` construit bien `create`. Le mot
« upload » n'apparaît que comme **drapeau** `--upload`. Pour atteindre ce bug, il
faudrait qu'un futur tool émette littéralement la méthode `upload` — une faute de code,
pas un usage. On ferme quand même l'incohérence, par prudence et pour la cohérence de la
famille #156 / #157.

Le correctif ne change **aucun comportement réel** : aucun appel émis ne porte la méthode
`upload`, donc aucun verdict existant ne bouge. On aligne seulement la classification
théorique sur la source de vérité partagée (`gateway.categorize`, où `upload ∈
CREATE_METHODS`).

## Contexte / problème

`gateway/categorize.py` est la **source de vérité** du triplet service × opération ×
ressource. Elle place `upload` dans `CREATE_METHODS`. Donc trois composants qui en
dérivent classent `drive files upload` en **create** :

- le gate transactionnel `gateway/api.py::_classify_operation` (catégorie signée, Zone 1) ;
- l'audit `gateway/usage.py::infer_call` (triplet journalisé) ;
- `categorize("drive", ["files"], "upload")` lui-même.

Mais `scripts/policy-check.py` **ré-implémente** la classification des méthodes
`drive files` à la main, par deux tables `if/elif` dupliquées — dans `check_drive`
(policy du compte) et dans `_gate_drive_session` (intersection des capacités de session).
Les deux rangent `upload` dans la branche `("update", "patch", "modify", "untrash",
"upload")` → **update**. L'override `drive_files_trash_override` n'y change rien :
`upload ∉ UPDATE_METHODS`, donc l'override ne le voit pas non plus.

Le désaccord, pour un `drive files upload` :

```
        drive files upload   (un upload CRÉE un fichier)
                  │
  categorize ─────┼────►  create      (upload ∈ CREATE_METHODS)
  gate        ────┼────►  create
  audit       ────┼────►  create
  policy-check ───┼────►  update      ← le seul désaccord
```

Pourquoi ça compterait si c'était atteignable : `create` et `update` suivent des
**chemins de vérification de zone différents** dans `check_drive`. `create` lit les
`parents` dans le corps (`--json`) et vérifie que le dossier de destination est en zone.
`update` lit un `fileId` dans `--params`. Un vrai upload a des `parents` (pas de
`fileId`) : classé « update », il serait soit refusé à tort (« no fileId »), soit — si un
`fileId` leurre était glissé dans `--params` — validé contre le mauvais identifiant
pendant que l'API écrit ailleurs. Classé « create », il est vérifié sur le bon chemin.

## Correctif

Aligner `policy-check` sur `categorize` pour la seule méthode `upload`, sans toucher aux
autres méthodes ni au chemin de lecture.

1. Extraire une fonction pure `_drive_files_category(method)` dans
   `scripts/policy-check.py`. Elle encode **exactement** la table d'écriture actuelle
   (`create`/`update`/`delete`, `None` sinon), avec `upload` rangé en **create**. Elle n'a
   **pas** de branche `read` : une méthode de lecture non filtrée en amont ou une méthode
   inconnue reste « non classifiable » (refus par prudence) — comportement inchangé. Ce
   choix évite de dériver de `categorize()` directement, ce qui aurait classé `read` des
   méthodes comme `drive files search` (absentes de `DRIVE_READ_FILES`) et **desserré** la
   policy.
2. `check_drive` et `_gate_drive_session` appellent cette fonction au lieu de leurs deux
   tables dupliquées. Même repli qu'avant : `check_drive` refuse sur `None`,
   `_gate_drive_session` replie sur `update`. `drive_files_trash_override` reste appliqué
   là où il l'était.

`gateway/categorize.py` n'est **pas** modifié : `upload` y est déjà `create`. On ne fait
que conformer `policy-check` à cette source.

## Critères d'acceptation

- [ ] `drive files upload` classé **create** par les trois : `_classify_operation(...)[4]`,
      `infer_call(...)[1]`, et la classif de `policy-check` (`_drive_files_category("upload")`).
- [ ] Non-régression : `create`/`copy`, `update`/`patch`/`modify`/`untrash`,
      `delete`/`trash`/`batchdelete` gardent leur catégorie, identique entre `policy-check`
      et `categorize`.
- [ ] Pas de desserrage : une méthode de lecture `drive files` hors `DRIVE_READ_FILES`
      (ex. `search`) reste refusée, pas reclassée `read`.
- [ ] Les deux points de classif de `policy-check` (`check_drive`, `_gate_drive_session`)
      dérivent d'**une seule** source (`_drive_files_category`), plus de table dupliquée.
- [ ] Gate hermétique verte (`./scripts/test.sh`).

## Comment vérifier

Avant le correctif, les trois ne s'accordent pas (policy-check dit « update ») ; après, si :

```bash
./scripts/test.sh    # section « classif drive files upload » verte
```

Preuve runtime directe (depuis la racine du repo) :

```bash
python3 - <<'PY'
import importlib.util, sys
import gateway.api as api
from gateway.usage import infer_call
spec = importlib.util.spec_from_file_location("pc", "scripts/policy-check.py")
pc = importlib.util.module_from_spec(spec); sys.argv = ["pc"]; spec.loader.exec_module(pc)
args = ["drive", "files", "upload", "--json", '{"parents":["z"]}']
print("gate  :", api._classify_operation(args)[4])   # create
print("audit :", infer_call(args)[1])                 # create
print("policy:", pc._drive_files_category("upload"))  # create
PY
```

## Notes

- Lignée directe :
  - [0037](0037-semantique-suppression-en-zone.md) — classer un acte Drive d'après le
    **corps**, pas le seul nom de méthode (Option A, corbeille = delete).
  - [0086](0086-raffinements-audit-migration-capacites-session.md) — aligner la
    catégorie entre **autorisation** et **audit** (le triplet journalisé doit nommer la
    capacité qui a réellement autorisé).
  - PR #157 (fiche `20261001121405000`) — jumeau corbeille : câbler
    `drive_files_trash_override` au gate. Même classe de bug, fonction voisine.
- Repéré en **revue adverse de la PR #157**. Préexistant, hors scope de #157 (qui corrigeait
  le cas corbeille), donc traité ici en fiche + PR séparées.
- `upload` reste volontairement dans `CREATE_METHODS` (`gateway/categorize.py`) : c'est la
  bonne catégorie (un upload crée un fichier) et la source que `policy-check` doit suivre.
