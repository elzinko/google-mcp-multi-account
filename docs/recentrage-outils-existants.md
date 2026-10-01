# Recentrage — google-mcp-multi-account
### Face à msgvault, Composio, NanoClaw/OpenClaw · 2026-09-30

Note de décision. Pourquoi ce projet existe encore alors que des outils voisins existent,
et où concentrer l'effort.

## En clair
Les outils qui existent règlent un problème **voisin et plus simple** que le nôtre : brancher
ou consulter Gmail sans effort. Aucun ne fournit notre raison d'être — l'accès **souverain**,
**multi-comptes**, avec **consentement par acte** et **identité par conversation**.
Conclusion : arrêter de construire la partie « lire », garder la partie « agir sous contrôle ».
Une seule question tranche le reste.

## Le constat
- **msgvault** — archive locale, lecture seule. Plusieurs Gmail dans une base, recherche
  plein-texte, serveur MCP pour interroger. Pas d'envoi, pas d'action, pas de WhatsApp.
- **Composio** — courtier d'authentification + 500 apps. Jetons dans son cloud par défaut,
  auto-hébergeable mais lourd. Aucune notion de consentement par acte.
- **NanoClaw / OpenClaw** — coquilles multi-canal (WhatsApp par canal non officiel, 1 numéro).
  Elles acceptent un serveur MCP tiers, mais le font tourner **en conteneur**, loin du
  Secure Enclave et de Touch ID.

## Ce qu'on abandonne (ne plus construire)
La **lecture et la recherche sur l'historique** de plusieurs comptes Gmail.
msgvault le fait déjà, en local, multi-comptes, avec un MCP. Le réécrire n'apporte rien.

## Ce qu'on garde (le différenciateur — introuvable ailleurs)
- Plusieurs comptes Gmail avec **identité par conversation** (droits signés par conversation).
- **Consentement par acte** : verrou « accès sur demande », policy default-deny par service,
  grants Drive qui expirent.
- Jetons **sur l'hôte**, Touch ID / Secure Enclave, **journal d'audit local**.
- L'**écriture sous contrôle** (brouillon, envoi confirmé, écriture Drive). Le geste risqué,
  donc le geste qui mérite notre garde.

Point clé : les risques repérés — un mail piégé qui détourne l'agent, un agent qui garde le
droit d'envoyer, un contenu lu par le LLM cloud — frappent *n'importe quel* montage.
Notre couche de consentement **est** la parade. Le différenciateur n'est pas un luxe.
C'est le frein.

## Comment on brancherait msgvault
Division nette : deux serveurs MCP côte à côte, un même client (Claude Desktop/Code).
- **Consulter l'historique, chercher, analyser** → msgvault (son MCP).
- **Lire le mail qui vient d'arriver et agir dessus sous consentement** → notre serveur.

Nuance à garder : msgvault est une **archive synchronisée**. Elle peut être en retard sur la
boîte vivante. Le « live » reste chez nous.

## La décision (choix produit — humain)
> A-t-on *vraiment* besoin du consentement souverain par acte, ou « local-ish et pratique »
> suffit-il à l'usage réel ?

- **Ça suffit** → assembler l'existant (msgvault + un MCP WhatsApp) et arrêter notre couche.
  Livrer vite.
- **Besoin réel** → la roue n'existe pas. Continuer, recentré sur l'écriture sous consentement.

## Suite
1. Répondre à la question ci-dessus, à froid.
2. **Spike 30 min** : lancer msgvault sur les comptes, vérifier que sa lecture couvre le
   besoin « consulter ». Fiche backlog dédiée :
   [`features/20260930214101550_spike-msgvault-lecture-gmail.md`](../features/20260930214101550_spike-msgvault-lecture-gmail.md).
3. Si on garde la couche : décider comment le serveur est atteint — client Claude direct
   (simple), ou pont HTTP pour une coquille type NanoClaw (transport HTTP à ajouter).

**Pendant WhatsApp.** Même réflexe côté WhatsApp, mais la conclusion diffère : pas de produit
aussi fini que msgvault. Le plus proche est un serveur MCP (pont → base locale → recherche).
Le spike dédié vit dans son vrai repo, `whatsapp-mcp` :
`features/20261001125109014_spike-whatsapp-archive-locale.md`.
