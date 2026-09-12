---
id: 0018
title: Cross-platform — faire tourner le projet hors macOS (Linux, Intel)
type: feature
priority: P3
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-07-24
---

> **Ouverte aux contributions — l'auteur ne la portera pas.** Décision PO du
> 2026-07-25 : le projet tourne sur macOS, l'auteur n'a aucun besoin propre de
> Linux, et le coût restant (smoke Docker, `gws auth login` en conteneur) n'est
> pas justifié au regard de ses priorités. La fiche est **volontairement laissée
> complète et à jour** pour qu'un contributeur puisse la prendre telle quelle :
> le constat technique ci-dessous est vérifié, les dépendances sont constatées,
> le périmètre est arbitré. Passée en **P3** — bonne candidate **« good first issue »** pour un
> contributeur : constat vérifié, dépendances constatées, périmètre net.

## Contexte / Problème

Le README annonce **macOS (Apple Silicon)** comme requis, en citant « Trousseau
(clé de chiffrement), Touch ID, chemins Homebrew ». L'audit du code (2026-07-25)
montre que **ce constat est largement faux**, et c'est ça le vrai problème : la
doc décourage un adoptant Linux alors que le chemin nominal marche presque.

Ce que l'audit a établi, point par point :

| Affirmation | Réalité |
|---|---|
| Clé maître dans le Trousseau macOS (`bin/mag`) | **Faux.** Aucun appel `security`/keychain dans le repo. C'est `gws` qui gère la clé, via le crate Rust `keyring` (Secret Service/libsecret sur Linux) **et** un backend `file` prévu pour le headless. |
| Symlink `/opt/homebrew/bin/mag` codé en dur | **Faux.** L'occurrence en `bin/mag:39` est un commentaire ; `resolve_repo_dir` suit le symlink. Le README utilise déjà `$(brew --prefix)`. |
| Présence humaine via Touch ID | Vrai mais **opt-in** : `require_strong_auth` sort si `$GWSA_ROOT/.strong-auth` n'existe pas. Par défaut, aucune dépendance Swift. |
| `stat -f %m`, `open` | Vrai, mais **hors chemin nominal** : `provision-gcp.sh` (setup one-shot) et un `open` déjà en `\|\| true` dans `mag admin`. |
| Seuls `test.sh` et `install-claude-desktop.sh` portables | **Sous-estimé.** Tout `gateway/` (~1 750 lignes, le serveur MCP) est portable — que du `subprocess`. |

**Le chemin nominal — client LLM → MCP → `gateway/` → `gws` — est donc déjà
portable aujourd'hui.** Le travail restant n'est pas la « couche d'abstraction
mince » décrite à la capture : c'est de la doc à corriger, une install sans
`brew`, et un smoke qui le prouve.

## Valeur

- **Débloque l'épic [[0017]]** : Linux est la plateforme par défaut des serveurs
  MCP et de tout dev non-Apple. Tant que le README dit « macOS requis », la
  population adressable reste 1.
- **Corrige une contre-vérité publique** : le README affirme un requis (Trousseau)
  que le code n'a pas. C'est un bug de documentation sur la porte d'entrée du
  repo — coût quasi nul, effet direct sur l'adoption.
- **Requalifie le coût** : la fiche annonçait un chantier d'architecture, la
  réalité est ~10× plus petite. La laisser mal décrite la maintient artificiellement
  en bas du backlog pour de mauvaises raisons.

## Proposition

**Périmètre : chemin nominal seulement** (arbitrage PO du 2026-07-25).

Dans le périmètre :
- **Install sans Homebrew** : documenter le chemin `gws` par tarball Linux
  (releases officielles) + le symlink `mag` résolu via PATH, sans `brew --prefix`.
- **Backend de clé** : documenter `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file`
  comme le mode headless/conteneur, **avec sa conséquence de sécurité** (la clé
  descend du keyring OS vers un fichier local `.encryption_key`).
- **strongauth** : refus propre et explicite hors macOS (pas de crash), documenté
  comme fonctionnalité macOS-only. Aucun équivalent polkit/PAM — écart de sécurité
  assumé et écrit.
