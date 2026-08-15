# ADR-0007 — Droits par session : identité par consentement, jeton porté, consentement multi-hôte (fiche 0076)

**Date** : 2026-08-15  
**Statut** : proposé (Phase A visée par la fiche 0076 ; Phases B/C esquissées → fiches 0077/0078 à venir)  
**Décideurs** : Thomas (mainteneur)

> **TL;DR** — Chaque conversation obtient un périmètre Google **qui lui est propre** : décidé par un **geste de consentement humain signé** (élicitation ADR-0005 **exigée** ; pas déduit de la connexion MCP), **transporté dans chaque appel** (pas dans un état global du serveur), **configurable au grain le plus fin** (service × opération × ressource), et **validable depuis l'appareil où se trouve l'humain** (Touch ID desktop ou biométrie Android, y compris à distance). Résultat : deux sessions du même compte peuvent avoir des droits différents, et aucune n'hérite passivement d'une autre. *L'outil vérifie, l'humain autorise, le LLM propose.*

## Contexte

La fiche 0045 a posé l'intention (« chaque session repart de zéro, droits propres, isolés »). La Phase A a été plombée dans le code (`gateway/sessions.py`, registre `.sessions/`, `gma session …`), mais l'observation du poste montre qu'elle est **branchée à vide** :

- **Le grain est la connexion MCP, pas la conversation.** Le `session_id` est frappé à l'`initialize` et posé dans un **global de process** (`gateway/context.py:set_session_id`). Or Claude Desktop partage **une** connexion MCP entre toutes ses conversations → un seul `session_id` pour tout le monde.
- **Les droits sont grossiers** : `unlock` au niveau compte + zones Drive. Pas de différenciation service / opération / ressource.
- **Deux bugs constatés** (7 sessions lues sur le poste, 14/08) : `last_seen_at == created_at` partout (le `touch()` d'activité ne se déclenche pas → TTL-par-inactivité mort) et les sessions **s'accumulent sans purge** (le `close_session` de fin de connexion ne nettoie pas).

Forces en présence :

- Le **protocole MCP ne transmet pas** d'identifiant de conversation ; on ne peut pas compter dessus.
- Tout est **100 % local** ; le modèle reste **coopératif** tant que le vault (fiche 0003) n'isole pas les credentials.
- L'**élicitation signée** existe déjà côté desktop (fiche 0001 / ADR-0005 : payload canonique + ECDSA P-256, anti-rejeu par nonce). On réutilise, on n'invente pas.
- Cible produit élargie : valider **là où est l'humain** (desktop **ou** Android), le desktop pouvant être éteint.

## Décision

1. **Identité par consentement, pas par connexion.** Une session naît d'un **geste humain** (« ouvrir l'accès pour ce chat ») qui émet un **jeton de session signé** (réutilise ADR-0005). **La création de session emprunte toujours le chemin d'élicitation signée, indépendamment du flag `.strong-auth` global** — pas de session sans geste signé (enrôlement requis). **Chaque capacité (unlock, grant fin) — à la création comme à l'élargissement — est portée par un consentement signé liant le scope exact (compte / service / opération / ressource) ; aucun élargissement non signé.** Les **sous-sessions déléguées** (`parent_session_id`) héritent d'un sous-ensemble **déjà signé** du parent — sans nouvelle signature — et **ne peuvent pas élargir** (pas d'`access_request` enfant ; révocation en cascade), conformément à la fiche 0045. Le jeton n'est plus dérivé de l'`initialize`.
2. **Jeton porté dans chaque appel.** Les tools MCP acceptent un paramètre de session ; le broker autorise d'après le **jeton présenté**, jamais d'après un global de process. *C'est ce qui isole deux conversations sur une connexion Desktop partagée.* On abandonne `set_session_id` global.
3. **Configuration de droits au grain fin.** Le registre de session devient un **document de capacités** : par (compte, **service × opération × ressource**), avec expiry. Droits effectifs = **policy compte ∩ manifeste projet ∩ capacités session** (intersection, *fail-closed*).
4. **Consentement multi-hôte, routable.** Le broker + credentials vivent sur l'**hôte allumé** (desktop par défaut, Android sinon). La validation biométrique se fait **où est l'humain** : Touch ID desktop **ou** biométrie Android — y compris **à distance** (le broker desktop demande une approbation signée au téléphone **appairé**). Clés en **Secure Enclave / Android Keystore**, dispositifs appairés.
5. **Cycle de vie & observabilité.** Le cycle de vie d'une session est **découplé de la connexion MCP** : expiration **TTL** + **révocation explicite** (`gma session close` / `revoke`). Sur une connexion *partagée* (Desktop), la fin de connexion ne purge un jeton que si **plus aucune conversation ne le détient** — jamais ceux des autres. `gma session list` + **vue de la config par session** ; journal enrichi (`session_id`, service / opération / ressource) ; `last_seen` avance à chaque appel.
6. **Phasage.** **A — desktop** (fiche 0076, cette PR) : geste local + jeton porté + config fine + `session list` + fix bugs. **B — consentement distant** (0077) : appairage desktop↔Android + approbation signée poussée. **C — hôte Android** (0078) : broker + credentials sur l'APK, **conditionné au vault** (0003).

