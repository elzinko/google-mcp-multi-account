---
id: 0001
title: Élicitation signée — faire monter `gwsa strongauth` de la présence à la signature
type: feature
priority: P3
version:
epic:
status: idea
ready:
pr:
created: 2026-07-20
---

## Contexte / Problème

`gwsa strongauth` est livré (2026-07-19) : `scripts/touchid.swift` +
`require_strong_auth()`, appelé avant `gwsa unlock` et `gwsa grant`. C'est un
**presence check** — `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`, exit 0/1.

Ce qu'il garantit : au moment du déverrouillage ou de l'autorisation d'une zone Drive,
**un humain était physiquement devant le Mac**. Un LLM ne peut pas fabriquer ce verdict.

Ce qu'il ne garantit **pas** — deux trous distincts, à ne pas confondre :

1. **Aucune liaison entre le doigt et la question.** La raison affichée dans le prompt
   est une simple chaîne passée par l'appelant ; rien ne lie cryptographiquement le
   consentement à *cette* action précise. Le verdict est un booléen consommé par le code
   appelant, qui reste juge de ce qu'il en fait. Il ne reste aucune trace vérifiable
   après coup.
2. **Le contrôle vit dans le wrapper.** Tout l'édifice (verrous, policy, zones) est
   appliqué par `bin/gwsa`. Un agent disposant du shell peut appeler `gws` nu avec
   `GOOGLE_WORKSPACE_CLI_CONFIG_DIR=…` et **tout contourner**, Touch ID compris. Limite
   assumée et documentée (README, § policy), mais **l'élicitation signée ne la corrige
   pas** — c'est un problème orthogonal, peut-être plus pressant.

## Proposition

Faire monter la v1 d'un cran : consentement **scellé par une signature à présence
physique** — clé privée en Secure Enclave (elle n'en sort jamais), défi (nonce +
hachage de la question datée), signature gardée par Touch ID, vérification côté
appelant, **fail closed**, reçu journalisé.

La conception détaillée existe déjà et ne doit pas être réinventée ici : voir la fiche
**`0007-elicitation-signee-touch-id.md` du projet `whatsapp-group-mcp`**
(`/Users/elzinko/git/bacasable/whatsapp-group-mcp/features/`), en particulier ses
**4 décisions de conception** — signe-ce-que-tu-affiches (un seul payload canonique
dont le helper dérive le prompt *et* signe le hachage) · garde-fou dans la clé
(`biometryCurrentSet` / `userPresence`, pas « evaluatePolicy puis signe ») · emplacement
de la clé publique hors du répertoire éditable par l'agent + journal de reçus · repli
tranché explicitement.

Périmètre pressenti **ici** : les deux points d'élicitation existants, `unlock` et
`grant` (Drive). Rien d'autre pour l'instant.

## ⛔ Dépendance bloquante — ne rien démarrer avant

**Tant que la fiche 0007 de `whatsapp-group-mcp` n'est pas faite ET testée en conditions
réelles, on ne bouge pas ici.** Ce projet est le **second consommateur**, pas le
pionnier : il récupère un mécanisme éprouvé, il ne le défriche pas. Toute avance prise
ici serait du travail à refaire.

Signal de déblocage : 0007 `shipped`, avec un retour d'expérience réel (le doigt de
Thomas, pas seulement les tests à clé logicielle).

## Questions ouvertes (à trancher au grooming, une fois débloquée)

1. **Mutualisable ?** Le helper Swift + le protocole défi/vérification servent déjà deux
   projets. Brique partagée (un binaire + une lib de vérification) ou copie assumée dans
   chaque projet ? Ne pas sur-abstraire avant d'avoir **deux usages réels qui tournent** —
   ce qui sera précisément le cas à ce moment-là.
2. **Projet indépendant ?** Si mutualisation : repo dédié, package, ou simple dossier
   partagé ? Qui porte l'enrôlement (une clé pour tout l'écosystème = un seul doigt) ?
