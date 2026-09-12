# Sprint — 0083 durcir passkey (anti-clonage sign_count, TOCTOU)
Périmètre: 1 feature, verrou partagé (réutilise 0084). Statut: en cours

## Backlog  (1 ligne = 1 feature = 1 PR)
- [x] feat(install): brancher les clients en opt-in (0087) — PR #123 mergée + shipped
- [x] fix(elicitation): verrou consume_nonce (0084) — PR #125 mergée + shipped
- [x] fix(remote_approval): verrou partagé anti-clonage sign_count (fiche 0083) — PR #126 mergée (dea8264) + shipped → done/ (353800c). ezk-reviewer GO ; CI verte ; Codex indisponible ce run (mergé sur ezk-reviewer GO + CI, choix humain).

## Definition of Done
- Extraction `file_lock` → module partagé ; `elicitation.py` l'importe (`consume_nonce` **inchangé**)
- Verrou sur les **3 writers** de `phone.json` : `close_remote_challenge`, `run_remote_approval_gate`,
  `enroll_phone` ; reload **frais sous le verrou** puis check + persist
- Test **multi-process** : 2 `gwsa --remote`, **2 défis frais**, états **clonés au même sign_count** ⇒
  1 seul réussit ; **+** interleaving enroll ↔ vérif
- `./scripts/test.sh` vert ; revue `ezk-reviewer` GO ; 1 PR squash conventional

## Notes / décisions  (ADR courts)
- Fiche **sœur de 0084** — réutilise le verrou `_file_lock` via **extraction** en module partagé.
- Sécu-critique (anti-clonage passkey) → implémentation déléguée à `ezk-tdd`, revue adverse obligatoire.
- **Piège de test** (Codex #115) : chaque `gwsa --remote` forge son **propre** défi → il faut 2 défis
  distincts + 2 signatures d'états clonés au même compteur, sinon on teste la liaison au défi, pas la course.
- Hors périmètre : canal push / relais aveugle + app mobile = épic 0077.
- Cibles vérifiées : `gateway/remote_approval.py` close_remote_challenge(158)/run_remote_approval_gate(349)/verify_assertion(309)/enroll_phone(195)/enrollment_path(53).
