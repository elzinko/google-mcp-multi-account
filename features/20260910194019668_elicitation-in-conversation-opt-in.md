---
id: "20260910194019668"
title: Élicitation dans la conversation — popup sans terminal, confirmé dans le chat (opt-in)
type: feature
priority: P1
product: google-mcp-multi-account
version:
epic: 0082
status: ready
ready: 2026-09-10
pr:
created: 2026-09-10
---

## En clair

Aujourd'hui, pour autoriser un accès depuis une conversation, tu dois **sortir de la
conversation** : ouvrir un terminal, taper une commande `mag`, valider par Touch ID. La
friction, c'est le terminal.

Cette fiche supprime le terminal. Un **réglage opt-in**, désactivé par défaut, active un mode
où :

```
1. Claude annonce dans le chat : « Je vais demander l'accès à <compte> pour <X>. Tu confirmes ? »
2. TOI, dans le chat : « ok »
3. Le popup Touch ID surgit                → tu valides
4. L'accès est ouvert pour la session
```

Plus fluide qu'aujourd'hui : tu réponds « ok » au lieu d'ouvrir un terminal. Et le filet de
sécurité, le **Touch ID**, ne bouge pas.

## Décisions de conception (2026-09-10)

Trois choix tranchés avec Thomas (critères : safe, pro, plus fluide qu'aujourd'hui) :

1. **Tool MCP dédié, masqué par défaut.** `access_request` reste **inchangé** (il continue de
   renvoyer la commande à taper). Le mode vit dans un **tool séparé**, qui n'est **pas exposé**
   côté MCP tant que le réglage est off. Surface nulle par défaut, séparation nette, coupure
   facile.
2. **Confirmation dans le chat** avant le popup (pas de popup surgissant sans ton « ok »).
3. **POC minimal d'abord** : réglage + confirmation chat + popup + throttle. L'ADR formel et
   l'allowlist des comptes sensibles suivent dans un second temps.

## Contexte / problème

**Le flux actuel, en deux verrous.**

```
1. Claude touche un compte verrouillé        → refus « verrouillé »
2. access_request kind=session_unlock         → N'EXÉCUTE RIEN. Renvoie une commande texte :
                                                 « mag session unlock <sid> <alias> <min> »
3. TOI, dans un terminal : tu tapes           → VERROU 1 : l'humain INITIE (canal hors LLM)
4. Touch ID / mot de passe Mac                → VERROU 2 : l'humain AUTHENTIFIE
5. Claude refait l'appel avec le jeton        → accès accordé jusqu'à expiration
```

Le verrou 2 (Touch ID) est le contrôle fort. Le verrou 1 (taper la commande) garantit que
l'initiation vient de l'humain. La friction, c'est le verrou 1 : quitter la conversation,
ouvrir un terminal, copier-coller.

**Faisabilité — vérifiée le 2026-09-10.** Le broker tourne déjà en local ; rien dans macOS
n'empêche un process local de déclencher le popup Touch ID. Aujourd'hui, ce popup n'est appelé
**que** par `bin/mag`, jamais par le chemin MCP/broker. Le câblage manquant est donc petit et
localisé.

## Sécurité — ce que ce mode change vraiment (à ne pas survendre)

C'est le cœur de la fiche. Sois précis, ne survends pas.

- **Le terminal est un verrou dur.** Le tool MCP ne *peut pas* taper la commande. Seul l'humain
  le peut. Point.
- **La confirmation dans le chat est un verrou souple.** Elle repose sur la **coopération de
  Claude** : Claude annonce, attend ton « ok », puis rappelle le tool avec `confirm=true`. Une
  injection de prompt ne peut pas répondre « ok » à ta place (c'est **toi** qui écris dans le
  chat). Mais un Claude **entièrement détourné** pourrait sauter cette étape et appeler
  `confirm=true` directement.
- **Le vrai filet reste le Touch ID.** Même dans ce pire cas, le popup surgit et **exige ton
  doigt**. Rien ne s'autorise sans ton geste physique.

Bilan honnête : ce mode est **plus fluide qu'aujourd'hui** (plus de terminal) et **nettement
plus sûr que le popup-direct** (dans le cas normal, aucun popup sans ton « ok »). Il n'est
**pas** cryptographiquement équivalent au terminal. La protection ultime — Touch ID — est
inchangée. L'ADR doit écrire cette réalité du « verrou souple + filet Touch ID » telle quelle.

## Pistes de protection écartées (analyse faite, à ne pas refaire au grooming)

- **Sceau anti-phishing dans le popup.** Ne ferme **pas** la faille d'injection : le broker
  afficherait le sceau de bonne foi, quelle que soit l'origine de la demande. Le sceau prouve
  « ce popup vient du vrai broker », pas « cette demande vient de ton intention ». Il protège
  d'un **autre** flanc : un malware tiers qui imiterait le popup `mag`.
