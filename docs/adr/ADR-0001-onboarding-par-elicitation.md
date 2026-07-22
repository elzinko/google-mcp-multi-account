# ADR-0001 : Onboarding guidé par le MCP — élicitation, jamais exécution

**Statut :** Proposé
**Date :** 2026-07-22
**Décideurs :** Thomas (PO)

## Contexte

Le README donne l'impression d'une configuration lourde : provisioning GCP,
gestes console, `gwsa add` par compte, rôles IAM, branchement MCP, policies…
La demande produit : que l'humain ne fasse que l'**init GCP** (fiable et
simple), et que **tout le reste** soit piloté depuis le client LLM via le
MCP — un « init » guidé, et la connexion de nouveaux comptes par élicitation
à authentification forte.

Faits d'architecture qui contraignent la réponse :

1. **Google interdit d'automatiser** la création du client OAuth « Desktop
   app » et la publication de l'app. Aucun outil (script, MCP, Terraform) ne
   supprimera ces 2 gestes console. `provision-gcp.sh` les guide déjà.
2. Le **modèle de sécurité du projet** repose sur : *l'outil vérifie,
   l'humain autorise, le LLM propose*. Toute mutation qui élargit l'accès
   (unlock, grant, connexion de compte, binding IAM) exige un geste humain.
3. Dans **Claude Desktop, il n'y a pas de shell** : le serveur MCP est le
   seul pont. Or aujourd'hui tout le diagnostic de setup (`provision-gcp.sh
   status`, `gwsa list` enrichi) n'existe qu'en terminal — un utilisateur
   Desktop ne peut pas être guidé.
4. Les briques d'élicitation existent déjà (PRs #5/#6/#7) :
   `access_request` kind=`add_account` (email requis, Touch ID sur `gwsa
   add`), sonde IAM post-connexion, `status` avec dérive IAM, `sync-iam`
   idempotent.

## Décision (proposée)

Faire de l'onboarding un **dialogue guidé par le MCP**, en gardant la ligne
« élicitation, jamais exécution » :

- Ajouter un tool MCP **`setup_status`** (lecture seule) qui agrège l'état
  complet du setup — projet provisionné, app publiée, `client_secret`,
  profils connectés, rôle IAM par compte, verrous/policies — en réutilisant
  `provision-gcp.sh status` (à doter d'une sortie `--json`). Le LLM (y
  compris Desktop) obtient une **checklist structurée** et propose, pour
  chaque manque, la commande exacte : c'est le « init » demandé, sous forme
  guidée.
- La connexion d'un nouveau compte reste l'élicitation
  **`access_request add_account`** (déjà câblée) : Touch ID + consentement
  OAuth = deux barrières physiques, l'humain exécute.
- Réécrire le **README en quickstart 3 étapes** (provisionner → brancher le
  MCP → « initialise mes comptes »), les détails partant dans `docs/`.

## Options considérées

### Option A — Statu quo (docs terminal uniquement)

| Dimension | Évaluation |
|---|---|
| Complexité | Nulle |
| Sécurité | Inchangée |
| UX Desktop | Mauvaise — aucun guidage possible sans shell |
| UX Claude Code | Correcte (CLAUDE.md + scripts) |

**Pour :** rien à faire. **Contre :** l'impression « configuration
compliquée » demeure ; Desktop reste aveugle.

### Option B — Le MCP exécute le setup (« init » qui fait tout)

| Dimension | Évaluation |
|---|---|
| Complexité | Moyenne |
| Sécurité | **Rupture du modèle** |
| UX | Excellente en apparence |

**Pour :** zéro friction. **Contre :** `sync-iam`/gcloud n'a **aucune
barrière physique** — un LLM (ou une injection de prompt) pourrait muter
l'IAM cloud sans humain dans la boucle ; multiplier les prompts Touch ID
crée la fatigue d'approbation ; contredit CLAUDE.md et le threat model.
**Rejetée.**

### Option C — `setup_status` lecture seule + élicitation guidée (retenue)

| Dimension | Évaluation |
|---|---|
| Complexité | Faible (réutilise status/`iam_profile_states`, sortie JSON) |
| Sécurité | Modèle préservé — le tool ne fait que LIRE |
| UX Desktop | Bonne — checklist + commandes prêtes à coller |
| UX Claude Code | Idem, et le LLM peut lancer les lectures lui-même |

**Pour :** répond au besoin (« le MCP guide et aide ») sans toucher au
modèle. **Contre :** l'humain colle encore les commandes de mutation — c'est
un choix assumé, pas une limite technique.

### Option B′ — Variante différée : exécution médiée à double barrière

`account_add` exécuté par le MCP mais gaté par Touch ID **et** consentement
OAuth (les deux barrières physiques subsistent). Défendable pour ce geste
précis — mais pas pour `sync-iam` (aucune barrière équivalente). Notée comme
évolution possible, **différée** tant que la friction du copier-coller n'est
pas prouvée gênante.

## Conséquences

- Devient plus simple : l'onboarding Desktop (« initialise mes comptes » →
  checklist guidée), le README (quickstart 3 étapes), le diagnostic à tout
  moment (`setup_status`).
- Devient plus exigeant : maintenir la sortie `--json` de `status` comme
  contrat du tool ; documenter la frontière « le MCP lit, l'humain mute ».
- À revisiter : B′ si la friction résiduelle le justifie ; multi-projet GCP
  (fiche 0003/0008) hors périmètre.

## Scénarios validés par diagrammes de séquence

- [diagrams/onboarding-setup-initial](../../diagrams/onboarding-setup-initial/) — les 3 étapes cibles
- [diagrams/onboarding-add-account-elicite](../../diagrams/onboarding-add-account-elicite/) — connexion élicitée (existant, PR #7)
- [diagrams/onboarding-reparation-iam](../../diagrams/onboarding-reparation-iam/) — dérive IAM : détection ×2, réparation humaine (PRs #5/#6)

## Actions

1. [ ] Fiche 0009 : `provision-gcp.sh status --json` + tool MCP `setup_status` (lecture seule).
2. [ ] Fiche 0010 : refonte README en quickstart 3 étapes, détails → `docs/`.
3. [ ] Merger la pile #5 → #6 → #7 (préalable : les briques d'élicitation).
