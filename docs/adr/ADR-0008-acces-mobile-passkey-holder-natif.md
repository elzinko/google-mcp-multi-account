# ADR-0008 : Accès mobile — approbation par passkey, détention par un « holder » natif souverain

**Statut :** Accepté
**Date :** 2026-08-14 (accepté le 2026-08-15)
**Décideurs :** Thomas (PO)
**Note :** renuméroté depuis ADR-0007 le 2026-08-15 — le n° 0007 était pris par l'ADR « droits par session » (PR #108), sujet distinct.

> **TL;DR** — Pour accéder à ses comptes Google depuis un téléphone — **y compris quand le Mac est éteint** — sans jamais confier ses jetons d'accès à un service tiers, on sépare trois rôles : **qui demande** une action (l'assistant IA, où qu'il tourne), **qui l'approuve** (toujours le téléphone, par une empreinte qui **signe** l'action précise via une *passkey* — le standard supporté sur macOS/Windows/Linux/Android/iOS), et **qui détient** réellement les accès (un composant « holder » natif qui **scelle les jetons dans le coffre matériel** de l'appareil — Secure Enclave, StrongBox — clé non exportable). Faute d'un serveur allumé en permanence, c'est le **téléphone lui-même** qui devient ce holder, **à la demande** (rien ne tourne en fond). Le projet est repensé dès maintenant comme un **logiciel libre**, ce qui interdit tout point de contrôle centralisé : le seul relais éventuel est **aveugle** (il ne voit que des signatures, jamais un jeton) et **auto-hébergeable**.

## Contexte

Aujourd'hui, tout le système est **local à un Mac** :

- Le serveur MCP est **stdio** (`gateway/mcp_server.py`) : lancé en process enfant par le client LLM, sur la même machine. Aucun écouteur réseau.
- Les jetons vivent dans un **vault chiffré local** (`GWSA_ROOT/.vault/<alias>/credentials.enc`), servis par un **broker loopback** `127.0.0.1:4878`.
- L'approbation d'une action sensible (unlock, grant, add) passe par l'**admin web `127.0.0.1:4877`** — qui n'a **aucune authentification applicative** : elle fait confiance à la session macOS. Être physiquement devant le Mac déverrouillé **est** l'autorisation (autorité *ambiante*).
- Sous `strongauth`, le consentement est **signé** (Touch ID → ECDSA P-256, Secure Enclave du Mac, nonce anti-rejeu, reçu vérifiable) — cf. [ADR-0005](ADR-0005-elicitation-signee-v2.md).

Le besoin nouveau (session 2026-08-13) : **utiliser ces comptes depuis un mobile**, dans des contextes où l'agent tourne ailleurs que sur le Mac (Claude Code remote, discussion Claude, cowork, environnement cloud Anthropic), **avec le Mac allumé ou éteint**, et **sans appareil personnel allumé en permanence**.

Trois forces s'opposent :

1. **L'ADN du projet** : 100 % local, jetons jamais confiés à un tiers, audit et verrou par service (default-deny).
2. **La réalité mobile** : le mobile n'a pas de « session macOS » à qui faire confiance ; l'autorité ambiante n'existe pas ; un agent *cloud* doit être supposé **potentiellement hostile**.
3. **L'absence de serveur** : sans machine allumée H24, il n'y a pas de « backend » qui survit à l'extinction du Mac — **sauf le téléphone**, seul appareil personnel toujours avec soi et allumé.

## Décision

Adopter un modèle à **trois rôles découplés**, et refonder la brique de détention/approbation autour de standards cross-plateforme.

1. **Trois rôles.**
   - **Requester** — l'agent LLM qui *demande* une action. N'importe où (local, remote, cloud). **Jamais digne de confiance** par construction.
   - **Approver** — **le téléphone**, toujours. Il *approuve* en **signant** la description exacte de l'action avec une **passkey** (WebAuthn/FIDO2), gardée par biométrie (Face ID / Touch ID / Hello / biométrie Android).
   - **Holder** — le composant qui *détient* les jetons et *exécute* les appels Google. Il n'agit que sur présentation d'une **approbation signée valide**.

