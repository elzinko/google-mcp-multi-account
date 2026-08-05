# Un agent qui circule entre vos comptes (sans les mélanger)

> *Faire voyager un fichier d'un compte Google à un autre, coordonner une recherche sur quatre boîtes — un geste qui n'existe pas nativement, qu'un agent rend fluide, et qu'un cloisonnement garde sûr.*

Je dicte : *« dépose le rapport final dans le Drive du client »*. Le fichier part de mon **perso**, traverse, atterrit chez le **client** — deux comptes Google distincts, zéro copier-coller, et l'agent n'a jamais eu à voir le reste de mon perso. Ce petit voyage, un connecteur mono-compte en est tout bonnement incapable. Voici comment il se fait — proprement.

## Le voyage qui n'existe pas nativement

Première surprise pour qui débarque : **il n'y a pas de "déplacer" entre deux comptes Google.** Un fichier appartient à un compte ; aucune API ne le téléporte chez un autre d'un claquement de doigts.

L'agent fait donc ce qu'un humain ferait — mais sans le copier-coller pénible : il **lit** le contenu côté `perso`, le **recrée** côté client, ou **partage** l'original de l'un vers l'autre. Recopie et partage : deux gestes simples qui, combinés, reconstituent le « déménagement » manquant. C'est exactement le genre de couture que, sinon, on refait à la main à chaque fois.

Un point que j'assume : le **transfert de propriété** (faire du client le véritable propriétaire du fichier) est une opération à part — destructrice, délicate — et elle n'est **pas** dans cette version, volontairement. Recopier et partager couvrent l'immense majorité des besoins, sans le risque.

## Chercher sur quatre boîtes à la fois

L'autre grand cas : *« la facture de janvier ? »*, sans savoir où elle a atterri. Là encore, aucune recherche magique inter-comptes n'existe. C'est l'agent qui **orchestre** : il interroge `perso`, puis `work`, puis chaque client, et **synthétise** le tout en une réponse.

C'est peut-être *le* geste le plus « agent-natif » de toute l'histoire : lancer N requêtes ciblées, une par compte, et recomposer un résultat unique. Un connecteur mono-compte ne verrait qu'une boîte ; l'agent, lui, balaie l'ensemble — sans jamais mélanger d'où vient quoi.

## Pourquoi ça ne vire pas au carnage

Laisser un agent écrire et fouiller en travers de plusieurs comptes, ça pourrait très mal tourner. Trois niveaux de contrôle l'en empêchent, et ils s'emboîtent proprement :

- **Le verrou** décide *si* l'agent entre dans un compte. Chaque compte est un **profil** isolé, avec son propre verrou ; un compte fermé ne s'ouvre que sur un geste humain.
- **La policy et les zones** décident *à quoi* il touche une fois entré. Les **zones Drive** limitent l'écriture aux seuls dossiers que je lui ai confiés — en permanence, ou pour quelques heures. Déposer le rapport dans `client-x/Rapports` : oui. Écrire ailleurs sur le Drive du client : refusé. *Je prête un tiroir, pas la commode.*
- **Le *default-deny*** ferme tout le reste. Toute action non explicitement autorisée est refusée : le silence vaut « non ». Et côté Gmail, il n'existe tout simplement **aucun outil pour envoyer** — l'agent lit et prépare des brouillons. Ma recherche coordonnée peut donc ratisser mes quatre boîtes sans qu'un seul mail parte jamais tout seul.

Le cloisonnement est ce qui rend le reste possible : puisqu'un compte ne déborde jamais sur un autre de lui-même, faire circuler quelque chose d'un compte à l'autre reste un **geste explicite**, décidé par moi — jamais un effet de bord.

## Retour au vendredi soir

La corvée qui, un vendredi soir, m'avait fait fermer l'onglet — copier un dossier d'un Drive à un autre — l'agent l'expédie désormais pendant que je bois mon café. Il circule entre mes comptes ; il en balaie quatre d'un coup ; et pourtant chacun reste une boîte à part, ouverte par moi, pour ce qu'il faut, le temps qu'il faut.

C'était tout le pari du départ : un agent qui *travaille* pour moi en travers de mes comptes, sans que je lui aie livré ma vie numérique en bloc. Il demande, je réponds — et le reste, il ne le voit même pas.

---

*Pour creuser : [d'où est venue l'idée](1-la-genese.md) · [comment l'agent obtient l'accès sans se l'accorder lui-même](2-elicitation-authentification-forte.md).*
