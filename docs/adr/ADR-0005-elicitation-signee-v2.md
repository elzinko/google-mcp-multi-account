# ADR-0005 — Élicitation signée v2 (fiche 0001)

**Date** : 2026-07-28  
**Statut** : accepté (implémentation locale gwsa ; second consommateur whatsapp-group-mcp#0007 non requis pour le chemin macOS)

> **TL;DR** — **Quand le mode strongauth est activé** (`gma strongauth on`), chaque action sensible (débloquer un accès, ouvrir un dossier partagé, approuver un projet) doit être validée par une empreinte Touch ID qui **signe cryptographiquement** la description de cette action précise — au lieu de l'ancien contrôle qui vérifiait seulement qu'un humain était présent — pour qu'une approbation ne puisse ni être rejouée ni servir à autoriser une autre action.

## Contexte

`gwsa strongauth` v1 = presence check (`touchid.swift`). La fiche 0001 exige un
consentement **lié cryptographiquement** à l'action (unlock, grant, manifeste projet).

## Décision

1. **Payload canonique unique** (`gateway/elicitation.py`) : `action`, `alias`,
   `target`, `session_id`, `minutes`/`hours`, `nonce`, `issued_at`, `expires_at`.
   Le helper Swift dérive le prompt Touch ID **et** signe le JSON canonique
   (SHA-256 + ECDSA P-256).
2. **Clé** : enrôlement `gwsa elicitation enroll` tente dans l'ordre Secure Enclave
   → Keychain logiciel → **fichier** `~/.config/gws-accounts/.elicitation/private.p256`
   (0600) + `public.der`. Le repli fichier est requis parce que `swift script.swift`
   non codesigné reçoit souvent `errSecMissingEntitlement` (-34018) en créant une
   clé permanente Keychain/SE. La clé publique reste hors repo (dir mode 700).
3. **Reçus** : `~/.config/gws-accounts/.elicitation/receipts.jsonl` + entrées
   `decision=elicitation` dans `usage.jsonl`. Anti-rejeu : `nonces.json`.
4. **Tests CI / Linux** : `GWSA_ELICITATION_MOCK=1` + `gwsa elicitation enroll --mock`
   (HMAC-SHA256, pas de Swift).
5. **Mutualisation** : copie locale dans ce repo pour l'instant ; extraction vers
   brique partagée quand whatsapp-group-mcp#0007 sera livré et les deux usages
   réels validés (pas de sur-abstraction avant).

## Repli (fail closed)

- `strongauth on` sans enrôlement → refus avec message `gwsa elicitation enroll`.
- Biométrie indisponible (helper exit 2) → refus, jamais d'accord silencieux.
- Pas de fallback vers le simple presence check quand strongauth est activé.
- Mode fichier : Touch ID (`LAContext`) **avant** chaque signature ; le reçu reste
  lié au payload (ECDSA). La clé privée fichier est lisible par le même UID
  (même classe de menace que le vault actuel — fiche 0001 § trou n°2).

## Limites (inchangées)

- Contournement `gws` nu / édition FS : orthogonal (fiche 0001 § trou n°2).
- Vérification au moment de la commande humaine `gwsa` ; le broker fait confiance
  au registre session une fois l'humain passé.
- Helper non codesigné : pas de SE « hard » tant qu'on n'embarque pas un binaire
  signé avec entitlements Keychain (évolution possible).

## Références

- `scripts/elicitation-sign.swift`, `gateway/elicitation.py`, `bin/gwsa`
- Fiche 0001, whatsapp-group-mcp#0007 (conception miroir, non bloquante pour ce chemin)
