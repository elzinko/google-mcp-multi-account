# Politique de sécurité

Ce projet donne à des agents LLM un accès à des comptes Google personnels.
C'est précisément pour ça qu'il est construit autour d'une idée simple :
**le LLM ne peut jamais élargir son propre accès**. Il sait *demander*
(élicitation) ; seul un humain ouvre.

Ce document résume ce qui est en place, ce qui ne l'est pas encore, et comment
signaler un problème. Le modèle de menace complet (surfaces de confiance,
garanties phase par phase) : [docs/threat-model.md](docs/threat-model.md).

## Ce qui est en place

| Mesure | Concrètement |
|---|---|
| **Default-deny par service** | Un service absent de la policy d'un profil est refusé. Un compte connecté via `gwsa add` démarre avec une policy prudente (zones Drive vides, pas d'envoi Gmail — même via le CLI). |
| **Aucun tool d'envoi** | Les tools MCP Gmail s'arrêtent au **brouillon**. Aucun tool n'envoie de mail ni ne supprime définitivement. |
| **Écriture Drive zonée** | `drive_create` n'écrit que sous des dossiers autorisés — en permanent (policy) ou en temporaire (grants, qui **expirent**, 8 h par défaut). |
| **Verrous par compte** | Un profil verrouillé refuse tout accès aux données, en CLI comme via MCP, jusqu'à un `unlock` humain (temporaire par défaut). Seule métadonnée qui reste lisible : l'email du compte, pour le diagnostic (`setup_status`). |
| **Touch ID** | `gwsa strongauth on` exige une preuve de présence physique (Touch ID / mot de passe macOS) pour `unlock`, `grant` et `add`. |
| **Élicitation, pas exécution** | Le tool `access_request` renvoie **la commande que l'humain doit exécuter** — il n'exécute jamais rien lui-même. |
| **Tokens chiffrés** | Chaque profil stocke un `credentials.enc` (AES-256-GCM, chiffrement du CLI `gws`), clé maître dans le **Trousseau macOS**. Rien de sensible dans le repo (`.gitignore`). |
| **Broker loopback** | Les appels de données MCP passent par un broker local (`127.0.0.1`, jeton dédié) qui **re-vérifie** verrou et policy avant chaque exécution de `gws`. |
| **Journal d'audit** | Chaque appel autorisé — et chaque refus de policy — est tracé dans `usage.jsonl` avec le client émetteur (`GWSA_CLIENT`). |
| **CI** | Syntaxe bash/Python/Node, `shellcheck`, et suite de tests hermétique (aucun compte réel, aucun réseau) sur chaque PR touchant du code (les changements purement documentaires ne déclenchent pas la CI, par frugalité). |

## Ce qui n'est **pas** (encore) garanti

L'honnêteté fait partie du modèle :

- **Un agent avec shell libre peut contourner la gateway** en appelant `gws`
  directement sur les fichiers de credentials. L'élicitation contrôle le
  comportement *coopératif* ; elle ne retire pas la *capacité*. Mitigation :
  restreindre le shell de l'agent (pas de `gws` nu, pas d'accès à
  `~/.config/gws-accounts/`) — voir [docs/threat-model.md](docs/threat-model.md).
  La parade définitive est prévue : un coffre local (vault) qui met les
  credentials hors de portée de l'agent.
- **Un profil sans `policy.json`** (créé avant le durcissement des policies)
  n'est pas filtré du tout : lui poser une policy via l'admin ou `gwsa policy`.
- **Le journal est un outil de debug, pas une identité forte** : le champ
  `GWSA_CLIENT` est déclaratif, donc falsifiable — et les refus pour verrou n'y
  figurent pas encore (seuls les appels autorisés et les refus de policy sont
  tracés).
- **L'admin web (`127.0.0.1:4877`) n'a pas d'authentification propre** : elle
  fait confiance à la session macOS locale.

## Signaler une vulnérabilité

- De préférence : un **[Security Advisory GitHub](https://github.com/elzinko/google-mcp-multi-account/security/advisories/new)**
  (rapport privé — nécessite que le *Private vulnerability reporting* du repo
  soit actif ; si le lien renvoie un 404, utiliser le mail).
- Sinon : un mail à **thomas.couderc@gmail.com** avec `[SECURITY]` en objet.

Merci de ne pas ouvrir d'issue publique pour une faille exploitable. Projet
personnel maintenu sur temps libre : réponse sous quelques jours, sans SLA.

## Périmètre

Seule la dernière version de `main` est supportée. Les dépendances de
confiance : le CLI officiel [`gws`](https://github.com/googleworkspace/cli)
(tokens, appels API) et macOS (Trousseau, Touch ID).
