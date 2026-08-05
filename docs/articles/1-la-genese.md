# La genèse : les corvées que je voulais confier à un agent — en travers de mes comptes

> *Les tâches que je rêvais d'automatiser vivaient sur plusieurs comptes Google à la fois. Et pour les faire, il aurait fallu tout confier à l'agent.*

Vendredi soir. Un client me réclame le dossier de specs. Il est sur mon Drive **perso** ; il doit atterrir sur le Drive du **client** — un autre compte Google. Alors je fais ce que je fais toujours : télécharger d'un côté, re-téléverser de l'autre, à la main. Encore.

Et l'évidence me tombe dessus : *ça*, c'est exactement le genre de tâche idiote qu'un agent devrait avaler pendant que je bois mon café. Un agent LLM — un assistant fondé sur un grand modèle de langage, comme [Claude](https://claude.ai) ou [Cursor](https://cursor.com) — sait lire, trier, ranger. Je vais le brancher sur Google et lui dire « fais-le ». Deux minutes plus tard, j'avais refermé l'onglet. Pour une raison toute bête — mais elle changeait tout.

## Mes corvées ne tenaient jamais sur un seul compte

En listant ce que je voulais déléguer, un motif crève les yeux — tout enjambe plusieurs comptes :

- **Déplacer un fichier** de mon Drive perso vers le Drive d'un client.
- **Chercher un mail** — « la facture de janvier » — sans savoir sur laquelle de mes quatre boîtes il a atterri.
- **Ranger le Drive d'un projet** sans que l'agent aille fouiner dans mon perso.

Or les **connecteurs** que je trouvais — les intégrations qui branchent un agent sur un service — marchaient tous sur le même moule : **un compte, un jeton, "tout accepter".** Un agent câblé comme ça ne voit qu'*une* boîte, et pour la voir, il a fallu lui livrer ce compte en entier. Pour *déplacer un fichier entre deux Drives*, il était tout simplement hors-jeu.

Et si vous câblez vous-même un agent sur Google, c'est précisément ce que vous finissez par réécrire à la main : viser le bon compte, et ne lui lâcher que le strict nécessaire.

## Ce que je voulais vraiment

Deux exigences, qui tiraient dans le même sens.

**Cibler le bon compte, par son nom.** Pas « mon Google » en bloc, mais des comptes distincts — `perso`, `client-x` — que l'agent désigne par un **alias** (un surnom court), et jamais l'un pour l'autre. L'agent qui range le projet n'a aucune raison de pouvoir lire mon perso.

**Le moindre privilège.** Par défaut, l'agent ne peut *rien*. Il gagne un accès seulement quand je l'ouvre, pour la durée que je choisis. Bref, inverser la charge de la preuve : non pas « l'agent a tout sauf ce que j'interdis », mais **« l'agent n'a rien sauf ce que j'autorise »**.

## Le fil conducteur : l'agent demande, l'humain ouvre

De ces deux exigences découle la règle qui n'a jamais bougé : **l'agent peut *demander* un accès, mais c'est toujours un humain qui ouvre la porte.** Il propose ; je dispose. Ce petit mécanisme a un nom — l'**élicitation** — et il mérite son [propre article](2-elicitation-authentification-forte.md), parce que c'est lui qui transforme « fais-moi confiance » en « demande-moi ».

Un corollaire, tout aussi non négociable : tout ça tourne **sur ma machine**. Pas de serveur tiers qui voit défiler mes mails ; la seule miette de cloud, c'est un identifiant [OAuth](https://developers.google.com/identity/protocols/oauth2) créé une fois chez Google. « Sans lui donner tout », ça vaut aussi pour les intermédiaires.

## Ce que ça donne, un vendredi soir

Aujourd'hui, la corvée qui m'avait fait fermer l'onglet, je la dicte : *« copie le dossier de specs de perso vers le Drive du client »*. L'agent lit d'un côté, écrit de l'autre, chacun son compte, sans jamais les confondre — et il n'a touché qu'à la porte que je lui avais ouverte, celle-là précisément. Le reste de mon Google ne l'a jamais vu passer.

C'est toute la différence entre livrer les clés de la maison et tendre une clé, pour une pièce, le temps d'un café.

---

*Pour creuser : [l'élicitation, ou comment un agent obtient un accès sans se l'accorder](2-elicitation-authentification-forte.md) · [comment un agent circule entre vos comptes sans les mélanger](3-agent-en-travers-des-comptes.md).*
