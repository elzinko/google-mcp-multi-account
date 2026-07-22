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

**MàJ 2026-07-22 (revue backlog, puis vérification).** Les **trois points sont
résolus** — la fiche décrivait un état antérieur aux correctifs :
- **Point 1** (default-deny services) : **déjà implémenté** dès le commit d'origine
  `bfa2c32` (« add local MCP gateway **with default-deny policies** »). La revue
  l'avait re-signalé comme « décision vive » sur la foi de cette fiche périmée ;
  vérification faite, un service non déclaré est bien refusé (lecture comprise).
  Ce build **verrouille le comportement par des tests** sur toute la classe
  (chat/meet/people/slides/forms).
- **Point 2** : résolu (policy prudente écrite par défaut à `gwsa add`).
- **Point 3** : chemins absolus faits ; falsifiabilité de l'état des verrous →
  fiche 0001.

→ Fiche **close** : plus de décision ouverte, comportement conforme au choix
« default-deny complet » du PO (2026-07-22).

## Décisions (historique — toutes tranchées)

1. ~~**Service non modélisé = libre (allow-by-default sur la dimension service).**~~
   **RÉSOLU — était déjà default-deny.** `policy-check.py` (`main`) : `svc_pol =
   pol.get(service)` ; si le service n'est pas un dict déclaré (et hors passthrough
   `auth`/`schema`), la commande est **refusée** (`chat`, `meet`, `people`, `slides`,
   `forms`, `script`… — lecture comprise). L'inquiétude « silencieusement libres » de
   l'audit ne s'applique pas au code livré. Couverture de test ajoutée sur toute la
   classe (2026-07-22). *Reste, purement ergonomique : l'UI admin ne modélise que 7
   services — donc pas moyen d'AUTORISER `chat` si on le voulait ; enhancement, pas un
   trou de sécurité (le défaut est déjà « refusé »).*

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
