# Backlog features & bugs — google-mcp-multi-account

> Index auto-généré (`regen-backlog.sh` mega-city, via `/ezk-backlog regen`) — **ne pas éditer à la main**. Source de vérité = le front-matter de chaque fiche.
> 1 fiche / sujet · 1 PR / feature · backlog commité sur `main`. Statuts : 💡 idea · 🔴 todo · 🟠 in-progress · ⛔ blocked · ✅ shipped.

| # | Titre | Type | Prio | Statut | PR |
|---|-------|------|------|--------|----|
| 0004 | Broker daemon local Phase 2 A — gws derrière socket loopback | feature | P1 | ✅ shipped | 12114ac |
| 0005 | Onboarding des comptes — chaîne complète élicitée (IAM compris), drift visible | feature | P1 | ✅ shipped | #5 |
| 0012 | Panneau « Santé du setup » + bouton « Réparer l'accès IAM » dans l'admin | feature | P1 | ✅ shipped | #14 |
| 0014 | Journaliser les refus de verrou dans usage.jsonl (decision:refus, reason:locked) | bug | P1 | ✅ shipped | #17 |
| 0002 | Durcir le modèle de policy — décisions « default-deny » soulevées par l'audit | feature | P2 | ✅ shipped | #12 |
| 0007 | Provisioning GCP idempotent/déclaratif — durcir provision-gcp.sh ou passer à Terraform | feature | P2 | ✅ shipped | #10 |
| 0008 | Connexion dynamique d'un nouveau compte via élicitation forte (access_request kind=add_account) | feature | P2 | ✅ shipped | #7 |
| 0009 | Tool MCP `setup_status` (lecture seule) + `provision-gcp.sh status --json` | feature | P2 | ✅ shipped | #11 |
| 0010 | README en quickstart 3 étapes — le détail part dans docs/ | feature | P2 | ✅ shipped | #13 |
| 0011 | `gwsa admin` — démarrer/arrêter l'interface web en un geste, proposé par l'élicitation | feature | P2 | ✅ shipped | #9 |
| 0013 | Brancher le serveur MCP dans Claude Desktop en un geste (script idempotent) | feature | P2 | ✅ shipped | #15 |

## 💡 Idées (non groomées)

| # | Titre | Type | Prio | Statut | PR |
|---|-------|------|------|--------|----|
| 0006 | Harnais hybride pour les tests manuels — script pour la mécanique, LLM pour la glu | feature | P2 | 💡 idea |  |
| 0001 | Élicitation signée — faire monter `gwsa strongauth` de la présence à la signature | feature | P3 | 💡 idea |  |
| 0003 | Vault credentials hors périmètre agent (Phase 2.1) | feature | P3 | 💡 idea |  |

> Livrées (`done/`) : 0002, 0004, 0005, 0007, 0008, 0009, 0010, 0011, 0012, 0013, 0014.
