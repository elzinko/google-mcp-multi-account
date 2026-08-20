# Contribuer

Envie de donner un coup de main ? Ce projet est petit, local, et sans machinerie
lourde — on peut y entrer vite. Voici le chemin, du clone à la PR mergée.

## Mettre le pied à l'étrier

```bash
git clone https://github.com/elzinko/google-mcp-multi-account
cd google-mcp-multi-account
./scripts/test.sh          # la suite hermétique — sans compte réel, sans réseau
```

Si la suite est verte, votre environnement est bon. Il vous faut **Python 3** ; la
CLI Google `gws` n'est nécessaire que pour un test avec de *vrais* comptes (les tests
automatiques n'en utilisent aucun).

Pour voir tourner l'interface admin sur votre code :

```bash
./bin/mag dev test         # déploie le clone courant, démarre l'admin, affiche l'URL
```

## Comment le travail s'organise

- **Le backlog vit dans le dépôt.** Chaque idée, bug ou feature est une fiche
  markdown dans `features/`
  (une par sujet ; le front-matter porte le statut). C'est là qu'on voit *ce qui
  reste à faire* et *ce qui est livré* (`features/done/`).
- **Une PR par sujet.** On part d'une branche, on garde la PR focalisée.
- **Messages de commit** en [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`…) — c'est ce qui alimente le CHANGELOG et le versionnage.
- **Revue automatique** : chaque PR reçoit une relecture (Codex) ; on traite les
  retours avant de merger.
- **Merge au vert**, en général en *squash*.

## Deux garde-fous à respecter

Ce sont les invariants de sécurité du projet — les casser silencieusement est le
seul vrai « non » :

- **Ne jamais** committer ni afficher de secrets : tokens, `client_secret.json`,
  sortie de `gws auth export`. On cite les *chemins* (`~/.config/gws-accounts/`),
  jamais le contenu — voir [SECURITY.md](https://github.com/elzinko/google-mcp-multi-account/blob/main/SECURITY.md).
- **Ne pas contourner** les garde-fous (policy default-deny, verrous, zones Drive) :
  ils sont le cœur du projet. Si un besoin les gêne, ouvrez-en la discussion dans une
  fiche plutôt que de les affaiblir.

## Valider votre PR

Une bonne PR est **testable par quelqu'un qui n'a pas le contexte** : pas un « testé
✅ » nu, mais *quoi* a été testé, *comment* le rejouer, et *quel signal observable*
dit pass ou fail. La convention complète (matrice de modalités, bloc de commandes
copy-pastable, signaux pass/fail) est détaillée dans **[Validation des PR](PR_VALIDATION.md)**.

## Pour aller plus loin

- **[Sous le capot](architecture.md)** — comment les pièces s'assemblent, où sont les garde-fous.
- **[Sécurité GitHub](github-security.md)** — la configuration de sécurité du dépôt.
- Une décision de conception vous intrigue ? Les **[ADR](adr/ADR-0001-onboarding-par-elicitation.md)**
  expliquent *pourquoi* le projet a tranché comme il l'a fait.
