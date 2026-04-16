# Creating plugins using spec-driven development (`spec-kit` and Claude Code)

This document captures the process of creating a new Kong plugin using spec-driven development (SDD) with `spec-kit` and Claude Code. Along with step-by-step usage instructions, some broader commentary on the process from a user standpoint is included.

The AI generated plugin is in `plugins/trust-registry-ai` and the human generated plugin is in `plugins/trust-registry`. The spec and other artifacts are in the `specs/001-jwks-endpoint` directory.

A comparison report (`.sdd/comparison-report.md`) is also included which captures the differences between the human and AI generated plugins, with some helpful takeaways for improving the process.

## Setup

### 1. Install Specify CLI

*Persistent installation:*

Get `uv` installer:

```sh
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Install `specify-cli`:

```sh
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.7.0
```

Then verify installation:

```bash
specify version
```

### 2. Install Claude Code (or other agent of your choice)

```sh
curl -fsSL https://claude.ai/install.sh | bash
```

If using API key, set the `ANTHROPIC_API_KEY` environment variable in your shell.

```sh
export ANTHROPIC_API_KEY="your-api-key-here"
```

Verify installation (may need to restart WSL with `wsl --shutdown` in PowerShell or restart PC):

```bash
claude
```

Set theme and choose *Yes* to use the API key.

### 3. Initialize in an existing project

Open terminal in the project directory and run:

```sh
specify init . --ai claude
```

### 4. Deny Claude from reading the existing target plugin

Create or edit `.claude/settings.local.json` to include:

```json
{
  "permissions": {
    "deny": [ "Read(plugins/trust-registry)" ]
  }
}
```

### 5. Open Claude Code

`--verbose` shows token usage.

`--model` specifies the model to use, Opus 4.6 was chosen for planning in this
case, using default `high` effort level.

```sh
claude --verbose --model claude-opus-4-6
```

## Using Spec-Kit and Claude Code

### 1. Establish the project constitution

In Claude Code, run:

```sh
/speckit-constitution <<'EOF'
Establish the project constitution for this repository.

The constitution must:
- Define the written specifications as the sole source of truth
- Forbid feature expansion, inference, or undocumented behavior
- Constrain the AI to deterministic generation only; no autonomous design decisions
- Enforce repeatability, minimal output, and explicit termination criteria
- Require all ambiguities and assumptions to be explicitly surfaced, never silently resolved
- Prohibit IDE-dependent workflows, hidden state, or implicit agent iteration
- Require minimal, readable code that adheres strictly to Kong plugin conventions

The constitution should be concise, enforceable, and reusable for future Kong plugin projects.
EOF
```

Cost: ~40K tokens

### 2. Create the spec

In Claude Code, run:

```sh
/speckit-specify <<'EOF'
Story: As an SDX Edge Server host, I want to be able to publish my Edge Server public keys, so that other Edge Servers can use it to validate any JSON Web Signature (JWS) documents that my server creates.

Technical background: The SDX Edge Server host will be able to use a gateway pattern to register public keys.  To make these keys available to others, there has to be an endpoint that takes the Kong `keys` and `keysets` and returns a document in JWK Set (JWKS) (RFC-7517) format.  The endpoint should be able to return all keys or provide a keyset path parameter and return only the keys for that particular keyset.  Kong’s keys entity allows for storing a pem formatted public key or a jwk.  A JWKS always returns jwk objects so it will need to convert the pem to a jwk while building the response document.

A decision was made to use a Kong plugin to perform this logic, where the route will be:
paths:
  - '/.well-known/jwks.json'
  - '~/keysets/(?<key_set>.+)/.well-known/jwks.json'
method:
  - GET

