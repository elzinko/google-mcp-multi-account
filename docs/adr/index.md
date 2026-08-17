# Décisions d'architecture (ADR)

Un **ADR** (*Architecture Decision Record*) est une décision de conception **datée** :
on y explique *pourquoi* le projet a tranché d'une certaine façon, pas seulement ce
qu'il fait. Chaque fiche suit le même squelette — **Contexte** (le problème, les
contraintes) → **Décision** → **Options considérées** (pesées puis rejetées, avec leurs
raisons) → **Conséquences**.

**Comment les lire.** Chaque ADR est **autonome** : ouvrez celui qui vous intéresse et
commencez par son **TL;DR** (une phrase, en tête). Un fil rouge les traverse tous :
*l'outil vérifie, l'humain autorise, le LLM propose.* Le vocabulaire qui revient est
défini dans le **glossaire** ci-dessous — à garder ouvert à côté pendant la lecture.


## Glossaire

- **access_request** — le tool MCP d'élicitation : il **renvoie une commande à faire exécuter par l'humain**, il n'exécute jamais rien.
- **admin** — l'interface web **locale** (`mag admin`, `127.0.0.1:4877`) où l'humain gère les comptes ; jamais exposée hors loopback.
- **alias** — le nom court d'un profil (ex. `perso`). Optionnel : dans les commandes `mag`, on peut aussi désigner un compte par son **email** (les tools MCP, eux, utilisent l'alias).
- **broker** — le daemon local (`bin/google-broker`, `127.0.0.1:4878`) — le **seul** à exécuter `gws` pour **accéder aux données** ; il re-vérifie verrou et policy à chaque appel (la découverte, elle, lit encore `gws auth status` en direct).
- **capacité de session** — un droit fin accordé à une **session** : (service × opération × ressource ?), **signé** et expirant. S'intersecte avec la policy compte et le manifeste projet ; jamais un élargissement silencieux (ADR-0007).
- **client_secret.json** — le secret de l'app OAuth (« Desktop app »), stocké **hors dépôt**. Les surfaces MCP n'en vérifient que la **présence** ; il n'est jamais affiché ni committé.
- **connecteur** — l'entrée `google-multi-account` sous `mcpServers` dans la config du client — à ne pas confondre avec le **dépôt** `google-mcp-multi-account`.
- **corbeille (Drive)** — mettre à la corbeille compte comme une **suppression** (catégorie `delete`) ; la racine d'une zone est immuable (fiche 0037).
- **default-deny** — la règle de base : tout ce qui n'est pas explicitement autorisé est **refusé** (un service non déclaré est refusé).
- **descripteur de capacité** — les libellés de droits affichés dans l'admin, **dérivés côté navigateur** (`admin/index.html`) à partir des flags de policy bruts servis par `/api/profiles` — jamais codés en dur (ADR-0004).
- **.downloads** — le dossier (`~/.config/gws-accounts/.downloads`, 0700) où atterrissent les **pièces jointes reçues** — jamais un chemin arbitraire, jamais d'écrasement (ADR-0006).
- **.email** — un fichier par profil qui mémorise l'email, lisible **même profil verrouillé** (pour le diagnostic). Les lectures gateway/MCP ne relancent jamais `gws` ; seul un backfill humain (`mag list`, admin) peut le recalculer pour un ancien profil (ADR-0002).
- **gateway** — `gateway/` : la couche qui vérifie **verrou + policy** avant chaque appel à Google.
- **mag** — la CLI **de ce projet** — le poste de pilotage humain (`add`, `lock`/`unlock`, `grant`, `policy`, `wire`). Anciennement `mag` (alias déprécié conservé).
- **grant** — une autorisation **temporaire** d'écrire dans une zone Drive, pour la durée d'une session (`.sessions/<id>.json`).
- **gws** — la CLI officielle **Google Workspace** (amont, à installer) qui parle réellement aux API Google.
- **IAM (rôle Google Cloud)** — le droit, **par compte**, d'utiliser le projet OAuth (`serviceUsageConsumer`). Sans lui, un compte « connecté » échoue au 1er vrai appel.
- **jeton de session** — le secret créé par `mag session open` (geste **signé**) qui identifie une **session** ; l'assistant le présente à chaque appel. Sans jeton : aucun accès aux données, seulement la demande de création (ADR-0007).
- **MCP** — le protocole (*Model Context Protocol*) par lequel l'assistant parle au serveur local.
- **policy** — le fichier `policy.json` d'un profil : il dit, service par service, ce qui est autorisé (lecture, envoi, création…).
- **profil** — un compte Google connecté, isolé dans son dossier `~/.config/gws-accounts/<alias>/`.
- **serveur MCP** — `bin/google-mcp` : la porte d'entrée des données (Gmail/Drive) pour l'assistant.
- **session** — une conversation LLM, identifiée par son **jeton** (pas la connexion MCP) ; elle porte ses propres droits, **isolés** des autres sessions, avec un cycle de vie TTL / révocation (jamais la déconnexion). Les sous-agents héritent d'un sous-ensemble du parent (ADR-0007).
- **setup_status** — le tool MCP de **diagnostic** (lecture seule) : il rapporte l'état du setup et **propose** les commandes des étapes manquantes.
- **strongauth / Touch ID** — mode **optionnel** (`mag strongauth on`) : une fois activé, chaque unlock/grant/connexion exige une empreinte **Touch ID** qui signe l'action précise.
- **unlock** — déverrouiller un profil, en général pour une durée limitée (reverrouillage automatique).
- **.uploads** — le dossier temporaire d'où `gws` **téléverse** un contenu vers Drive, le temps d'un appel (ADR-0003).
- **vault** — l'isolation **prévue** (Phase 2.1) qui mettra les identifiants hors de portée d'un agent — pas encore construite (fiche 0003).
- **verrou (lock)** — un profil **verrouillé** refuse tout accès aux données tant qu'un humain ne l'a pas déverrouillé (`.locked` / `.unlock-until`).
- **zone (Drive)** — un dossier Drive sous lequel l'écriture est autorisée (`writeFolders`). Hors zone : refus.
- **élicitation** — quand l'assistant ne peut pas agir lui-même : il **propose** la commande exacte, c'est l'humain qui l'exécute (unlock, grant, connexion). Le LLM n'élargit jamais son propre accès.
- **élicitation signée** — le durcissement (ADR-0005) : le consentement Touch ID est **lié cryptographiquement** à l'action exacte, pas juste « un humain est présent ».
