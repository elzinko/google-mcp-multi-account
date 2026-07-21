# Setup OAuth — console Google Cloud (one-shot, ~10 min)

> **Raccourci** : `./scripts/provision-gcp.sh` automatise les étapes 1, 2 et 3
> (avec vérification du compte connecté) et te guide pour les étapes 4 et 5,
> seuls gestes que Google impose de faire dans la console. Ce guide manuel
> reste la référence si tu préfères tout faire toi-même.

Objectif : obtenir un `client_secret.json` qui permettra à `gws` de connecter
**tous** tes comptes @gmail.com. À faire **une seule fois**, avec **un seul**
compte (le « propriétaire » du projet — par ex. ton compte principal ; les autres
comptes n'auront jamais besoin d'ouvrir la console).

> **Rassurant à savoir** : un « projet » Google Cloud est un simple conteneur
> administratif. Rien n'est déployé, rien ne tourne, aucune carte bancaire ni
> facturation — c'est une fiche d'identité OAuth, pas de l'hébergement. Coût : 0 €.

Si plusieurs comptes Google sont connectés dans ton navigateur, vérifie (avatar
en haut à droite de la console) que tu agis bien avec le compte principal.

## 1. Créer le projet

1. Ouvre <https://console.cloud.google.com> et connecte-toi.
2. Sélecteur de projet (en haut à gauche) → **New project** → nom :
   `gws-multi-account` → **Create** (pas d'organisation).
3. Vérifie que le nouveau projet est bien sélectionné.

## 2. Activer les APIs

Pour chaque lien, clique **Enable** (avec le projet `gws-multi-account` actif) :

- Gmail : <https://console.cloud.google.com/apis/library/gmail.googleapis.com>
- Drive : <https://console.cloud.google.com/apis/library/drive.googleapis.com>
- Calendar : <https://console.cloud.google.com/apis/library/calendar-json.googleapis.com>
- Docs : <https://console.cloud.google.com/apis/library/docs.googleapis.com>
- Sheets : <https://console.cloud.google.com/apis/library/sheets.googleapis.com>
- Slides : <https://console.cloud.google.com/apis/library/slides.googleapis.com>
- Tasks : <https://console.cloud.google.com/apis/library/tasks.googleapis.com>
- People/Contacts (optionnel) : <https://console.cloud.google.com/apis/library/people.googleapis.com>

## 3. Écran de consentement OAuth

1. Ouvre <https://console.cloud.google.com/auth/overview> (« Google Auth Platform »).
2. **Get started** :
   - App name : `gws-cli-perso`
   - User support email : ton adresse
   - Audience : **External**
   - Contact email : ton adresse
3. **Create**.

## 4. Créer le client OAuth (Desktop)

1. Ouvre <https://console.cloud.google.com/auth/clients>.
2. **Create client** → Application type : **Desktop app** → nom : `gws-cli` → **Create**.
3. **Download JSON** (bouton de téléchargement du client créé).
4. Mets le fichier en place :

   ```bash
   mkdir -p ~/.config/gws-accounts
   mv ~/Downloads/client_secret_*.json ~/.config/gws-accounts/client_secret.json
   ```

## 5. Publier l'app en Production (recommandé)

Sans cette étape, l'app reste en statut *Testing* : il faut déclarer chaque
compte comme « test user » **et** les tokens expirent tous les 7 jours.

1. Ouvre <https://console.cloud.google.com/auth/audience>.
2. **Publish app** → confirmer.
3. C'est tout. Pas de vérification Google à demander pour un usage perso :
   à la première connexion de chaque compte, un écran « Google n'a pas validé
   cette application » s'affiche → **Paramètres avancés** → **Accéder à
   gws-cli-perso (non sécurisé)** → accorder les accès.

*Alternative si tu préfères rester en Testing : sur la même page, section
**Test users** → **Add users** → ajoute chaque adresse @gmail.com à connecter
(reconnexion hebdomadaire obligatoire).*

## 6. Connecter les comptes

De retour dans le terminal :

```bash
gwsa add perso     # navigateur → choisir le compte n°1 → accepter les accès
gwsa add assoc     # navigateur → choisir le compte n°2 → accepter les accès
gwsa list
```
