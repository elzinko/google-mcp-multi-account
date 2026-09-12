# ADR-0002 : L'email de profil est une métadonnée d'identité persistée — hors verrou, hors gws

**Statut :** Accepté
**Date :** 2026-07-24
**Décideurs :** Thomas (PO)

> **TL;DR** — L'adresse email de chaque compte Google connecté est désormais mémorisée dans un petit fichier texte écrit au moment de la connexion, au lieu d'être récupérée en relançant l'outil Google à chaque lecture — ainsi un compte « verrouillé » (dont l'accès aux données est bloqué tant qu'un humain ne l'a pas rouvert) peut quand même afficher son email pour le diagnostic d'installation, sans jamais faire tourner l'outil Google sur ses identifiants pendant le verrouillage.

## Contexte

Le verrou d'un profil (`.locked`) signifie « accès aux données sur demande » :
tout appel de données est refusé jusqu'à un `unlock` humain. Or `setup_status`
(fiche 0009) a besoin de l'email de **chaque** compte — verrouillé compris —
pour vérifier le rôle IAM et proposer la commande `gcloud add-iam-policy-binding`
exacte (onboarding guidé, ADR-0001).

L'implémentation initiale récupérait cet email en exécutant `gws auth status`
en subprocess direct (`GOOGLE_WORKSPACE_CLI_CONFIG_DIR=… gws …`) depuis
`gateway/profiles.py::_profile_email` :

1. **Hors broker** — dont le contrat est « seul process qui exécute gws »
   côté gateway ; et précisément le motif que le threat model demande de
   bloquer chez les agents.
2. **Sur profil verrouillé** — la branche ne s'exécutait *que* dans ce cas
   (`list_profiles` ne lit l'email que déverrouillé) : exécuter gws, c'est
   toucher aux credentials chiffrés pendant le verrou.
3. **Incohérent** — `profiles_list` masquait l'email des profils verrouillés,
   `setup_status` l'affichait.

La posture produit, elle, est déjà écrite (SECURITY.md) : « Un profil
verrouillé refuse tout accès aux données […] Seule métadonnée qui reste
lisible : l'email du compte, pour le diagnostic (`setup_status`). »

## Décision

**Assumer l'exception — l'email reste lisible profil verrouillé — mais en
changer la nature : c'est une métadonnée persistée, plus jamais le résultat
d'une exécution gws.**

- À la connexion (`mag add`, geste humain), l'email est écrit en clair dans
  `<profil>/.email`. `mag list` et l'admin backfillent les profils créés
  avant cette décision, dès qu'ils lisent un email non vide.
- Toutes les surfaces (**`profiles_list`, `setup_status`, admin, mag**)
  lisent ce fichier. La gateway ne lance plus aucun subprocess gws pour ça.
- L'invariant devient net et testable : **verrou ⇒ zéro exécution gws avec
  les credentials du profil**, et `gateway/` ne contient aucun
  `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` hors `broker_server.py` (test statique).
- Fichier absent (profil legacy) : email vide, IAM « unknown », et
  `next_actions` suggère `mag list` (le backfill est un passage humain).
  Un contenu qui n'est pas un email est ignoré (pas de confiance aveugle).

## Options considérées

### Option A — Assumer l'exception via le broker (dérogation au verrou)

| Dimension | Évaluation |
|---|---|
| Cohérence | Broker seul exécuteur : oui — au prix d'une dérogation « auth status même verrouillé » |
| Sécurité | gws s'exécute encore sur profil verrouillé (credentials touchés) |
| Complexité | Cmd broker dédiée + carve-out dans `require_unlocked` |

**Pour :** centralise et journalise l'exception. **Contre :** installe une
dérogation au verrou dans le composant le plus sensible, pour une donnée qui
n'a pas besoin d'être recalculée à chaque lecture. **Rejetée.**

### Option B — Aligner `setup_status` sur `profiles_list` (pas d'email si verrouillé)

| Dimension | Évaluation |
|---|---|
| Cohérence | Totale, par nivellement vers le bas |
| Sécurité | La plus stricte |
| UX onboarding | Cassée dans la posture recommandée : profil verrouillé ⇒ plus de check IAM ni de remédiation |

**Pour :** simple, rien à écrire. **Contre :** contredit la raison d'être de
`setup_status` (ADR-0001 : donner à Desktop la visibilité de
`provision-gcp.sh status`) et la phrase déjà publiée de SECURITY.md.
**Rejetée.**

### Option C — Métadonnée persistée `.email` (retenue)

| Dimension | Évaluation |
|---|---|
| Cohérence | Toutes les surfaces lisent la même source ; broker redevient seul exécuteur |
| Sécurité | Verrou ⇒ zéro exécution gws ; l'email est capté au geste humain `add` |
| UX onboarding | Préservée (IAM + remédiation même verrouillé) |
| Bonus | Plus de subprocess gws (timeout 15 s) par profil dans `profiles_list` |

**Pour :** livre le résultat de A avec un invariant plus fort que B ne le
demandait. **Contre :** un fichier de plus par profil + backfill des profils
existants — assumé (le dossier contient déjà `client_secret.json` en clair,
bien plus sensible qu'un email).

## Conséquences

- Devient plus simple : `setup_status` (plus de cas particulier),
  la doctrine (« le verrou bloque *toute* exécution gws »), les tests
  hermétiques (l'email se teste sans binaire gws).
- Devient plus exigeant : `.email` peut dériver si quelqu'un fait
  `gws auth login` à la main hors `mag` (chemin non supporté) — les
  passages `mag add`/`mag list` re-synchronisent.
- SECURITY.md reste vrai mot pour mot ; threat model mis à jour
  (section « Email = métadonnée d'identité »).
