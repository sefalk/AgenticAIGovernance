# Identities and Credentials (Copilot line 2.x)

The 2.x line keeps the identity that **runs the agents** separate from the
identity that **reaches your repositories**. Neither may depend on the Local
harness (removed February 2027) or on the editor being signed in to several
accounts at once. Decision: AF #563.

| Purpose | Identity | Where it lives | Checked at session start |
|---|---|---|---|
| Agents and model requests | Copilot harness sign-in | VS Code account (GitHub.com or GHE) | no — the harness owns it |
| Issues, PRs, REST for an extra repo | Fine-grained PAT | `AF_GH_TOKEN` user environment variable | yes — `session-mcp-readiness` (#563) |
| Git only (clone, fetch, push) | Git Credential Manager | OS credential store, one entry per account | no |
| Azure DevOps work items, PRs, wiki | The ADO MCP server's own sign-in | the project's `mcp.json` | presence and mode only |
| CI | `GITHUB_TOKEN` of the workflow | GitHub Actions | n/a |

A **provider API key (BYOK)** is a fifth, optional identity for model
requests. It is evaluated below and not adopted.

## 1. Agents: the harness sign-in

The Copilot harness sends model requests with the account VS Code is signed in
to. With a company licence that is usually a GitHub Enterprise (GHE) account;
with a personal licence it is a GitHub.com account. Nothing in the AF payload
reads or stores this credential.

A GHE token is a **GitHub** credential, not a model-provider key. It never
belongs in `COPILOT_PROVIDER_*` variables.

## 2. Extra repositories over the API: a fine-grained PAT

The `af-github` MCP server in `.mcp.json` authenticates with
`Authorization: Bearer ${AF_GH_TOKEN}` (#547). The file contains no secret; the
value comes from your environment.

Create the token with the minimum it needs:

- **Resource owner:** the account or organisation that owns the repository.
- **Repository access:** *Only select repositories*, normally one.
- **Repository permissions:** only what the agents use —
  *Issues* (read and write) for the issue workflow,
  *Pull requests* (read and write) for the PR workflow,
  *Contents* (read, or read and write only if agents push through the API),
  *Metadata* (read, mandatory).
- **Expiration:** short — 30 to 90 days.

Set it as a user environment variable, in your own terminal and never in a
chat:

```powershell
[Environment]::SetEnvironmentVariable('AF_GH_TOKEN', '<token>', 'User')
```

```bash
# ~/.bashrc or ~/.profile
export AF_GH_TOKEN='<token>'
```

Restart VS Code afterwards; running processes do not see the new value.

Renewing a fine-grained PAT issues a **new value**, and the old one stops
working at once. Update `AF_GH_TOKEN` every time. At each session start
`session-mcp-readiness` makes one `GET /user` request and reports the login
and expiry date. It puts a `WARNING` first in the session context when the
token is rejected, expires within 14 days, or is unset while `.mcp.json` uses
it. The token value is never printed. For GitHub Enterprise Server, point the
check at your API with `AF_GH_API_URL` (for example
`https://ghes.example.com/api/v3`).

## 3. Extra repositories, git only: Git Credential Manager

If agents only need `git fetch` and `git push`, no PAT is required. Git
Credential Manager (GCM, shipped with Git for Windows) stores one credential
per account and host. To use a second account on the same host, put the
account name into the remote URL:

```bash
git clone https://<account>@github.com/<owner>/<repo>.git
# existing clone
git remote set-url origin https://<account>@github.com/<owner>/<repo>.git
```

The first push opens a browser sign-in for that account; later operations use
the stored credential. To pin a default account for a host instead:

```bash
git config --global credential.https://github.com.username <account>
```

`git credential-manager github list` shows the stored accounts. Reference:
[GCM — multiple users](https://github.com/git-ecosystem/git-credential-manager/blob/main/docs/multiple-users.md).

Use both mechanisms when a repository needs git **and** issues or PRs.

## 4. Nested Copilot CLI: never inherit an identity

A Copilot CLI started from inside a harness session inherits the harness
environment. Measured on 2026-11-23 (#563): it picked up `COPILOT_GH_HOST` and
`COPILOT_HOME` and authenticated against the GHE host, which failed with
`401 Bad credentials`. The CLI also takes `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`
and `GITHUB_TOKEN` in that order **before** its stored sign-in, so a token set
for another tool silently becomes the model identity.

Any script that starts a nested CLI must therefore clear the inherited
variables and set the identity explicitly:

```powershell
$clean = Get-ChildItem Env: | Where-Object { $_.Name -match '^(COPILOT_|GH_|GITHUB_)' }
$clean | ForEach-Object { Remove-Item "Env:$($_.Name)" }
$env:COPILOT_HOME = $isolatedHome          # own config, own trusted folders
$env:COPILOT_GITHUB_TOKEN = $explicitToken # or a BYOK provider, see § 5
& copilot -p $prompt
```

Today no AF script starts a nested CLI. The first one will be the CLI
attestation of #553 stage B, and this rule binds it.

A token used for the CLI must be an OAuth token (`copilot login`), a GitHub
App user token, or a fine-grained PAT with the account permission **Copilot
Requests**. Classic PATs are not supported. On a Copilot Free account that
permission is not offered (#553), so a PAT-based CLI run needs a paid seat, a
GHE account (`copilot login --host <host>`), or BYOK.

## 5. Provider API key (BYOK): evaluated, not adopted

**Decision (#563):** keep the harness sign-in as the only model identity for
now. BYOK stays a documented option for platform independence and is
re-evaluated when the harness or the CLI attestation needs it.

| Aspect | Finding | Basis |
|---|---|---|
| What it is | A key from a model provider: `openai` (default, incl. compatible APIs such as Ollama), `azure` (Azure OpenAI), `anthropic` or `google` (experimental). Not a GitHub, GHE or ADO token. | `copilot help providers-env` |
| Configuration | `providers.json` in the CLI configuration directory (preferred; stores the key in **plain text**), or the variables the CLI calls legacy: `COPILOT_PROVIDER_BASE_URL` (required), `COPILOT_PROVIDER_TYPE`, `COPILOT_PROVIDER_API_KEY` and `COPILOT_MODEL` (required). `COPILOT_PROVIDER_API_KEY_COMMAND` fetches the key per request from a vault instead of storing it. | `copilot help providers-env` |
| GitHub sign-in | Not required for model requests. Without one, `/delegate`, the built-in GitHub MCP server and code search are unavailable. The AF's `af-github` server uses `AF_GH_TOKEN` and is unaffected. | CLI docs; AF part inferred |
| Cost | Billed by the provider per token; no Copilot premium requests. No cap from the AF side. | inferred, not measured |
| Model choice | Any model the provider serves that supports tool calling and streaming; AF tier mapping (#557) would need provider model names. | CLI docs; mapping not built |
| Hook and agent parity | Hooks and agents are evaluated client-side, so the model source should not change them. | **not measured** |
| VS Code harness | Whether the VS Code Copilot harness accepts a provider key the way the CLI does is not established. | **not measured** |

Needed before adoption: one CLI run with a provider key in an isolated
`COPILOT_HOME` (§ 4) that records hook events and an agent handoff, compared
with the same run under the harness sign-in.