- **Challenge LLM ↔ broker.** Le broker authentifie **déjà** le serveur MCP par jeton
  (`.broker-<port>-token`). Le maillon faible n'est pas « un imposteur se fait passer pour le
  LLM » ; c'est « le vrai LLM relaie une intention injectée ». Mauvais maillon.

## Proposition (POC minimal)

1. **Réglage**, façon `mag strongauth`. Off par défaut. Nom à trancher, par ex.
   `mag elicitation in-conversation on|off|status`. L'activation affiche un **avertissement de
   risque** avant de basculer.
2. **Tool MCP dédié, exposé conditionnellement.** Tant que le réglage est off, le tool
   **n'apparaît pas** dans la liste des tools. Quand il est on, il apparaît et porte le mode.
3. **Protocole en deux temps** (la confirmation chat) : premier appel → le tool renvoie
   « confirmation requise » + le texte de l'action ; Claude l'annonce dans le chat ; après ton
   « ok », second appel `confirm=true` → le broker déclenche `run_elicitation_gate` → popup
   Touch ID natif. Refus ou biométrie absente → accès refusé (fail-closed).
4. **Garde-fou throttle** : une demande à la fois, plafond par fenêtre de temps. Un second
   déclenchement rapide est bloqué.
5. **Texte de popup clair** : déjà fourni par `prompt_from_payload` — le réutiliser tel quel.

**Reporté au 2e temps** (pas dans le POC) : ADR formel threat-model, allowlist des comptes
sensibles (les marquer « toujours au terminal »).

## Relation aux fiches voisines (pas un doublon)

- [`0001`](0001-elicitation-signee-strongauth-v2.md) — le **mécanisme** d'élicitation signée
  qu'on étend (le popup Touch ID). Ici, on change **qui le déclenche**, pas la signature.
- [`0082`](0082-droits-par-session.md) — **épic parent** (droits par session).
- [`0108`](0108-session-demande-sous-ensemble-droits-compte.md) — voisin **orthogonal** : le
  *quoi* on accorde (sous-ensemble de droits). Ici c'est le *comment* l'humain autorise.
- Question ouverte partagée avec [`0101`](0101-nom-de-session-fourni-par-le-client.md) et 0108 :
  le protocole MCP ne porte pas d'id de conversation. **Ce mode n'en dépend pas** — le popup
  fonctionne avec le jeton de session actuel.

## Critères d'acceptation

- [ ] **Réglage off par défaut.** `mag elicitation in-conversation status` répond « off » sur un
  poste neuf. L'activation affiche un avertissement de risque explicite.
- [ ] **OFF = zéro changement.** Le tool dédié **n'est pas exposé** côté MCP. `access_request`
  renvoie la commande à taper, comme aujourd'hui. Test de non-régression.
- [ ] **ON = tool exposé.** Le tool dédié apparaît dans la liste des tools MCP seulement quand
  le réglage est on.
- [ ] **Protocole en deux temps.** Premier appel → « confirmation requise » (aucun popup). Second
  appel `confirm=true` → le popup Touch ID surgit ; validation → accès ouvert pour la session ;
  refus / biométrie absente → refus (fail-closed).
- [ ] **Throttle.** Un second déclenchement dans la fenêtre est bloqué. Test qui le prouve.
- [ ] **Risque documenté.** L'aide du réglage et la fiche disent que la confirmation chat est un
  verrou **souple**, filet = Touch ID (pas d'équivalence terminal survendue).
- [ ] Clair ET sombre si l'admin est touchée ; `./scripts/test.sh` au vert.

## Comment vérifier

Activer le réglage (voir l'avertissement s'afficher). Depuis une conversation, demander une
action sur un compte verrouillé. Claude doit **annoncer** la demande et attendre ton « ok » —
**aucun popup** avant. Répondre « ok » → le popup Touch ID surgit **sans terminal**. Valider →
l'accès passe. Puis : désactiver le réglage → la même demande **retombe** sur la commande à
taper, et le tool dédié disparaît de la liste. Enfin, enchaîner deux demandes → la seconde est
**bloquée** par le throttle.

## Notes

- **Faisabilité constatée le 2026-09-10** (session Claude) : le popup n'est appelé aujourd'hui
  que par `bin/mag` (via `require_signed_elicitation`) ; `gateway/mcp_server.py` n'expose aucun
  tool qui signe/élicite ; `access_request` ne renvoie qu'une `suggested_command`
  (`gateway/api.py`). Le gros du travail est le **cadrage de sécurité**, pas la plomberie.
- **Décisions de conception datées** ci-dessus (tool dédié masqué / confirmation chat / POC
  minimal) — tranchées le 2026-09-10.
- **Limite de menace** : ce mode augmente la surface (un tool de plus quand il est on). Il ne se
  justifie que pour un usage perso, local, où l'humain contrôle largement ce que Claude lit.
- **Priorité P1**, alignée sur ses sœurs 0101/0108 (même épic). Thomas veut « dev ASAP » : un
  passage devant se décide dans `PLAN.md`.
