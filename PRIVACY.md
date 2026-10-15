# Privacy Policy

**google-multi-account** is a free, open-source tool that connects an LLM agent
to **your own** Google accounts (Gmail, Drive, Calendar, …) through a local
[MCP](https://modelcontextprotocol.io) server. It runs **entirely on your
machine**.

_Last updated: 2026-10-13_

## Who this concerns

This policy describes how the **software** handles data when you run it. The
project is maintained by its open-source authors, who operate **no server** and
**receive no data** from you.

## What data is processed

- The tool accesses **your own** Google data only when you ask it to, using
  OAuth credentials **you** create in **your own** Google Cloud project.
- OAuth tokens are stored **locally and encrypted** (AES-256-GCM, master key in
  the macOS Keychain). They never leave your machine except to talk to Google's
  own APIs.
- The only network calls are between **your machine** and **Google's APIs**
  (plus the one-time Google OAuth consent flow in your browser).

## What the project does NOT do

- **No data is sent to the maintainers** or to any third party. There is no
  backend, no analytics, no telemetry.
- The project does not sell, share, or store your data anywhere outside your
  machine.
- Nothing is recorded beyond a **local** audit log on your own disk, for your
  own inspection.

## Your responsibility

Because you run the tool yourself with your own Google project, **you are the
controller** of your data. Your use of the Google APIs is subject to
[Google's Terms of Service](https://policies.google.com/terms) and
[Google's Privacy Policy](https://policies.google.com/privacy).

## Access and revocation

Google Workspace APIs (Gmail included) can reach sensitive data. Grant only the
access you need, and revoke it at any time from your
[Google Account permissions](https://myaccount.google.com/permissions).

## Contact

Questions or issues: <https://github.com/elzinko/google-mcp-multi-account/issues>