2. **L'approbation devient une signature de passkey** — généralisation de l'[ADR-0005](ADR-0005-elicitation-signee-v2.md). Le signataire **migre** de la Secure Enclave du Mac vers la **passkey du téléphone**. Une seule API standard remplace le helper Swift macOS-only, et couvre les 5 OS.

3. **WYSIWYS — « on signe ce qu'on voit ».** Le téléphone **affiche l'action précise avant de signer** (« Autoriser Drive · compte perso · dossier *X* · 2 h ? »). Le challenge signé lie le consentement à cette action (compte, cible, durée, `nonce`, `expires_at`). Un requester cloud compromis **ne peut pas** faire signer autre chose que ce que l'humain voit.

4. **Sécurité au repos maximale : holder natif, jetons scellés dans le coffre matériel.** Les jetons sont chiffrés par une clé **non exportable** logée dans le coffre matériel de l'appareil (Secure Enclave iOS/macOS, StrongBox/Keystore Android, TPM), déscellée uniquement après biométrie. On abandonne la voie « navigateur » (PWA) : le curseur du PO est la **sécurité au repos**, pas la vitesse de mise en œuvre.

5. **Sans serveur H24 : le téléphone est le holder quand le Mac est éteint** — en **holder éphémère à la demande**. Pas de démon : on ouvre l'app → biométrie → déscellement → appel Google → oubli. Le Mac reste un holder possible **quand il est allumé** (l'existant continue de servir).

6. **Techno retenue : Tauri 2 (cœur Rust, UI web embarquée)** pour le holder/approbateur natif — couvre les 5 OS, petit binaire auditable, accès natif aux coffres matériels, surface d'attaque réduite. *Flutter* est l'alternative documentée (cf. Options).

7. **Logiciel libre, donc zéro point de contrôle centralisé.** Le seul relais éventuel (pour joindre un holder derrière un NAT depuis un agent cloud) est **aveugle** — il ne transporte que des messages **signés et opaques**, jamais un jeton Google — et **auto-hébergeable**. Chaque utilisateur fournit **son propre client OAuth** (déjà le cas via le provisioning GCP). Aucun secret partagé n'entre dans le dépôt.

8. **Décisions complémentaires (actées le 2026-08-15 avec le PO).**
   - **Enrôlement OAuth par appareil** : chaque appareil (Mac, téléphone) détient ses propres jetons dans son coffre — **pas** de synchronisation de secrets entre appareils.
   - **Migration progressive, pas de big-bang** : le holder **Python-macOS** existant est **conservé** et continue de servir ; le holder natif est ajouté **à côté**. L'unification éventuelle du desktop sur Tauri 2 est **différée** (non décidée).
   - **Licence : Apache-2.0** (clause brevets + adoption large).
   - **Point de départ = phase 1** : poser l'approbation par passkey sur l'architecture *actuelle* (Mac holder allumé) avant toute refonte native.

## Options considérées

### Axe 1 — Où vit le holder (détention des jetons + exécution) ?

#### Option 1A — Statu quo : le Mac, seul holder
| Dimension | Évaluation |
|---|---|
| « Mac éteint » | ❌ aucun accès |
| Souveraineté | ✅✅ maximale (rien ne change) |
| Coût | 🟢 nul |

**Rejetée** : ne répond pas à l'exigence « Mac allumé *ou éteint* ».

#### Option 1B — Un appareil personnel allumé en permanence (Pi, NAS, Mac mini)
| Dimension | Évaluation |
|---|---|
| « Mac éteint » | ✅ le serveur tient |
| Souveraineté | ✅ (machine à soi) |
| Coût | 🟠 un serveur à administrer + transport entrant + biométrie déportée |

**Rejetée** : le PO **n'a pas** et ne veut pas d'appareil allumé en permanence.

#### Option 1C — Un holder dans le cloud (Anthropic ou tiers)
| Dimension | Évaluation |
|---|---|
| « Mac éteint » | ✅ |
| Souveraineté | ❌ jetons Google confiés à un tiers, en clair au moment de l'usage |
| Coût | 🟢 léger |

**Rejetée** : trahit l'ADN du projet. « Pas de MCP du tout » (connecteur Google générique) est un cas dégradé de celle-ci — il perd multi-comptes, policy, verrou et audit, c'est-à-dire **toute la valeur**.

