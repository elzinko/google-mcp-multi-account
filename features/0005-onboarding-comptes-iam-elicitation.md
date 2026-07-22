---
id: 0005
title: Onboarding des comptes — chaîne complète élicitée (IAM compris), drift visible
type: feature
priority: P1
version:
epic:
status: idea
ready:
pr:
created: 2026-07-22
---

## Contexte / Problème

Premier run du test manuel `tests/manuels/drive-2-comptes` (2026-07-22) :
3 comptes connectés sur 4 étaient **inutilisables** (`403 Caller does not
have required permission to use project gws-multi-802ec6`) alors que tokens,
verrous et policies étaient parfaits. Cause : `gws` attache le projet GCP du
`client_secret.json` comme *quota project* ; seul le compte **propriétaire
du projet** (celui du provisioning) passe le contrôle IAM. Chaque autre
compte doit recevoir `roles/serviceusage.serviceUsageConsumer` — un geste
gcloud que rien ne documentait ni ne vérifiait.

Leçon générale : « connecter un compte » n'est pas un geste mais une
**chaîne** — projet GCP → test user (si app en Testing) → `gwsa add` →
**rôle IAM** → policy/verrou. Les maillons par-compte vivent dans 3 surfaces
(console web, gwsa, gcloud) et l'invariant « tout compte connecté peut
appeler l'API » n'était contrôlé nulle part. Quiconque reprend le projet
retombera dans le trou.

## Proposition

Faire de l'onboarding un flux de première classe, **élicité** (le LLM ou le
script propose, l'humain exécute — même philosophie que unlock/grant) :

1. **`provision-gcp.sh`** : demander la liste des adresses Gmail à connecter
   (élicitation au moment du provisioning, ré-invocable ensuite) et s'en
   servir deux fois : affichage pour l'écran *test users* (geste console
   non automatisable) et bindings IAM `serviceUsageConsumer` via gcloud.
2. **`provision-gcp.sh status`** : détecter la **dérive** — comparer les
   emails des profils connectés (`gwsa list`) aux membres de l'IAM policy du
   projet, signaler chaque compte sans rôle avec la commande exacte.
3. **`gwsa add`** : après connexion réussie, sonde API légère ; si
   `403 …use project` → afficher la commande gcloud exacte (ne jamais
   l'exécuter).
4. **Docs** : fait le 2026-07-22 — `docs/setup-oauth.md` §7 intègre l'étape
   au flux, README et CLAUDE.md pointent, dépannage du protocole E2E à jour.

**Décision (à re-challenger si multi-poste)** : pas de liste d'adresses
persistée comme source de vérité — dans le repo elle serait une fuite de vie
privée (cf. 41da931), hors repo un second état qui dérive. L'état réel
(profils connectés + IAM policy) suffit, `status` compare les deux ; la
liste n'est élicitée qu'au moment des gestes.

## Critères d'acceptation

- [ ] `provision-gcp.sh status` liste les comptes connectés **sans** rôle
      `serviceUsageConsumer` et affiche la commande de remédiation par compte.
- [ ] `gwsa add` détecte le 403-projet après connexion et affiche la
      commande gcloud exacte, sans l'exécuter.
- [ ] Un LLM guidant l'init (Claude Desktop/Code) peut dérouler toute la
      chaîne en ne demandant à l'humain que : les adresses, et l'exécution
      des commandes proposées.
- [ ] `scripts/test.sh` : le message de remédiation 403 est couvert par un
      cas hermétique (sortie simulée de gws).

## Notes

- Découvert par le premier run de `tests/manuels/drive-2-comptes` — le test
  manuel a payé dès sa première exécution.
- Voir `docs/setup-oauth.md` §7 ; erreur type dans la table de dépannage du
  protocole E2E.
- Piste écartée : `GOOGLE_WORKSPACE_PROJECT_ID` vide ne neutralise pas le
  quota project (testé) ; pas de flag `--project` par commande dans gws 0.22.5.
