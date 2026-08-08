# Décisions d'architecture (ADR)

Un **ADR** (Architecture Decision Record) est une décision de conception **datée** : on y fige *pourquoi* le projet a tranché d'une certaine façon, pas seulement *ce qu'*il fait. Chaque fiche suit toujours le même squelette — **Contexte** (le problème, les contraintes) → **Décision** → **Options considérées** (celles qu'on a pesées et rejetées, avec leurs raisons) → **Conséquences** (ce que ça rend plus simple, plus sûr, ou plus exigeant).

**Comment les lire.** Chaque ADR est **autonome** : on peut en ouvrir un sans avoir lu les autres. Il s'ouvre sur son en-tête (**Statut** — proposé / accepté — et **Date**), parfois un bloc de ratification qui résume l'état à jour ; ensuite ça se lit de haut en bas. Les renvois entre ADR (« ADR-0002 », « fiche 0037 ») situent la décision dans son histoire, sans obliger à les suivre.

Un fil rouge traverse tout : *l'outil vérifie, l'humain autorise, le LLM propose*. Le vocabulaire qui revient sans cesse — **élicitation**, **verrou**, **grant**, **policy**, **broker**, **IAM**… — est défini dans le **glossaire ci-dessous** : une ligne par terme, à garder ouvert en marge pendant la lecture.

## Glossaire

- **.downloads** — Répertoire de téléchargement dédié (`<GWSA_ROOT>/.downloads`, 0700), seule destination possible des pièces jointes reçues via `gmail_attachment_get` (ADR-0006) — sens descendant.
- **.email** — Fichier par profil contenant l'email en clair, écrit au geste humain `gwsa add` ; source unique de l'email (lisible même verrouillé), plus jamais recalculé via `gws` (ADR-0002).
- **.upload-roots / GWSA_UPLOAD_ROOTS** — Le fichier (et la variable d'env) qui listent les dossiers-sources autorisés en lecture pour `drive_upload` ; l'humain seul les ouvre, jamais le LLM (aucun tool n'écrit sous `GWSA_ROOT`).
- **.uploads** — Répertoire de dépôt dédié (`<GWSA_ROOT>/.uploads`, 0700) où le contenu à téléverser est matérialisé le temps d'un appel `gws --upload`, puis effacé en `finally` (ADR-0003) — sens montant.
- **access_request** — Tool MCP d'élicitation : il ne fait qu'énoncer la commande que l'humain doit exécuter (kind `unlock`, `grant`, `add_account`) — il n'exécute jamais rien lui-même.
- **admin** — L'interface web d'administration locale (`admin/server.js`, `127.0.0.1:4877`), jamais exposée hors loopback ; c'est l'humain qui y clique, pas le LLM.
- **ADR (Architecture Decision Record)** — Une décision de conception datée et numérotée (ADR-0001…), autonome, structurée en Contexte → Décision → Options pesées → Conséquences.
- **ADR-0001 / ADR-0002 / ADR-0003 (référencés)** — ADR antérieurs cités comme précédents : onboarding par élicitation ; email hors verrou ; contenu Drive via le dépôt du broker.
- **alias** — Le nom court qui identifie un compte connecté (ex. dans `gwsa <alias> …` ou l'URL admin `/api/<alias>/<action>`).
- **ALIAS_RE** — L'expression régulière qui valide les noms d'alias ; grâce à elle les dossiers cachés (`.uploads`, `.downloads`) ne sont jamais pris pour un compte.
- **backfill / backfiller** — Remplir rétroactivement une donnée manquante des anciens profils (ici le fichier `.email`), au passage humain `gwsa list` ou via l'admin.
- **broker** — Le seul process autorisé à exécuter `gws` pour les données (daemon loopback `127.0.0.1:4878`, `bin/google-broker`) ; re-vérifie verrou + policy avant chaque appel (Phase 2 A).
- **broker_server.py** — Le module du daemon broker (`gateway/broker_server.py`) ; seul endroit de `gateway/` autorisé à poser `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`.
- **capsHtml / table SVCDEF** — Identifiants du front admin qui traduisent les flags de policy bruts en libellés de droits (« vert/rouge ») ; le mapping vit dans une seule table côté front.
- **carve-out / require_unlocked** — `require_unlocked` est la garde de code qui bloque l'accès à un profil verrouillé ; un « carve-out » serait une exception à cette garde (option rejetée en ADR-0002).
- **client_secret.json** — Le fichier secret de l'app OAuth « Desktop app », stocké en clair hors repo (`~/.config/gws-accounts/`) ; jamais lu, affiché ni committé.
- **clients LLM (Claude Desktop, Cursor, Claude Code)** — Les applications qui appellent le MCP (données) ou le shell (admin) ; celles avec shell (Code, Cursor) motivent la mitigation « pas de `gws` nu ».
- **codesigné / entitlements** — La signature Apple et les droits associés qui manquent à un script Swift non signé, d'où l'erreur `errSecMissingEntitlement` et le repli sur une clé en fichier.
- **corbeiller / corbeille** — Verbe interne « mettre à la corbeille » (suppression) dont le sens exact — vraie suppression ? — n'est pas encore tranché (fiche 0037).
- **couloir (stable / dev)** — Un canal d'installation isolé (stable ou dev), chacun avec sa propre racine `GWSA_ROOT` et donc son propre dépôt (fiche 0023).
- **default-deny (défaut-deny)** — Règle de base : un service absent de la policy est refusé (sauf `auth`/`schema`) ; un service déclaré est fail closed — seule une catégorie explicitement à `true` passe.
- **descripteur de capacité / verbes autorisés** — La liste des actions permises (créer, modifier, corbeiller…) dérivée des flags de policy, calculée côté serveur et seulement rendue par le front — jamais codée en dur.
- **Desktop (Claude Desktop)** — Le client LLM sans shell : le MCP y est le seul pont, d'où le besoin d'un onboarding guidé par `setup_status`.
- **DIP (Dependency Inversion Principle)** — Principe SOLID : dépendre d'une abstraction plutôt que d'un détail ; ici la policy vit côté serveur et le front dépend du descripteur de capacité.
- **drive_create / drive_update / drive_upload / drive_copy** — Tools MCP d'écriture Drive, tous limités aux zones autorisées : créer avec contenu, remplacer le contenu d'un fichier non-natif, téléverser un fichier local, copier.
- **fail closed / repli** — En cas de doute (JSON corrompu, biométrie indisponible, enrôlement manquant) on refuse plutôt que d'autoriser ; jamais d'accord silencieux.
- **fiche (backlog)** — Une carte du backlog interne du projet (ticket markdown numéroté : 0001, 0009, 0037…), référencée par numéro comme source ou suite d'une décision.
- **gateway** — La moitié « serveur MCP » (`gateway/`) : valide l'alias, applique verrou + policy, journalise, puis délègue l'exécution `gws` au broker — elle ne lance plus `gws` elle-même.
- **GCP (Google Cloud Platform)** — L'environnement Google Cloud où vit le projet de l'app OAuth à provisionner (le seul geste d'init laissé à l'humain).
- **gmail_attachment_get** — Tool MCP qui écrit une pièce jointe reçue dans `.downloads` et en renvoie le chemin ; contenu tiers, traité comme potentiellement hostile.
- **gmail_draft_create** — Tool MCP qui prépare un brouillon Gmail ; aucun tool MCP n'envoie de mail (le LLM prépare, l'humain envoie).
- **GOOGLE_WORKSPACE_CLI_CONFIG_DIR** — Variable d'env qui pointe `gws` vers la config d'un profil ; l'appeler à la main hors gateway contourne verrou, policy et journal — chemin à bloquer côté agent.
- **grant / zone Drive** — Autorisation d'écrire dans un dossier Drive précis : permanente (policy `writeFolders`) ou temporaire accordée par l'humain (`gwsa grant`, 8 h par défaut, expire).
- **gws** — Le CLI officiel Google Workspace (`googleworkspace/cli`) qui détient les tokens et parle réellement aux API Google : la « capacité réelle » d'accès aux données.
- **gwsa** — Le wrapper maison autour de `gws` : isole chaque compte, ajoute verrous/policy/grants ; c'est la porte admin humaine (`gwsa add`, `gwsa list`, `gwsa unlock`…).
- **GWSA_CLIENT** — Champ déclaratif qui identifie l'émetteur dans le journal (`mcp`, `claude-code`, `cli`…) ; utile au debug mais falsifiable — pas une identité forte.
- **GWSA_ROOT / gwsa_root()** — La racine de configuration partagée par gateway et broker (tokens, pidfile, `usage.jsonl`, `.uploads`, `.downloads`) ; un couloir = une racine.
- **IAM (rôle IAM)** — Le contrôle d'accès côté Google Cloud ; ici le rôle `serviceUsageConsumer` que chaque compte doit avoir sur le projet GCP de l'app OAuth pour l'utiliser.
- **IAM — binding (gcloud add-iam-policy-binding)** — La commande admin (geste humain) qui attribue le rôle IAM manquant à un compte sur le projet GCP.
- **IAM — dérive** — L'écart détecté quand un compte connecté n'a pas (ou plus) le rôle IAM attendu ; `setup_status` / `provision-gcp.sh status` le signalent et proposent la réparation.
- **iam_profile_states** — La structure interne qui calcule l'état IAM par profil, réutilisée par `setup_status` et la sortie `provision-gcp.sh status`.
- **injection de prompt** — Attaque où un texte lu (un mail, une pièce jointe) détourne le LLM pour lui faire exécuter les ordres de l'attaquant ; motive le durcissement de `drive_upload` et `gmail_attachment_get`.
- **install-claude-*.sh** — Les scripts d'installation qui réécrivent l'environnement ; d'où le choix du fichier `.upload-roots` (persistant) plutôt que d'une variable d'env perdue à la mise à jour.
- **legacy** — Un profil ancien créé avant un durcissement (ex. sans `policy.json`, ou sans `.email`) : non filtré/complété tant qu'on ne le met pas à jour à la main.
- **liste blanche** — Inverse d'une liste noire : seuls les dossiers explicitement déclarés sont autorisés (ici les sources lisibles de `drive_upload`) ; tout le reste est refusé.
- **loopback (127.0.0.1)** — L'interface réseau strictement locale ; admin (`:4877`) et broker (`:4878`) n'écoutent que là, jamais exposés au réseau externe.
- **manifeste projet** — Une des actions que l'élicitation signée peut couvrir (au même titre qu'unlock/grant) : l'approbation cryptographique d'un périmètre de projet.
- **maquette v11** — La version de maquette de l'admin ratifiée en ADR-0004 (liste-maître → page de détail, sans routeur ni URL).
- **MCP (Model Context Protocol)** — Le protocole/serveur local (`bin/google-mcp` → `gateway/`) qui sert de seul pont recommandé entre un client LLM et les comptes Google.
- **nonce / anti-rejeu (nonces.json)** — Un jeton à usage unique inséré dans le payload à signer ; `nonces.json` mémorise ceux déjà vus pour empêcher de rejouer une approbation.
- **O_CREAT|O_EXCL, 0600/0700** — Drapeaux/permissions Unix : création exclusive sans écrasement (échoue si le fichier existe) et fichiers/dossiers lisibles par le seul propriétaire.
- **OAuth (Desktop app, consentement)** — Le mécanisme d'autorisation Google ; la création du client « Desktop app » et sa publication sont les deux gestes console que Google interdit d'automatiser.
- **payload canonique** — Le JSON normalisé d'une action à approuver (`action`, `alias`, `target`, `session_id`, `nonce`, `issued_at`, `expires_at`) dont dérivent le prompt Touch ID et la signature.
- **Phase 1 / 2 A / 2.1** — Jalons produit : 1 = MCP + policy + verrous (déployé) ; 2 A = broker loopback seul exécuteur de `gws` (déployé) ; 2.1 = vault des credentials (prévu).
- **PO (Product Owner)** — Le rôle de décideur produit ; ici Thomas, signataire des ADR.
- **POC (proof of concept)** — Prototype servant à délimiter le périmètre ; certaines améliorations sont explicitement rangées « hors périmètre POC ».
- **policy / policies** — Les règles d'autorisation par service et par profil (`policy.json`), détenues côté serveur et appliquées avant chaque commande.
- **policy-check.py** — Le script (`scripts/policy-check.py`) qui applique la policy en default-deny avant tout appel `gws`, côté `gwsa` comme côté gateway.
- **PR #5/#6/#7** — Des pull requests (demandes de fusion GitHub) identifiées par numéro ; ici la pile des briques d'élicitation préalables à l'onboarding guidé.
- **presence check** — La version v1 de strongauth : vérifie seulement « un humain est là » (Touch ID), sans lier le consentement à l'action précise.
- **profil** — Le dossier local d'un compte Google connecté (`~/.config/gws-accounts/<alias>/`) : tokens chiffrés, policy, verrou, `.email`.
- **profiles_list** — Le tool MCP qui liste les comptes connectés (alias, état de verrou, policy).
- **provision-gcp.sh** — Le script d'init GCP côté humain (`status`, `--json`, `sync-iam`) : état du provisioning et des rôles IAM ; `status` est en lecture seule.
- **registre session / session_id** — L'état de session côté humain : une fois la signature vérifiée, le broker fait confiance au `session_id` enregistré pour la durée accordée.
- **REPO_DIR** — Variable pointant le dépôt git, utilisée comme répertoire courant du broker en démarrage automatique — contrainte réglée par ADR-0003.
- **reçus (receipts.jsonl)** — Les preuves d'approbation signées (`.elicitation/receipts.jsonl`, plus des entrées `decision=elicitation` dans `usage.jsonl`).
- **Secure Enclave / Keychain** — Les magasins de clés Apple (puce sécurisée / trousseau macOS) où l'on tente de ranger la clé de signature ; repli sur un fichier 0600 si l'entitlement manque.
- **sens montant / descendant** — Jargon interne : montant = envoi (upload, via `.uploads`) ; descendant = réception (download, via `.downloads`).
- **session-grants.json** — Le fichier où vivent les zones Drive temporaires (grants de session) que la policy vérifie avant une écriture.
- **setup_status** — Le tool MCP en lecture seule qui agrège l'état du setup (projet, publication, `client_secret`, profils, rôle IAM, verrous/policies) et propose, pour chaque manque, la commande exacte à exécuter.
- **strongauth** — Le mode « authentification forte » : exige une preuve de présence physique (Touch ID / mot de passe macOS) pour `unlock`, `grant` et `add`.
- **sync-iam** — Sous-commande idempotente de `provision-gcp.sh` qui répare d'un coup les rôles IAM manquants (confirmation par compte) ; geste humain, jamais le LLM.
- **tests hermétiques** — Les tests automatiques isolés (`./scripts/test.sh`) : sans binaire `gws`, sans comptes réels, sans réseau.
- **threat model (modèle de menace)** — L'analyse des menaces (`docs/threat-model.md`) : ce qui est garanti ou non, phase par phase ; principe = l'outil vérifie, l'humain autorise, le LLM propose.
- **Touch ID** — La biométrie macOS utilisée par strongauth comme barrière physique (helper Swift appelé en chemins absolus, jamais via le PATH).
- **unlock** — Le geste humain qui lève le verrou d'un profil (temporaire par défaut : `gwsa unlock <alias> [min]`).
- **usage.jsonl** — Le journal d'audit (`<GWSA_ROOT>/usage.jsonl`) : appels autorisés, refus de policy et refus de verrou, avec le client émetteur — coopératif, pas une identité forte.
- **vault (coffre)** — Évolution prévue (Phase 2.1, fiche 0003) : mettre les credentials hors de portée de l'agent ; seule la socket broker resterait utile.
- **verrou / .locked** — État « accès aux données sur demande » d'un profil (`.locked`) : tout appel de données est refusé (CLI comme MCP) jusqu'à un `unlock` humain ; seul l'email reste lisible.
- **YAGNI (You Aren't Gonna Need It)** — « Tu n'en auras pas besoin » : argument pour rejeter une complexité anticipée (ex. un mini-routeur pour 5-20 comptes).
- **zonesOnly / writeFolders** — Mode Drive d'une policy : écriture autorisée uniquement sous les dossiers listés dans `writeFolders` (∪ grants temporaires) ; partout ailleurs, refus.
- **élicitation** — Quand l'agent ne peut pas agir lui-même : il propose la commande exacte, c'est l'humain qui l'exécute (unlock, grant, connexion de compte). Le LLM n'élargit jamais son propre accès.
- **élicitation signée (v2)** — Durcissement (ADR-0005 / fiche 0001) : le consentement est lié cryptographiquement à l'action précise (payload canonique signé ECDSA P-256), au lieu d'un simple « un humain est là ».
