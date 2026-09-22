# Prompt de lancement — test manuel « une fois / pour la session »

> À coller dans une session Claude Code de ce repo, ou déclencher par :
> « lance le test manuel transactionnel-une-fois-session ».

Lance le test manuel **transactionnel-une-fois-session**.

Lis d'abord `tests/manuels/transactionnel-une-fois-session/PROTOCOLE.md`, puis
déroule-le **phase par phase**. Utilise le serveur MCP transactionnel (`gma-tx`)
ou `GWSA_CLIENT=claude-code mag …` — jamais `gws` nu.

Règles du jeu :
- Tu **proposes** les gestes de consentement ; **c'est moi** qui pose le doigt
  (Touch ID) et qui exécute les unlock/grant. Tu ne déverrouilles jamais toi-même.
- Toute écriture reste sous `ZZ-TESTS/DOSSIER-A` ou `DOSSIER-B` (bac à sable).
- À chaque acte, annonce clairement la **portée** que tu demandes (« une fois »
  ou « pour la session ») **avant** que je valide, et dis-moi ce que tu attends
  comme résultat (geste demandé ? ou passage direct ?).
- Arrête-toi à chaque phase et attends ma confirmation visuelle avant la suivante.

But : prouver les 4 comportements clés — « une fois » redemande, « pour la
session » laisse repasser le même dossier, un autre dossier redemande, et le
partage redemande **toujours**.
