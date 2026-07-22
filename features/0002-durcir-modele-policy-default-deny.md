---
id: 0002
title: Durcir le modèle de policy — décisions « default-deny » soulevées par l'audit
type: feature
priority: P2
version:
epic:
status: idea
ready:
pr:
created: 2026-07-20
---

## Contexte / Problème

Audit adversarial du contrôleur de policy le 2026-07-20 (4 attaquants + réfutation).
Les **bugs** exploitables trouvés ont été corrigés et couverts par des tests le jour même
(préfixe de version `gmail:v1`, positionnel piège après flag inconnu, parents lus depuis
`--params`, `removeParents` non contrôlé, fail-open sur `policy.json` corrompu). Restent
**trois décisions de conception** — pas des bugs, des choix de modèle — laissées ouvertes
parce qu'elles changent le comportement et l'UX, à trancher par l'utilisateur.

**MàJ 2026-07-22 (revue backlog).** Le **point 2 est résolu** (policy prudente
écrite par défaut à `gwsa add`), le **point 3 partiellement** (chemins absolus ;
le reste → fiche 0001). La **décision vive restante = le point 1** : default-deny
sur les services non modélisés. Priorité relevée **P3 → P2** — c'est un trou du
modèle de sécurité, cœur de la proposition de valeur du projet.

## Décisions à trancher

1. **Service non modélisé = libre (allow-by-default sur la dimension service).**
   `policy-check.py` : `svc_pol = pol.get(service)` ; si le service n'a pas de clé dans
   `policy.json`, la commande passe **sans aucun contrôle**. Voulu pour docs/sheets/tasks
   (peu risqués). Mais l'interface d'admin ne modélise que 7 services (drive, gmail,
   calendar, keep, docs, sheets, tasks) ; or `gws` en expose ~19. Conséquence : `chat`
   (envoi de message), `meet`, `people`, `script`, `slides`, `forms`, `workflow`,
   `classroom`, `admin-reports` sont **impossibles à restreindre** et **silencieusement
   libres** — y compris des actions visibles de l'extérieur (chat send), ce que la règle 3
   de CLAUDE.md veut justement encadrer. Vérifié : avec une policy prudente,
   `gwsa <alias> chat spaces messages create --json '{"text":"hi"}'` → autorisé.
   → Basculer en **default-deny** (tout service non déclaré « libre » refuse au moins les
   écritures), ou a minima faire échouer-fermé les services à effet externe ? Impact : UI
   admin à étendre, mental model « allowlist de restrictions » → « denylist par défaut ».

2. ~~**Aucun `policy.json` = tout ouvert.**~~ **RÉSOLU (2026-07-22).** `cmd_add` écrit
   désormais une policy prudente par défaut à la création (`gateway/default_policy.py` →
   `write_default_policy` : Drive `zonesOnly`, Gmail sans envoi, docs/sheets/tasks lecture
   seule). Un profil frais est restreint d'emblée. *Reste, comme fail-open résiduel : si le
   `policy.json` est absent (supprimé à la main), `bin/gwsa` retombe en « tout ouvert » —
   c'est la même racine que le point 1 (défaut permissif) ; à traiter avec lui.*

3. ~~**`gwsa strongauth` : le cérémonial Touch ID s'appuie sur des éléments éditables par
   l'agent.**~~ **PARTIELLEMENT TRAITÉ le 2026-07-20.** `require_strong_auth` shellait vers
   `swift` **résolu dans le PATH**, et — plus grave — `bin/gwsa` lançait le **contrôleur de
   policy** via `python3` du PATH : un faux `python3` renvoyant 0 **désactivait toute la
   policy** (démontré : la commande d'envoi atteignait `gws` malgré `send:false`). Corrigé :
   `SYS_PYTHON=/usr/bin/python3` et `SYS_SWIFT=/usr/bin/swift` en chemins absolus, non
   surchargeables par variable d'environnement (une telle porte rouvrirait le trou) ;
   `/usr/bin` est protégé par SIP, donc hors d'atteinte sans root. Vérifié avant/après.

   **Reste ouvert sur ce point** : l'**état** du verrou et des grants vit toujours dans de
   simples fichiers (`.locked`, `.unlock-until`, `session-grants.json`) éditables par un
   agent ayant le shell. La vraie réponse (signature liée à la question, état non falsifiable)
   est la fiche **0001**. À noter aussi (audit §2) : `touchid.swift` utilise
   `.deviceOwnerAuthentication`, qui accepte le **mot de passe de session** en secours — si
   l'exigence est « présence physique », préférer `.deviceOwnerAuthenticationWithBiometrics`.

## Note transverse — la seule garantie dure est hors wrapper

Les trois points, plus le contournement par `gws` nu (limite déjà documentée), pointent le
même mur : **`gwsa` est un garde-fou côté client, dans le périmètre de l'agent.** Un agent
avec shell peut toujours `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=… gws …` et tout contourner
(policy, verrou, journal). Le wrapper hausse le coût et trace l'usage coopératif — il ne
contraint pas un agent adverse déterminé. La seule garantie dure serait de déplacer
l'enforcement **hors du périmètre de l'agent** (broker/proxy de tokens appliquant la policy
côté serveur, l'agent ne recevant jamais les identifiants). Gros morceau — à ne poser que si
le besoin réel émerge (cf. déclencheurs de la fiche 0001).

## Critères d'acceptation

*(à définir au grooming, une fois la/les décision(s) prise(s) ci-dessus)*

## Notes

- Bugs déjà corrigés (référence, ne pas rouvrir) : commit/segment du 2026-07-20,
  `scripts/policy-check.py` + `scripts/test.sh` (section « Bypass corrigés »).
- Trous de couverture comblés le même jour : emptyTrash, move addParents/removeParents,
  partage Calendar (acl), Gmail labels/update, bornes de `gwsa grant`, path-traversal alias.
- Idées de couverture encore ouvertes (audit §2) : test transitif « sous-dossiers compris »
  de `under_allowed` (récursion + anti-cycle + profondeur, via un stub `gws` en PATH) ;
  test que tout accès AUTORISÉ produit bien une ligne dans `usage.jsonl` (la journalisation
  est la propriété la moins testée) ; contrat d'exit-code de `touchid.swift` (0/1/2 → fail
  closed) ; choix `.deviceOwnerAuthentication` (accepte le mot de passe) vs
  `.deviceOwnerAuthenticationWithBiometrics` (biométrie stricte).
