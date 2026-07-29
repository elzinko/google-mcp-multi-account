# Test E2E — `gwsa grant` résout un dossier par nom (ZZ-TESTS)

Ce test prouve que la commande :
`gwsa grant <alias> ZZ-TESTS <heures>`
arrive à résoudre le dossier **par son nom** (pas seulement via l'ID),
et évite l'erreur historique :
`dossier « ZZ-TESTS » introuvable ou ambigu — donne son ID`.

## Comptes

- `perso` : compte source A (Thomas Couderc)
- `mw` : compte destination B (matiereweb@…)

## Prérequis (humain)

1. Dans le Drive de **chaque** compte, avoir un dossier `ZZ-TESTS` à la racine
   (nom exact, un seul exemplaire).
2. S'assurer que `perso` et `mw` sont connectés (`gwsa list`).
3. Si strongauth est activé (Touch ID requis), accepter les prompts pendant
   les phases `unlock/grant` (ici le LLM guide, l'humain exécute).

## Outils MCP utilisés (si disponibles)

Ce test ne dépend pas des tools MCP : il vérifie principalement le wrapper
`gwsa` (résolution dossier par nom + signature élicitation).

## Déroulé

### Phase 0 — état des lieux (lecture)

1. Vérifier que le dossier existe bien dans chaque compte, en récupérant
   l'ID via :

   ```bash
   gwsa perso drive files list --params '{"q":"name=\"ZZ-TESTS\" and mimeType=\"application/vnd.google-apps.folder\" and trashed=false","fields":"files(id,name)"}'
   gwsa mw drive files list --params '{"q":"name=\"ZZ-TESTS\" and mimeType=\"application/vnd.google-apps.folder\" and trashed=false","fields":"files(id,name)"}'
   ```

2. Noter les deux `folderId` (ID) retournés par l'API (un par compte).

### Phase 1 — élicitation « unlock » (si nécessaire)

Tenter une commande sensible (au besoin) :

```bash
gwsa unlock perso 30
gwsa unlock mw 30
```

Si un profil était verrouillé : exécuter `unlock` jusqu'à pouvoir relancer
les phases suivantes.

### Phase 2 — grant par nom (le point à tester)

Pour chaque compte, exécuter (en utilisant les prompts d'élicitation si strongauth) :

```bash
GWSA_CLIENT=claude-code gwsa grant perso ZZ-TESTS 1
GWSA_CLIENT=claude-code gwsa grant mw ZZ-TESTS 1
```

**Succès attendu :**
- aucune erreur du type `dossier « ZZ-TESTS » introuvable ou ambigu ...`
- `gwsa grants <alias>` affiche une autorisation temporaire active (avec ID).

### Phase 3 — vérification

```bash
gwsa grants perso
gwsa grants mw
```

Vérifier que l'entrée correspond bien au `folderId` noté en Phase 0.

### Phase 4 — contrôle négatif (assertion)

```bash
gwsa grant perso ZZ-TESTS-INCORRECT 1
```

Succès attendu : l'opération échoue (barrière correcte), et le message
contient `introuvable ou ambigu`.

### Phase 5 — nettoyage réversible (optionnel)

Révoquer les grants temporaires (sans modifier la policy permanente) :

```bash
gwsa grant perso revoke <folderId_perso>
gwsa grant mw revoke <folderId_mw>
```

## Critères de réussite

- `gwsa grant perso ZZ-TESTS 1` et `gwsa grant mw ZZ-TESTS 1` réussissent
  (ou au minimum passent la phase de résolution par nom — pas de message
  « introuvable/ambigu »).
- Les contrôles négatifs échouent comme attendu.
