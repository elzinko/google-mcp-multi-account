---
id: 0073
title: Drive — transfert de propriété (drive_permissions_create transfer_ownership)
type: feature
priority: P2
version:
epic: 0017
status: idea
ready:
pr:
created: 2026-08-03
---

## Contexte / Problème

La PR #77 (grant par nom + surface MCP Drive : update, partage, permissions) a
livré les parties solides, mais le **transfert de propriété** en a été **retiré**
et **refusé** par le serveur (voir `drive_permissions_create`, message « fonction
déplacée dans une PR dédiée »). Cette fiche porte sa reprise.

Pourquoi c'était sorti (revue sécurité indépendante + revue Codex de #77) :

- **Destructif** : donner un fichier = irréversible côté produit.
- **Garde de sécurité insuffisante (F2)** : partage **et** transfert ne sont
  gardés que par le flag **persistant** `drive.share:true` — pas par les zones ni
  par un grant de session. Une fois `share` activé, l'agent peut partager/
  transférer **tout** fichier possédé vers **tout** email (jamais public,
  `type=user`). Le « confirmer avec l'humain » n'est que de la prose.
- **Flux consumer non validé** : pour des comptes @gmail.com (les comptes du
  projet), Google **refuse** un `create role=owner` direct ; il faut un
  `writer` marqué `pendingOwner` + notification, que le destinataire **accepte**
  depuis son Drive. Ce flux n'a jamais été validé sur de **vrais** comptes.

## Proposition

Reprendre le code du transfert (déjà écrit sur la branche
`feat/drive-transfer-ownership`, en **brouillon**) et le rendre livrable :

1. **Garde de sécurité (F2)** — décision produit à trancher puis implémenter :
   - exiger un **grant de session** pour partager/transférer (pas le flag
     persistant seul), et/ou restreindre aux **zones** ;
   - **Touch ID / strongauth** pour le transfert (action la plus destructive).
2. **Flux consumer** — confirmer le `pendingOwner` (writer + pendingOwner +
   notification ; `pendingOwner` dans le masque de champs) contre de **vrais**
   comptes @gmail.com, côté source **et** acceptation côté destination.
3. **Doc** — threat-model + protocole manuel (phase 7) à réactiver et corriger.

## Critères d'acceptation

- [ ] Garde de sécurité du transfert décidée et implémentée (F2) — plus de
      dépendance au seul flag persistant `drive.share`.
- [ ] Transfert validé **de bout en bout sur de vrais comptes @gmail.com**
      (invitation `pendingOwner` → acceptation → `owned_by_me` bascule).
- [ ] threat-model honnête + protocole manuel phase 7 réactivé.
- [ ] Revue Codex propre.

## Notes

- **Dépendance externe** : validation sur de vrais comptes Google @gmail.com —
  geste **humain**, non hermétique. Accès à confirmer (2 comptes du projet).
- Code de départ : branche `feat/drive-transfert-propriete` (PR brouillon), qui
  restaure ce que #77 a retiré. Rebaser sur `main` une fois #77 mergée.
- Lié : surface MCP Drive [[0021]] · écart policy/surface [[0041]].
