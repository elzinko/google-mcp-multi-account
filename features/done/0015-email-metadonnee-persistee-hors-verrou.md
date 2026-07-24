---
id: 0015
title: Email de profil = métadonnée persistée (.email) — zéro exécution gws hors broker
type: refactor
priority: P1
version:
epic:
status: shipped
ready: 2026-07-24
pr: "#18"
created: 2026-07-24
---

## Contexte / Problème

Le tool MCP `setup_status` exécutait `gws auth status` sur un profil **même
verrouillé** pour récupérer son email (`gateway/profiles.py::_profile_email`,
subprocess direct avec `GOOGLE_WORKSPACE_CLI_CONFIG_DIR`) — précisément le
motif que le threat model interdit et **hors du broker**, dont le contrat est
« seul process qui exécute gws ». En pratique cette branche ne s'exécutait
*que* pour les profils verrouillés (`list_profiles` ne lit l'email que si
déverrouillé), d'où une incohérence : `profiles_list` masquait l'email des
profils verrouillés, `setup_status` l'affichait.

Deux options étaient sur la table : (a) assumer l'exception (posture déjà
écrite dans SECURITY.md : « Seule métadonnée qui reste lisible : l'email »)
et passer par le broker ; (b) aligner `setup_status` sur `profiles_list`
(pas d'email si verrouillé) — au prix du diagnostic IAM et de la commande de
remédiation exactement dans la posture recommandée (profils verrouillés).

## Proposition

Trancher par une troisième voie qui garde le résultat de (a) avec un
mécanisme plus sûr ([ADR-0002](../../docs/adr/ADR-0002-email-metadonnee-hors-verrou.md)) :
l'email devient une **métadonnée persistée en clair** (`<profil>/.email`),
écrite par les gestes humains (`gwsa add`, backfill par `gwsa list` et
l'admin), et lue par toutes les surfaces. La gateway n'exécute **plus jamais
gws** pour l'obtenir — verrouillé ou non.

## Critères d'acceptation

- [x] `gwsa add` écrit `.email` ; `gwsa list` / l'admin backfillent les
      profils existants au premier passage.
- [x] `profiles_list` **et** `setup_status` montrent l'email d'un profil
      verrouillé (cohérents entre eux), sans exécuter gws.
- [x] Le check IAM et la commande de remédiation de `setup_status` restent
      disponibles pour un profil verrouillé (onboarding guidé préservé).
- [x] Invariant testé : aucun `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` dans
      `gateway/` hors `broker_server.py`.
- [x] Profil sans `.email` : email vide, IAM « unknown », `next_actions`
      suggère `gwsa list` ; un `.email` au contenu non-email est ignoré.

## Notes

- Décision : [ADR-0002](../../docs/adr/ADR-0002-email-metadonnee-hors-verrou.md) ;
  threat model mis à jour (section « Email = métadonnée d'identité »).
- La phrase de SECURITY.md (« Seule métadonnée qui reste lisible : l'email »)
  reste vraie telle quelle — seul le mécanisme change.