- **README** : retirer l'affirmation « Trousseau » ; distinguer « chemin nominal :
  macOS + Linux » de « provisioning GCP + admin web : macOS ».
- **CI** : le job `ubuntu-latest` gagne un smoke d'install/exécution (il ne fait
  aujourd'hui que syntaxe bash/shellcheck/`py_compile`).

**Hors périmètre** (reste macOS, documenté comme tel) :
- `provision-gcp.sh` — `stat -f %m`, `open`, surveillance `~/Downloads`.
- `mag admin` — ouverture navigateur (dégrade déjà en `|| true`).
- Équivalent Linux de la présence humaine (polkit/PAM) — fiche séparée si besoin.
- Packaging/release installable → relève de [[0020]], pas d'ici.

## Critères d'acceptation

- [ ] Un conteneur Linux nu (Docker) exécute `mag list` et démarre `bin/google-mcp`,
      qui répond à `profiles_list` — sans macOS, sans `brew`, sans Swift.
- [ ] Aucun BSD-isme ni binaire macOS-only sur le chemin nominal (`bin/mag` +
      `gateway/`) : vérifié par le smoke, pas par relecture.
- [ ] `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` est documenté comme le mode
      Linux/headless, avec l'écart de sécurité explicité.
- [ ] `mag strongauth on` hors macOS échoue avec un message explicite (pas de
      trace), et la doc dit que c'est macOS-only.
- [ ] Le README n'annonce plus le Trousseau comme requis, et sépare chemin nominal
      (macOS + Linux) et outillage de setup (macOS).
- [ ] Le job CI `ubuntu-latest` exécute ce smoke à chaque push.
- [ ] **Une** lecture Gmail réelle depuis Linux validée à la main, protocole rangé
      dans `tests/manuels/` (voir la contrainte d'auth ci-dessous).

## Dépendances externes

- **`gws` / googleworkspace-cli** — le projet est en Rust et publie des binaires
  `x86_64` et `aarch64`, `linux-gnu` et `linux-musl` (+ Windows) en v0.22.5.
  *Accès constaté le 2026-07-25* (`gh release view --repo googleworkspace/cli`).
- **Docker** — v29.6.2, daemon `linux/aarch64` opérationnel en local, suffisant
  pour le smoke et rejouable en CI. *Accès constaté le 2026-07-25* (`docker info`).

**Contrainte d'auth à anticiper** : les credentials chiffrés sont liés à la
machine — `gws` refuse un `credentials.enc` venu d'ailleurs (« Decryption failed.
Credentials may have been created on a different machine »). On ne peut donc
**pas** monter `~/.config/gws-accounts` dans le conteneur pour tester : il faut un
`gws auth login` **dans** l'environnement Linux, avec le port du flow OAuth mappé
vers l'hôte et `KEYRING_BACKEND=file` (pas de Secret Service dans un conteneur nu).
C'est le seul point réellement coûteux de la fiche.

## Notes

- Portée « faire tourner », pas « parité parfaite ». Touch ID reste un plus macOS.
- Frontière avec [[0020]] : ici on prouve que **ça tourne** sur Linux ; là-bas on
  rend l'installation **agréable** (release, packaging). Si 0020 passe avant, il
  hérite du chemin d'install Linux défini ici.
- Le grooming du 2026-07-25 a réécrit le problème : la version initiale décrivait
  une abstraction OS à construire, invalidée par l'audit. Voir épic [[0017]].
- **Un morceau ne dépend d'aucun portage** : le README annonce le Trousseau comme
  un requis macOS alors que le code ne l'utilise pas. Cette correction-là est
  quasi gratuite et garde sa valeur même si personne ne porte jamais le projet —
  à traiter au fil de l'eau plutôt qu'à attendre un contributeur.
- Cette fiche est en français, comme tout le repo : un contributeur externe la
  lira dans cette langue tant que [[0019]] (doc EN) n'est pas fait.
- Rappel de l'épic : [[0003]] (vault) reste le prérequis de sécurité avant une
  vraie diffusion — porter sur Linux n'y change rien.
