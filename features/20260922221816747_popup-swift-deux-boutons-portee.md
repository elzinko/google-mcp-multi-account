---
id: "20260922221816747"
title: Popup Touch ID à deux boutons « Une fois / Pour la session » (ergonomie du geste)
type: feature
priority: P2
product: google-multi-account
version:
epic: 0082
status: idea
ready:
pr:
created: 2026-09-23
---

## En clair

Le geste « une fois / pour la session » marche déjà (ADR-0013, #150). Mais aujourd'hui la
portée se choisit via un **paramètre** (`grant_scope`) que le LLM relaie ; l'humain la
**confirme** en lisant le texte du popup Touch ID. Cette fiche ajoute le vrai geste de Claude
Code : **deux boutons dans le popup** — « Une fois » et « Pour la session » — pour que
**l'humain choisisse la portée au moment de poser le doigt**, sans dépendre du LLM.

## Contexte / problème

ADR-0013 a livré la portée comme un **champ signé** (`grant_scope`), threadé depuis l'appel
jusqu'au payload signé et au texte du popup. Le popup Swift (`scripts/elicitation-sign.swift`)
**affiche** la portée mais ne la **fait pas choisir**. C'était un choix assumé (POC d'abord) :
les boutons natifs sont l'aboutissement ergonomique, différés à cette fiche.

**Point technique à groomer.** Aujourd'hui `grant_scope` entre dans le payload **avant** la
signature (le LLM le propose, puis Touch ID signe). Si l'humain choisit au popup, son choix
doit entrer dans le payload **signé** — donc le flux doit changer : le popup renvoie le choix,
**puis** on signe. À cadrer avec `gateway/elicitation.py` (ordre payload → geste → signature).

## Proposition

- Le popup Touch ID présente **deux boutons** pour un acte éligible (mutation Drive non-partage,
  mode manuel) : **« Une fois »** (défaut) / **« Pour la session »**.
- Le **choix humain** devient la portée effective et signée (le LLM peut toujours proposer via
  `grant_scope`, mais l'humain tranche au doigt).
- Garde-fous inchangés (ADR-0013) : le **partage** n'a jamais le bouton « session » ; hors
  éligibilité (mode auto, catégorie non whitelistée, sous-session déléguée), pas de bouton →
  « une fois » forcé.

## Critères d'acceptation

- [ ] Popup à 2 boutons pour un acte éligible (mutation Drive, mode manuel).
- [ ] Le choix « session » écrit la grâce (2ᵉ acte même dossier sans geste) ; « une fois » non.
- [ ] Partage / mode auto / catégorie non éligible : aucun bouton « session » (once forcé).
- [ ] Le **payload signé** reflète le choix **humain** (pas seulement le paramètre du LLM).
- [ ] Parité de rendu + test manuel (vrais comptes, Touch ID).

## Comment vérifier

Test manuel (vrais comptes) : écrire dans un dossier, choisir **« Pour la session »** au popup
→ la 2ᵉ écriture dans le même dossier passe sans geste. Tenter un partage → **aucun** bouton
« session ». Basculer en mode auto → pas de bouton « session ».

## Notes

- Suite directe d'[ADR-0013](../docs/adr/ADR-0013-consentement-une-fois-ou-session.md) — le
  « reste différé assumé » y est nommé. Épic 0082.
- Touche surtout `scripts/elicitation-sign.swift` (UI native + retour du choix) et le flux de
  signature `gateway/elicitation.py` (le choix humain doit entrer dans le payload signé).