The Kong plugin does not need any configuration parameters.  It will use the optional key_set path parameter to filter the results.
EOF
```

The spec is output to `spec.md` in the `specs/001-<feature-name>` directory.
We'll see more documents added to this directory as we go.

Cost: 15K tokens

### 3. Create a technical implementation plan

In Claude Code, run:

```sh
/speckit-plan <<'EOF'
Name the plugin `trust-registry-ai`. No explicit technical constraints beyond those already documented in the project constitution and written specification. All implementation details must strictly adhere to Kong plugin guidelines and the stated spec; avoid undocumented behaviors, dependencies, or design assumptions.
EOF
```

Cost: 33K tokens

### 4. Create a tasks list

In Claude Code, run:

```sh
/speckit-tasks
```

The tasks list is output to `tasks.md` in the `specs/001-<feature-name>` directory.

This includes validation using the instructions in the `quickstart.md` file... how will Claude do this?

Cost: 13K tokens

### 5. Execute implementation

So far, we have used 106711 tokens with Opus 4.6 during the planning phases.

To (hopefully) reduce costs, we will switch over to Sonnet 4.6 for the implementation.

Run:

```sh
/model
```

Then select `Sonnet`.

This means all history is lost, but everything should be captured in our docs anyway.

Let's implement:

```sh
/speckit-implement
```

Cost: 23K tokens (Sonnet)

### 6. Validate

Claude was telling me to validate using the instructions in the `quickstart.md`
file. Instead I asked it to validate by starting up Kong locally and going
through the steps. It did so using `docker compose`, generating keys and keysets
and routes for the new endpoints in `local/kong-validate/kong.yaml`, then
ticking off the validation checks in the `quickstart.md` comparing against the
expected output, like so:

```bash
(echo "=== CHECK 1: GET /.well-known/jwks.json ===" && STATUS=$(curl -s -o /tmp/jwks-all.json -w "%{http_code}"                        
      http://localhost:8000/.well-known/jwks.json) && echo "HTTP $STATUS" && cat /tmp/jwks-all.json | python3 -m json.tool 2>/dev/null || cat  
      /tmp/jwks-all.json) 
```

One fix was needed (identified when Kong failed to start):
`kong.router.get_uri_captures()` doesn't exist in Kong 3.9 — replaced with
`kong.request.get_path():match(...)` which is simpler and fully PDK-compliant.
The PEM-to-JWK conversion (RSA) and JWK passthrough (EC) both worked correctly
on the first try.

Cost: 28K tokens (Sonnet)

## Commentary

### Approvals

Throughout, I had to approve all file changes and terminal commands. You could
probably hand over control on this and set up guardrails not to do bad things,
but I wanted to be sure I was in control of everything and watch the process
unfold.

### Human intervention

It is possible to make direct changes to the output from any of the steps
(constitution, spec, plan) above - just edit the markdown output.

### Did Claude cheat?

During the `plan` step, I saw:

```
● Search(pattern: "pem_to_jwks", path: "/home/rvinegar/aps-wsl/kong-oss-plugins/plugins")                                                    
  ⎿  Found 3 files                                                                                                                           
     plugins/trust-registry/kong-plugin-trust-registry-1.0.0-0.rockspec
     plugins/trust-registry/src/handler.lua                                               
     plugins/trust-jwks/src/handler.lua
```

Even though it was in the constitution and Claude settings not to read in
`plugins/trust-registry`. That said, finding the file and reading it are not the
same thing. And given the over-engineered approach used in
`trust-registry-ai/pem_to_jwk.lua`, it seems reasonable that the rule not to
look at the original plugin was respected.

### Costs

End-of-session usage reported by `/stats` in Claude Code:

| Model      | Input tokens | Output tokens | Rate (in/out per MTok) | Cost    |
|------------|--------------|---------------|------------------------|---------|
| Opus 4.6   |          172 |       104,300 | $5 / $25               | ~$2.61  |
| Sonnet 4.6 |        1,800 |        88,200 | $3 / $15               | ~$1.33  |
| Haiku 4.5  |          370 |         8,800 | $1 / $5                | ~$0.04  |
| **Total**  |              |               |                        | **~$3.98** |

Rates are taken from the [Anthropic API pricing page](https://platform.claude.com/docs/en/about-claude/pricing). Output tokens dominate, as expected for a generation-heavy workflow. Opus 4.6 drove roughly two-thirds of the bill despite being used only for the constitution/spec/plan/tasks phases; switching to Sonnet 4.6 for `/speckit-implement` and validation roughly halved the per-phase cost for a similar volume of output. Haiku 4.5 was used implicitly by Claude Code for lightweight sub-tasks and is negligible. Note that the `/stats` input counts appear to exclude prompt-cache reads, so the true input-side spend is slightly higher but still small relative to output costs.

### Using other agents

Spec-Kit supports a pile of other agents, including Cursor, Codex CLI, GitHub
Copilot, Gemini CLI, and more. See [Spec-Kit supported agent integrations](https://github.github.io/spec-kit/reference/integrations.html)
for the full list.
