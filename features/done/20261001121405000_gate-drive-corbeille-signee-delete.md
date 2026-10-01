---
id: "20261001121405000"
title: Gate transactionnel Drive — signer la corbeille (trashed:true) en « delete », comme policy-check
type: bug
priority: P2
product: google-multi-account
version:
epic:
status: shipped
ready: 2026-10-01
pr: "#157"
created: 2026-10-01
---

## En clair

Le point de contrôle qui fait signer un acte Drive (Touch ID) pouvait le signer avec la
**mauvaise étiquette**. Une mise à la corbeille (`drive files update {"trashed": true}`) était
signée « update », alors que le vérificateur d'accès (policy-check) la lit comme « delete ».
Résultat possible : un acte **approuvé par l'humain ET autorisé par la policy** aurait été
**refusé** au dernier moment, parce que le droit porté ne correspondait pas au droit exigé.

C'est le **jumeau Drive** du correctif Gmail de la PR #156. Même classe de bug, même fonction,
deux lignes voisines. Empilée sur #156 (la ligne Gmail y vit).

**Latent aujourd'hui** : aucun tool MCP curaté n'émet `trashed:true` (pas d'outil de corbeille ;
`drive.delete` vaut `false` par défaut). Le gate ne voit donc jamais ce cas par la surface MCP.
On ferme quand même l'incohérence : c'est un piège si un futur tool l'émet.

## Contexte / problème

Le consentement transactionnel (ADR-0011/0012) classe chaque appel pour construire la
**capacité signée** portée jusqu'au broker (Zone 1). Cette classification vit dans
`gateway/api.py::_classify_operation`, appelée par `_transactional_gate`.

Depuis #156, `_classify_operation` appelle `categorize()` **puis** `gmail_labels_override(...)` —
pour qu'un `gmail messages modify` touchant un libellé système soit signé comme le voit
policy-check. Mais elle **n'appliquait pas** `drive_files_trash_override(...)`.

Or `scripts/policy-check.py::check_drive` **et** `gateway/usage.py::infer_call` appliquent, eux,
`drive_files_trash_override` : un `drive files update {"trashed": true}` y devient « delete »
(Option A, fiche [[0037]] ; alignement audit ↔ autorisation, fiche 0080).

Le désaccord :

```
          corps {"trashed": true}
                  │
   gate  ─────────┼─────────►  cap signé { drive, update }   ← FAUX
   policy-check ──┼─────────►  exige      { drive, delete }
                  │
         broker : update ⊄ delete  →  _session_drive_ok = False  →  REFUS
```

L'acte a pourtant été approuvé (Touch ID) et il est autorisé (`delete:true`). Il serait quand
même refusé. Le gate et le vérificateur **doivent s'accorder**.

## Correctif

Dans `_classify_operation`, appeler `drive_files_trash_override(resources, raw_method, category,
gws_args)` **juste après** la ligne `gmail_labels_override`. La fonction existe déjà
(`gateway/categorize.py`, source de vérité partagée) ; il manquait son câblage au gate.

## Critères d'acceptation

- [x] `_classify_operation(["drive","files","update","--json",'{"trashed":true}'])[4] == "delete"`.
- [x] `{"trashed":false}` (restauration) reste « update ».
- [x] Même reclassement via `--params` et pour la méthode `patch`.
- [x] Aucun test transactionnel Drive existant n'attendait « update » pour un trash.
- [x] Gate hermétique verte (`./scripts/test.sh`).

## Comment vérifier

```bash
./scripts/test.sh   # section « Gateway — drive corbeille : gate … accordé avec policy-check »
```

La section asserte les cinq cas ci-dessus. Gate complète au vert : 651 réussis, 0 échoués.
