# OAuth setup — Google Cloud console (one-shot, ~10 min)

!!! info "Prerequisite to using the project"
    This Google Cloud step is a **prerequisite**: without the `client_secret.json`
    produced here, no account can be connected. Do it once — before, or
    right after, [installing the connector](mcp-setup.md).

> **Shortcut** (once the connector is installed): the `provision-gcp.sh` script
> automates steps 1, 2 and 3 (checking which account is signed in) and
> guides you through steps 4 and 5, the only actions Google forces you to do in the console.
> `curl` install → `~/.local/share/google-mcp/current/scripts/provision-gcp.sh`;
> from a clone → `./scripts/provision-gcp.sh`. If you do the OAuth **before**
> installing, follow the manual guide below — it remains the reference if you
> prefer to do everything yourself.

Goal: get a `client_secret.json` that will let `gws` connect
**all** your @gmail.com accounts. Do it **only once**, with **one**
account (the project "owner" — e.g. your main account; the other
accounts will never need to open the console).

> **Good to know**: a Google Cloud "project" is just an administrative
> container. Nothing is deployed, nothing runs, no credit card or
> billing — it is an OAuth identity card, not hosting. Cost: €0.

If several Google accounts are signed in in your browser, check (avatar
at the top right of the console) that you are acting with the main account.

## 1. Create the project

1. Open <https://console.cloud.google.com> and sign in.
2. Project selector (top left) → **New project** → name:
   `gws-multi-account` → **Create** (no organization).
3. Check that the new project is selected.

## 2. Enable the APIs

For each link, click **Enable** (with the `gws-multi-account` project active):

- Gmail: <https://console.cloud.google.com/apis/library/gmail.googleapis.com>
- Drive: <https://console.cloud.google.com/apis/library/drive.googleapis.com>
- Calendar: <https://console.cloud.google.com/apis/library/calendar-json.googleapis.com>
- Docs: <https://console.cloud.google.com/apis/library/docs.googleapis.com>
- Sheets: <https://console.cloud.google.com/apis/library/sheets.googleapis.com>
- Slides: <https://console.cloud.google.com/apis/library/slides.googleapis.com>
- Tasks: <https://console.cloud.google.com/apis/library/tasks.googleapis.com>
- People/Contacts (optional): <https://console.cloud.google.com/apis/library/people.googleapis.com>

## 3. OAuth consent screen

1. Open <https://console.cloud.google.com/auth/overview> ("Google Auth Platform").
2. **Get started**:
   - App name: `gws-cli-perso`
   - User support email: your address
   - Audience: **External**
   - Contact email: your address
3. **Create**.

## 4. Create the OAuth client (Desktop)

1. Open <https://console.cloud.google.com/auth/clients>.
2. **Create client** → Application type: **Desktop app** → name: `gws-cli` → **Create**.
3. **Download JSON** (download button of the created client).
4. Put the file in place:

   ```bash
   mkdir -p ~/.config/gws-accounts
   mv ~/Downloads/client_secret_*.json ~/.config/gws-accounts/client_secret.json
   ```

## 5. Publish the app to Production (recommended)

Without this step, the app stays in *Testing* status: each account must be
declared as a "test user" **and** tokens expire every 7 days.

1. Open <https://console.cloud.google.com/auth/audience>.
2. **Publish app** → confirm.
3. That's it. No Google verification to request for personal use:
   on each account's first sign-in, a "Google hasn't verified
   this app" screen appears → **Advanced** → **Go to
   gws-cli-perso (unsafe)** → grant the access.

*Alternative if you prefer to stay in Testing: on the same page, **Test
users** section → **Add users** → add each @gmail.com address to connect
(weekly reconnection required).*

## 6. Connect the accounts

Back in the terminal:

```bash
mag add perso perso.email@gmail.com     # account #1: the email pins it, the browser confirms
mag add assoc assoc.email@gmail.com     # account #2
mag list
```

## 7. Multi-account: IAM role for each connected account

`gws` attaches the GCP project of `client_secret.json` as the *quota project* on
every API call. Google then checks that the **calling account** has the
`serviceusage.services.use` permission on that project — otherwise `403 Caller
does not have required permission to use project <id>`, even with a perfectly
valid token. The account that created the project passes; **all the
others must be given the role** (one-shot, free, ~2 min to propagate):

```bash
# run with the project owner account (gcloud auth login)
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=user:<adresse@gmail.com> --role=roles/serviceusage.serviceUsageConsumer
```

Redo this for each new account connected via `mag add`. It is the same
list of addresses as the *test users* of step 5 (if the app stayed in
Testing): decide it once, use it twice.

**The tooling guides you** — you don't have to spot the gap by hand:

- `mag add <alias>` runs a probe after sign-in: if the account lacks the
  role, it **directly prints the gcloud command** to have run.
- `./scripts/provision-gcp.sh status` lists **all** connected accounts
  with their project access state, and the remediation command for each
  one that is missing — the entry point to check for drift at any
  time (read-only).
- `./scripts/provision-gcp.sh sync-iam` grants the role to all accounts
  that are missing it, in one **idempotent** pass (confirmation per account,
  `--yes` for scripting) — to be run by the project owner, in their gcloud
  session.

An LLM guiding the installation therefore only has to run `status`, relay the
printed commands, and let you run them (it never runs them
itself — admin action, like unlock/grant).
