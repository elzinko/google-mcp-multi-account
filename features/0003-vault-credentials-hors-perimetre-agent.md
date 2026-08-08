---
id: 0003
title: Vault credentials hors périmètre agent (Phase 2.1)
type: feature
priority: P3
version:
epic:
status: idea
ready:
pr:
created: 2026-07-21
---

## Contexte / Problème

La Phase 2 « rapide » (broker daemon + `gws` interne, socket loopback) centralise
les appels mais **ne retire pas** la capacité d’un agent avec shell + filesystem
d’appeler `gws` avec `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` pointant sur
`~/.config/gws-accounts/<alias>/`. Les tokens restent lisibles/utilisables hors
broker. Pour une non-confiance réelle envers un LLM adversaire local, il faut un
**vault** : credentials inaccessibles au processus agent.

Recoupe l’intention de [0002](0002-durcir-modele-policy-default-deny.md) § « garantie
dure hors wrapper », sans la dupliquer : 0002 = policy defaults ; **celle-ci = isolement
des secrets**.

## Proposition

Après le broker Phase 2 A (daemon + RPC) :

- Déplacer ou encapsuler `credentials.enc` / secrets hors du répertoire lisible
  par l’agent (dir dédié permissions strictes, user séparé, ou trousseau réservé
  au process broker).
- L’agent n’a plus de chemin utile vers `gws` + tokens ; seule la socket broker
  reste ouverte.
- Documenter le modèle de menace mis à jour (Phase 2.1).

## Critères d'acceptation

> **Réconciliation (2026-08-08).** Relocalisation **partielle** atterrie via #49 :
> `gateway/vault.py` déplace les creds vers `.vault/<alias>/`. Mais c'est un dossier
> `0700` **au même UID** — un agent avec shell peut encore le lire ;
> `docs/threat-model.md` + `SECURITY.md` listent d'ailleurs le vault comme
> « prévu ». Aucun critère ci-dessous n'est rempli : l'isolement **dur**
> (user/keychain séparé) reste à construire. Fiche valide, `idea` P3.

- [ ] Un process « agent » (même UID sandboxé ou sans droit de lecture vault) ne
      peut pas obtenir un access token Google ni invoquer `gws` utilement
- [ ] Le broker continue de servir MCP / gwsa pour les opérations autorisées
- [ ] Migration documentée depuis le layout `~/.config/gws-accounts/` actuel
- [ ] Tests d’acceptation (refus d’accès vault + happy path broker)

## Notes

- Décision produit 2026-07-21 : Phase 2 **A** d’abord (rapide) ; **cette fiche =
  B / plus tard** (`idea`, P3).
- Ne pas démarrer tant que le broker A n’est pas shippé et utilisé en conditions réelles.
- Anti-doublon : pas équivalent à 0001 (élicitation signée) ni au default-deny de 0002.
