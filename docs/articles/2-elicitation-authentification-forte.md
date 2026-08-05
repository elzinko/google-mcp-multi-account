# L'élicitation : un agent qui demande, un humain qui authentifie

> *Un agent puissant ne devrait jamais s'accorder ses propres droits. Il demande ; l'authentification forte, c'est un humain qui la fournit — avec son doigt.*

*« Je vais avoir besoin d'écrire dans le Drive du client pour y déposer le rapport. »* L'agent le dit, poliment. Ce qu'il ne fait **pas**, c'est se donner l'accès tout seul. Il m'affiche une commande exacte à lancer — et comme j'ai activé l'authentification forte, mon Mac me demande **Touch ID**. Une seconde plus tard, la porte est ouverte, pour la durée que j'ai choisie.

Ce petit ballet a un nom — l'**élicitation** (demander la permission au lieu de la prendre) — et c'est le cœur du projet.

## Le problème : puissant *et* imprévisible

Un agent enchaîne les actions vite, et se trompe parfois de cible. Lui laisser s'attribuer ses propres autorisations, c'est comme donner à un stagiaire enthousiaste le tampon qui valide ses propres notes de frais. Tôt ou tard ça dérape — pas par malice, par excès de zèle.

La parade classique — une longue liste de permissions cochées au départ — ne règle rien : soit on coche trop (l'agent peut trop), soit trop peu (on rouvre tout à la première tâche). Je voulais un accès qui s'ouvre **au moment où on en a besoin**, avec **un humain dans la boucle** à cet instant précis.

## Demander, jamais prendre

L'idée tient en une phrase : **l'agent peut *demander* un accès, jamais se l'accorder.**

Pour ça, un principe de base : par défaut, **chaque compte est verrouillé** — l'agent ne peut rien tant qu'un humain n'a pas ouvert. Et l'agent ne possède qu'un seul outil pour réclamer plus : `access_request`, qui **ne déverrouille rien et n'accorde rien**. Il se contente de renvoyer la commande exacte que l'humain devra taper — avec `gwsa`, la commande en ligne de l'outil :

```text
gwsa unlock client-x 30           # déverrouille le compte "client-x" 30 minutes
gwsa grant client-x Rapports 2    # confie le dossier "Rapports" pour 2 heures
```

(`client-x`, ici, c'est l'*alias* d'un compte — son surnom court.) L'agent propose ; moi j'exécute. La décision d'élargir l'accès **quitte** l'agent pour revenir à un humain, à chaque fois. C'est ça, le renversement.

## Là où l'authentification forte entre en scène

Renvoyer une commande, c'est bien. Mais qu'est-ce qui prouve que c'est **un humain** — moi — qui la lance, et pas l'agent qui aurait trouvé le moyen de le faire à ma place ?

La présence physique. Une fois l'authentification forte activée, `unlock` et `grant` exigent **Touch ID** (l'empreinte) ou, à défaut, le mot de passe de session macOS. « Authentification forte » n'a pas ici le sens habituel du code reçu par SMS : c'est une **preuve de présence** par biométrie. Pas de doigt, pas d'ouverture.

Et un détail qui change tout : **la fenêtre Touch ID nomme le produit**. Elle affiche « google-multi-account », pas un intitulé technique cryptique. Parce qu'au moment d'apposer son doigt, ce qu'on *lit* compte autant que ce qui se passe derrière — un dialogue qu'on ne reconnaît pas, c'est un dialogue qu'on valide sans réfléchir. (Sous le capot, le programme qui déclenche la biométrie est même appelé par son chemin complet, jamais deviné, pour qu'aucun imposteur ne se glisse à sa place.)

## Ce que ça garantit — et ce que ça ne garantit pas

Soyons honnête, c'est important. L'élicitation **discipline le comportement** d'un agent coopératif : par le chemin prévu, il ne peut qu'attendre qu'un humain ouvre. Elle ne lui retire pas magiquement toute **capacité** — un agent doté d'un accès terminal libre pourrait, en théorie, contourner ces garde-fous par un autre chemin.

D'où le geste concret à retenir si vous outillez un agent : **ne faites transiter vos données Google que par le serveur local du projet** (la prise unique par laquelle l'agent accède aux comptes), et fermez-lui les autres portes. Le détail de cette frontière est dans le [modèle de menace](../threat-model.md).

Le principe, lui, reste intact : **un agent ne s'auto-autorise jamais.** Il demande — et c'est mon empreinte qui répond.

---

*Pour creuser : [pourquoi tout est parti d'une corvée entre deux comptes](1-la-genese.md) · [comment l'agent travaille ensuite en travers de vos comptes](3-agent-en-travers-des-comptes.md).*