3. **Ça existe déjà ailleurs ?** ✅ *Recherché le 2026-07-20* (audit multi-agent, 3 angles :
   MCP, Secure Enclave, WebAuthn). **Verdict : construire soi-même, ~100-200 lignes, en
   assemblant des pièces éprouvées — rien à réutiliser tel quel, et c'est la seule voie
   compatible 100 % local.** L'écosystème se scinde en deux familles étanches, aucune ne
   couvre le besoin :
   - **Boutons d'approbation** (HumanLayer/Agent Control Plane, gotoHuman, VantaGate,
     serveurs MCP « human-in-the-loop ») : UX + log d'audit, **zéro preuve cryptographique**.
     Le HMAC de VantaGate prouve que *le service* a émis la décision, pas qu'un *humain* a
     signé *cette* question — approbation par magic-link, rejouable si le lien fuit. Le plus
     proche en marketing, le plus trompeur.
   - **Crypto de non-répudiation agentique** (Signet — Ed25519 + JSON canonique RFC 8785 +
     nonce + chaînage ; SMCP/RFC 9421 ; open-agent-auth) : toute la mécanique voulue existe,
     **mais le signataire est l'agent ou l'IdP, jamais l'humain**. À réutiliser comme *format
     de reçu*, en remplaçant la clé agent par une clé matérielle humaine.
   - La jonction exacte (geste physique humain → signature sur le hash de la question) n'est
     standardisée QUE dans le paiement (W3C Secure Payment Confirmation + WebAuthn, Google
     AP2 Cart Mandate) et en produit d'entreprise fermé (Yubico+Delinea Role Delegation Token
     — annonce partenaire, ni spec ni code publics, inexploitable). **Aucun SEP MCP ne comble
     ce trou** ; l'élicitation renvoie sa réponse en clair, non signée.

   **Piste ZÉRO-CODE à prototyper en premier (~30 min, tout est déjà là — M-series, Touch ID,
   OpenSSH ≥ 9.9)** : `sc_auth create-ctk-identity -k p-256-ne -t bio` crée une clé Secure
   Enclave gardée par la biométrie ; puis `ssh-keygen -Y sign -n <namespace> question.json`
   produit un **reçu SSHSIG armuré**, et `ssh-keygen -Y verify` + `allowed_signers` le vérifie.
   Liaison à une question arbitraire native (namespace + hash du payload), signataire = clé
   matérielle humaine, vérification hors-ligne. Si ce chemin tient, il remplace le helper Swift
   ET le protocole de vérification maison — à confronter à l'option Swift au grooming.
   *(Le mode `url` de l'élicitation MCP reste le point d'accroche UX : une page locale qui
   déclenche la signature et renvoie l'assertion. NB : la révision MCP 2026-07-28 remplace
   l'élicitation par les Multi Round-Trip Requests / SEP-2322 — cibler ça pour ne pas bâtir
   sur une API en fin de vie.)*
4. **Où vit la vérification ?** `gwsa` est du bash ; `scripts/policy-check.py` montre que
   Python 3 est déjà dans la boucle. Vérifier une signature ECDSA en Python vs déléguer au
   helper Swift lui-même (mode `verify`) — à trancher.
5. **Et le trou n°2 ?** Le contournement par `gws` nu mérite-t-il sa propre fiche ? Sans
   réponse, l'élicitation signée durcit une porte pendant qu'une autre reste ouverte.

## Critères d'acceptation

*(esquisse — à compléter au grooming, une fois 0007 livrée et les questions ci-dessus
tranchées ; ne pas passer le gate `ready` en l'état)*

- [ ] `gwsa unlock` et `gwsa grant` exigent une **signature fraîche** liée à l'action
      exacte (alias + action + cible + date), pas un simple booléen de présence
- [ ] Rejeu refusé (nonce) ; question modifiée = signature invalide (hachage)
- [ ] Reçus signés journalisés (au minimum dans `usage.jsonl`, aux côtés des décisions
      policy déjà tracées)
- [ ] Repli documenté en cas d'absence de biométrie ; jamais d'accord silencieux
- [ ] Décision tracée (ADR ou note) sur la mutualisation retenue

## Notes

- **État de l'art interne à reprendre** : `scripts/touchid.swift` (~25 lignes,
  `.deviceOwnerAuthentication`), `gwsa strongauth on|off|status` (drapeau
  `~/.config/gws-accounts/.strong-auth`), `require_strong_auth()` dans `bin/gwsa`.
  Même dépendance (LocalAuthentication), même contrainte de compilation (`swiftc`, pas
  de Xcode requis) — il manque la signature et la liaison à la question.
- **Verdict déjà acquis (2026-07-19)** : pas de « plugin Claude Desktop ». Desktop
  consomme des serveurs MCP ; l'« extension » `.mcpb`/`.dxt` n'est qu'un emballage
  d'installation, sans API ni garantie supplémentaire. Le cérémonial vient de toute
  façon d'un helper natif local — l'architecture retenue marche donc à l'identique sous
  tous les clients.
- **Dépendance externe** (exigence DoR) : la fiche 0007 vit dans `whatsapp-group-mcp`,
  hors de ce repo. Avant de passer le gate `ready`, poser ici une ligne datée
  « dépendance whatsapp-group-mcp#0007 — état constaté le AAAA-MM-JJ ».