#### Option 1D — Le téléphone devient le holder (retenue)
| Dimension | Évaluation |
|---|---|
| « Mac éteint » | ✅ le téléphone est l'appareil toujours allumé |
| Souveraineté | ✅✅ rien ne quitte les appareils de l'utilisateur |
| Coût | 🔴 refonte du cœur (quitte Python + `gws` CLI + Swift macOS) |

**Retenue** : seule option qui concilie « Mac éteint », souveraineté et absence de serveur. Le prix — la refonte native — est assumé.

### Axe 2 — Techno du holder/approbateur natif

#### Option 2A — PWA « web-first » (WebAuthn + PRF + appels Google directs)
| Dimension | Évaluation |
|---|---|
| Portée | ✅ les 5 OS via le navigateur, zéro store |
| Sécurité au repos | 🟠 coffre du navigateur < coffre matériel natif ; extension PRF encore jeune |
| Coût | 🟢 le plus frugal |

**Rejetée** au vu du curseur PO (sécurité au repos maximale). Reste un candidat *prototype* rapide si besoin.

#### Option 2B — Tauri 2 (Rust) (retenue)
| Dimension | Évaluation |
|---|---|
| Portée | ✅ desktop **et** mobile (Tauri 2) |
| Sécurité au repos | ✅✅ accès natif Secure Enclave / StrongBox / TPM ; cœur Rust (sûreté mémoire) |
| Auditabilité (libre) | ✅✅ petit binaire, surface réduite (vs Electron) |
| Coût | 🟠 stack à monter ; écosystème mobile Tauri jeune mais viable |

**Retenue** : meilleur alignement sécurité-au-repos + auditabilité open source.

#### Option 2C — Flutter (Dart)
| Dimension | Évaluation |
|---|---|
| Portée | ✅ les 5 OS |
| Sécurité au repos | ✅ plugins coffre natif (biométrie, secure storage) |
| Vélocité UI mobile | ✅✅ la meilleure |
| Coût | 🟠 runtime plus lourd ; cœur sécurité en Dart |

**Alternative crédible** : à préférer si la priorité bascule vers la richesse UI mobile plutôt que l'auditabilité d'un cœur Rust minimal.

#### Option 2D — Garder Python, le porter sur mobile (BeeWare/Kivy)
**Rejetée** : écosystème Python mobile immature pour un composant de sécurité avec tâches de fond et coffre matériel.

### Axe 3 — L'approbation biométrique cross-OS

**Passkeys / WebAuthn (retenu)** contre *réécrire un helper biométrique natif par OS*. Le standard FIDO2 donne, via **une** API, clé en enclave + biométrie + signature d'un challenge — sur les 5 OS. Écrire 5 helpers natifs (à la `elicitation-sign.swift`) serait le même travail cinq fois. La logique de l'ADR-0005 (payload canonique, `nonce`, reçu) est **conservée** ; seul le mécanisme de signature change.

## Modèle de menace (nouveau — l'agent cloud change la donne)

L'ADR-0005 supposait un agent **local semi-honnête** (contournable via `gws` nu, mais physiquement proche). Dès que le requester est **cloud**, il faut le supposer **distant et potentiellement hostile**. Conséquences, non négociables :