## Options considérées

**Naissance de l'identité**

| Option | Complexité | Portabilité clients | Sécurité | Verdict |
|---|---|---|---|---|
| **Geste de consentement signé** | moyenne | toutes topologies | forte (signé, humain) | **retenu** |
| Id de conversation transmis par le client | faible | dépend du client (Desktop ne l'émet pas) | moyenne | rejeté — non garanti, non portable |
| Par connexion MCP (actuel) | déjà fait | KO sur Desktop partagé | faible | rejeté — n'isole pas les conversations |

**Transport du droit** : *jeton porté dans l'appel* (**retenu**) vs *global de process* (actuel — cassé dès qu'une connexion est partagée).

**Granularité** : *service × opération × ressource* (**retenu** — « chaque session sa config ») vs *service entier* (trop grossier) vs *compte* (actuel).

**Cas desktop éteint** : *broker sur Android, credentials locaux au téléphone* (**retenu, phase C**) vs *credentials côté cloud* (rejeté — casse le 100 % local et la posture « sécurisé au max »).

## Conséquences

**Plus facile** : deux sessions du même compte avec des droits distincts ; nouvelle conversation = zéro droit ; révocation par session ; audit par session ; extension mobile cadrée.

**Plus dur** : le geste de consentement ajoute une friction (assumée ; **enrôlement Touch ID requis pour ouvrir toute session**) ; le jeton porté impose un **paramètre de session sur les tools** et que le modèle le présente (à instruire côté skill / prompt) ; le consentement distant est un **protocole d'appairage** coûteux (phase B) ; l'hôte Android **double la surface credentials** (phase C) — à ne faire **qu'avec** le vault (0003).

**À revisiter** : le jeton est une **capacité au porteur** → le borner (expiry court, scope minimal, non affiché entre conversations) ; tout reste **coopératif** tant que le vault n'est pas là (contournements `gws` nu / édition FS, S-01…S-03 de 0045) ; si un client finit par exposer un vrai id de conversation, on pourra l'utiliser comme **raccourci** du geste.

## Repli (fail-closed) & limites

- Jeton absent / invalide / expiré → **refus** (jamais d'accès par défaut).
- **Création de session sans enrôlement** de la clé d'élicitation, ou **biométrie indisponible** → **refus** (`gma elicitation enroll`) — *pas de session sans geste signé*, indépendamment du flag `.strong-auth`.
- **Fin de connexion MCP** : ne purge **pas** les jetons encore détenus par d'autres conversations de la même connexion (cf. Décision 5).
- Service / opération / ressource non déclarés dans la config de session → **refus** (default-deny, intersection).
- **Élargissement de scope sans consentement signé** → **refus** : le broker n'accorde une capacité que si elle est couverte par un **payload signé** (compte / service / opération / ressource), indépendamment de `.strong-auth`. Le modèle ne peut pas s'auto-élargir jusqu'aux plafonds compte / projet.
- Consentement distant (phase B) : refus si non appairé, signature non vérifiée, ou requête non liée à l'action exacte (nonce + expiry + device pinning).
- Limite de menace **inchangée** : sans vault (0003), un agent avec shell peut contourner (édition `.sessions/`, `gws` nu). La couche session **durcit le modèle coopératif**, elle ne le rend pas cryptographiquement étanche.

## Action items

1. [ ] **Phase A** — paramètre `session` sur les tools + autorisation broker par jeton ; registre de capacités (service × op × ressource) **signées à chaque octroi** ; `gma session list` + vue config ; fix purge + `last_seen` ; **héritage sous-agent ⊆ parent + révocation cascade (0045) testés** ; tests hermétiques verts.
2. [ ] Test **live Desktop** (2 conversations → nombre de `session_id`) pour documenter, même si la décision 2 le rend non-bloquant.
3. [ ] **Phase B** (0077) — appairage desktop↔Android + approbation signée distante (étend ADR-0005).
4. [ ] **Phase C** (0078) — broker + credentials Android (APK), **conditionné au vault** (0003).

## Références

- Fiches : [0045](../../features/0045-capacites-projet-signees.md), [0076](../../features/0076-droits-par-session-phase-a.md), [0001](../../features/0001-elicitation-signee-strongauth-v2.md), [0003](../../features/0003-vault-credentials-hors-perimetre-agent.md)
- ADR : [ADR-0005](ADR-0005-elicitation-signee-v2.md) (élicitation signée réutilisée)
- Code : `gateway/sessions.py`, `gateway/context.py`, `gateway/broker_server.py`, `gateway/mcp_server.py`
- Menace : `docs/threat-model.md`, `SECURITY.md`
