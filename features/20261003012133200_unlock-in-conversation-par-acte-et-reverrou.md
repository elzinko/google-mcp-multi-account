---
id: "20261003012133200"
title: Consentement Gmail en conversation — accord par acte par défaut (au lieu de 60 min) + re-verrouillage
type: feature
priority: P2
product: google-multi-account
version:
epic: 0082
status: idea
ready:
pr:
created: 2026-10-03
---

## En clair

Pour agir sur Gmail depuis le chat, il faut déverrouiller le profil. Aujourd'hui ce
déverrouillage s'ouvre **pour 60 minutes** par défaut — un blanc-seing de durée, alors que
le modèle transactionnel veut **un accord par acte**. Et rien ne permet de **re-verrouiller**
depuis la conversation : le grant traîne jusqu'à expiration.

## Contexte / problème

Constaté le 2026-10-03 (test gmail-cleanerz).

Pour lire ou étiqueter Gmail depuis le chat, `session_unlock_in_conversation` déverrouille
le profil avec `minutes = 60` par défaut. C'est le modèle « déverrouillage par durée » —
celui que le mode transactionnel devait remplacer par un consentement **par acte**
(`grant_scope=once` par défaut, « session » en opt-in explicite).

Portée réelle, à nommer dans la fiche : ce déverrouillage est attaché à la **session de
conversation**, pas au poste entier. Un autre process — le CLI gmail-cleanerz, session
séparée — n'en profite pas. Il reste malgré tout plus large que « par acte », et il
**expire seul** faute d'un moyen de refermer.

Manque aussi : **aucun outil in-conversation pour re-verrouiller / fermer** la session côté
google-multi-account. (whatsapp-mcp expose un `session_close` ; pas celui-ci.)

## Proposition

- Par défaut, le chemin Gmail *en conversation* demande un accord **par acte** (lecture,
  pose de libellé), aligné sur `grant_scope=once` — pas un déverrouillage de 60 min.
- Le « pour la session » reste possible, mais en **choix explicite** (cf. fiche sœur
  « deux boutons »), jamais le défaut.
- Ajouter un outil in-conversation pour **re-verrouiller / fermer** la session (réduire est
  toujours permis, sans geste supplémentaire).

## Critères d'acceptation

- [ ] Un acte Gmail en conversation (lecture ou libellé) demande un accord par acte par
      défaut, sans ouvrir 60 min.
- [ ] « Pour la session » n'est atteint que par choix explicite.
- [ ] Un outil in-conversation referme la session (ou re-verrouille le profil) sans
      consentement supplémentaire.
- [ ] Test manuel (vrais comptes, Touch ID) : deux actes → deux gestes par défaut ; après
      « session » → un seul geste ; re-verrouillage effectif.

## Comment vérifier

Depuis une conversation, poser un libellé sur un mail, puis un second : par défaut, deux
gestes Touch ID. Choisir « pour la session » : le second passe sans geste. Appeler l'outil
de fermeture : le profil est re-verrouillé tout de suite.

## Notes

Lié à l'épic 0082 et à :
[ADR-0013 — consentement une fois / session](../docs/adr/ADR-0013-consentement-une-fois-ou-session.md)
[Popup Touch ID à deux boutons « Une fois / Pour la session »](20260922221816747_popup-swift-deux-boutons-portee.md)

Découvert en testant gmail-cleanerz (session 2026-10-03). Le déverrouillage 60 min n'atteint
pas le CLI cleanerz (sessions séparées) : côté cleanerz, c'est le « bootstrap headless »
(fiche 0076), un problème distinct.

Concrètement : `minutes` par défaut dans `session_unlock_in_conversation`, et absence de
`session_close` pour google-multi-account.