- Le holder **ne fait jamais confiance** au requester : toute action sensible exige une **approbation signée** fraîche (anti-rejeu par `nonce` + `expires_at`).
- **WYSIWYS** obligatoire : le téléphone affiche l'action *avant* la signature ; on ne signe jamais un opaque.
- Le relais (s'il existe) est **aveugle** : il ne voit que des enveloppes signées, jamais un jeton, jamais un contenu Google.
- **Moindre autorité** conservée : l'approbation porte sur *une* action (compte, cible, durée), pas un blanc-seing. La policy default-deny par service et les zones Drive temporaires restent la référence.

## Articulation avec les droits par session (ADR-0007 / PR #108)

Un axe **parallèle** (PR #108, ADR-0007 « droits par session ») isole le périmètre de **chaque session** (conversation) : `session_id` + jeton de droit porté dans l'appel + grain fin, en réutilisant lui aussi l'élicitation signée (ADR-0005). Les deux axes **s'emboîtent** :

- le *requester* de cet ADR **est** une « session » au sens de l'ADR-0007 ;
- l'*approver* (passkey, phase 1 / fiche 0078) **est** le « consentement distant » des **phases B/C** de l'ADR-0007 — à concevoir **une seule fois** ;
- ordre : la couche *session* se pose d'abord (ADR-0007 phase A, desktop) ; le consentement mobile (cet axe) s'y branche ensuite.

Les deux ADR restent **distincts** (questions différentes : *isolation par session* vs *où / comment approuver + détenir*) mais **doivent décrire le même mécanisme de consentement signé** (socle ADR-0005).

## Conséquences

**Devient possible**
- Accéder à ses comptes Google depuis le mobile, Mac allumé **ou éteint**, sans céder les jetons à un tiers.
- Approuver depuis le téléphone via **une** API standard sur les 5 OS.
- Sécurité au repos **matérielle** (clé non exportable, gardée par biométrie).
- Distribuer le projet en **logiciel libre** sans imposer d'infrastructure centrale.

**Devient plus difficile / coûteux**
- Le holder mobile **quitte Python** : refonte du cœur (Rust/Tauri). C'est le point dur.
- **Deux implémentations du holder** cohabiteront pendant la transition (Python-macOS existant + natif) → risque de divergence de règles de sécurité, à cadrer.
- **Multi-appareils OAuth** : un même compte Google détenu par le Mac *et* le téléphone impose de choisir entre **enrôlement par appareil** (chaque appareil a ses propres jetons dans son coffre — recommandé) et **synchronisation chiffrée** entre appareils (plus pratique, surface plus grande).

**Tranché le 2026-08-15 (cf. Décision §8)** : enrôlement *par appareil* ; les deux holders cohabitent (migration progressive) ; licence Apache-2.0.

**À revisiter plus tard (ADR/fiches enfants)**
- **Design du relais aveugle** (protocole, découverte, hébergement) — et le cas « Mac allumé » sans relais (LAN direct / tunnel type WireGuard). → ADR enfant.
- **Enrôlement multi-appareils** : le *protocole concret* (le principe « par appareil » est acté §8). → ADR enfant.
- **Unification desktop** sur Tauri 2 à terme (retirer le Python) : ouverte — décision différée.
- **Modèle de menace public** publié + **CI multi-OS** (builds desktop + mobile ; cf. coût GHA).

## Suites (action items)

1. [x] Valider cet ADR (direction + invariants) avec le PO — **Accepté le 2026-08-15** (cf. §8).
2. [x] Ouvrir la **fiche backlog** — épic **0077** + phase 1 **0078**.
3. [ ] **Phase 1, à faible risque** : poser l'approbation par **passkey** sur l'architecture *actuelle* (Mac = holder allumé, téléphone = approbateur) — bénéfice immédiat, sans refonte.
4. [ ] **Prototype** holder natif Tauri 2 : sceller un jeton dans le coffre matériel + un appel Google, sur un OS mobile.
5. [ ] ADR enfant sur l'**enrôlement multi-appareils** et un autre sur le **relais aveugle**.

## Références

- [ADR-0005](ADR-0005-elicitation-signee-v2.md) — élicitation signée (brique de signature réutilisée).
- **ADR-0007** « droits par session » (PR #108) — axe complémentaire : isolation par session ; son consentement distant (phases B/C) = la phase 1 de cet axe (fiche 0078). Même socle de signature (ADR-0005).
- [ADR-0003](ADR-0003-contenu-drive-via-depot-broker.md), [ADR-0006](ADR-0006-fichiers-recus-repertoire-dedie.md) — couloirs de contenu, modèle de menace « default-deny ».
- Code actuel : `gateway/mcp_server.py` (stdio), `gateway/broker_server.py` (4878), `gateway/elicitation.py`, `scripts/elicitation-sign.swift`, `admin/server.js` (4877).
- Standards : WebAuthn / FIDO2 (passkeys), coffres matériels (Secure Enclave, Android StrongBox/Keystore, TPM).
