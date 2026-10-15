# Browser-assisted provisioning (LLM-driven)

Runbook for an LLM (Claude in Chrome / the built-in browser pane) to provision
the Google Cloud project end to end, driving the console itself and **stopping
only for the few gestures that must stay human**. It is the automated path for
the manual steps in [setup-oauth.md](setup-oauth.md).

> **Who runs this.** A human asks their LLM: *"provision my GCP project
> (browser-assisted)"*. The LLM follows this runbook. The CLI parts come from
> `scripts/provision-gcp.sh`; the console parts the LLM does in a browser.

## In plain terms

Most of the setup is automatable. The LLM creates the project, enables the APIs,
configures the consent screen, creates the OAuth "Desktop" client, downloads its
JSON, and publishes the app — all in the browser. **Three things stay human**:
having a Google account, the `gcloud` login (credentials), and confirming which
account owns the project. The LLM never does those; it stops and asks.

## The golden rule — verify the account first (and keep verifying)

The single most common failure: the project gets created under one Google
account, but the browser console is signed into a **different** account, so every
console action is refused ("you need additional access"). Caught the hard way on
2026-10-13.

So, **before creating anything**, and **before every console action**:

1. Read the account that `gcloud` will use — it becomes the project **owner**:
   ```bash
   gcloud auth list --filter=status:ACTIVE --format="value(account)"
   ```
2. Read the account the **browser console** is signed into (open the account menu
   via the top-right avatar).
3. **They must match.** Show both to the human and get an **explicit
   confirmation** (elicitation) before creating the project:
   *"I'll create the project under `X`, and your browser console is on `X` — is
   that the account you want?"* Create nothing before the human says yes.
4. If the browser account ≠ the `gcloud` owner at any later step: **STOP**, say
   so, and let the human switch accounts. Never click on a project the current
   browser account cannot see — the console may say "already deleted / not found"
   when the truth is "wrong account", which can orphan a real project.

## Prerequisites — the one-time human gestures

| Gesture | Who | How |
|---|---|---|
| Have a Google account | Human (once) | Most people already do. Otherwise: <https://accounts.google.com/signup> |
| Open the GCP console & accept its Terms | Human (once) | <https://console.cloud.google.com> — sign in, accept the ToS. **No credit card**: the project is just an OAuth container, free (0 €). |
| `gcloud auth login` | Human (credentials) | The LLM **never** types credentials. The human authenticates in the browser and finishes to *"You are now logged in as …"*. |

The LLM may open those links and explain, but the human performs the sign-in.

## The flow

Legend: **[CLI]** = `provision-gcp.sh` does it · **[LLM]** = the LLM does it in
the browser · **[HUMAN]** = a human gesture the LLM only prompts for.

1. **[HUMAN]** Ensure a Google account exists and the GCP console ToS are
   accepted (links above).
2. **[HUMAN]** `gcloud auth login` → pick the account that should **own** the
   project. The LLM prompts; the human authenticates.
3. **[LLM]** Verify the account (the golden rule) and get explicit confirmation.
4. **[CLI]** Run the provisioner, which creates the project and enables the APIs:
   ```bash
   ./scripts/provision-gcp.sh --confirm-account <the-confirmed-email>
   ```
   It stops at the consent screen and OAuth client steps (the ones below).
5. **[LLM]** **Consent screen / Branding.** If the CLI could not create it by API
   (normal on personal accounts), open
   `https://console.cloud.google.com/auth/overview?project=<PROJECT_ID>` and
   complete the Branding page: app name, user support email (the owner), Audience
   **External**, developer contact email (the owner).
   **To be able to publish later (step 7), also fill on the Branding page:** the
   **App domain** fields — application homepage, privacy policy and terms URLs
   (for an open-source tool, the public repo URL works for all three) — and add
   an **authorized domain** (e.g. `github.com`). These are *not* flagged as
   required in the UI, but **publishing to Production needs them**.
   **Do NOT add a logo:** a logo forces app verification in Production.
6. **[LLM]** **OAuth Desktop client.** Open
   `https://console.cloud.google.com/auth/clients/create?project=<PROJECT_ID>` →
   application type **Desktop app** → name `gws-cli` → **Create**. In the dialog,
   click **Download JSON** *before closing it* (the secret is shown only once).
   The CLI watches `~/Downloads` and files the JSON into
   `~/.config/gws-accounts/client_secret.json` automatically. **Download it only
   once** (a second download leaves a copy of the secret in `~/Downloads` — tell
   the human to delete it). The LLM never reads or prints the secret.
7. **[LLM]** **Publish to Production.** Open
   `https://console.cloud.google.com/auth/audience?project=<PROJECT_ID>` →
   **Publish app** → **Confirm**. This removes the 7-day token expiry of Testing
   mode. The app stays **unverified** (personal use): each account clicks through
   a one-time "Google hasn't verified this app" warning at sign-in. Publishing is
   reversible (you can return to Testing). If **Publish app** is greyed out, the
   Branding App-domain fields or the authorized domain are missing — see step 5.
8. **[HUMAN]** Back in the terminal, confirm the publish so the CLI records it,
   then connect accounts: `mag add <alias> <email>` (the email is required when
   Touch ID / strongauth is on).

## Gotchas learned on real runs

- **"Publish app" is greyed out, pointing you to the Branding page — even though
  Branding looks complete.** The real cause is **not** propagation (a long red
  herring on the first real run): the **App domain** fields (homepage, privacy,
  terms URLs) and an **authorized domain** are missing. Fill them on the Branding
  page (the repo URL for the three links, `github.com` as the authorized domain)
  and Save — the button enables. Re-saving Branding *without* those fields does
  **not** help.
- **A logo triggers verification in Production.** Leave the logo empty, or remove
  it before publishing, to stay unverified for personal use.
- **"Create OAuth client" says 'configure the consent screen first' right after
  you created it.** This one *is* a short propagation lag — retry after a moment.
- **Account mismatch** (the golden rule) is the #1 blocker. Always verify.

## Hard limits — what the LLM never does

- Never type credentials / never do the `gcloud auth login` sign-in itself.
- Never read, print, or commit `client_secret.json` or anything under
  `~/.config/gws-accounts/` (only trigger the download; let the CLI file it).
- Never bypass a **[HUMAN]** stop, and never act on a console project the current
  browser account cannot see.
- Never create an account or accept Terms on the human's behalf.

## Related

- Manual procedure: [setup-oauth.md](setup-oauth.md)
- Provisioner (CLI): `scripts/provision-gcp.sh`
- Backlog item that asked for this: `features/20261013102010760_provisioning-gcp-assiste-navigateur-llm.md`
