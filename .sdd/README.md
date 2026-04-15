# Creating plugins using spec-driven development (`spec-kit` and Claude Code)

1. Install Specify CLI

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

1. Install Claude Code (or other agent of your choice)

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

1. Initialize in an existing project

Open terminal in the project directory and run:

```sh
specify init . --ai claude
```

1. Deny Claude from reading the existing target plugin

Create or edit `.claude/settings.local.json` to include:

```json
{
  "permissions": {
    "deny": [ "Read(plugins/trust-registry)" ]
  }
}
```

1. Open Claude Code

`--verbose` shows token usage.

`--model` specifies the model to use, Opus 4.6 was chosen for planning in this
case, using default `high` effort level.

```sh
claude --verbose --model claude-opus-4-6
```

1. Establish the project constitution

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

1. Create the spec

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

1. Create a technical implementation plan

In Claude Code, run:

```sh
/speckit-plan <<'EOF'
Name the plugin `trust-registry-ai`. No explicit technical constraints beyond those already documented in the project constitution and written specification. All implementation details must strictly adhere to Kong plugin guidelines and the stated spec; avoid undocumented behaviors, dependencies, or design assumptions.
EOF
```

Cost: 33K tokens

1. Create a tasks list

In Claude Code, run:

```sh
/speckit-tasks
```

The tasks list is output to `tasks.md` in the `specs/001-<feature-name>` directory.

This includes validation using the instructions in the `quickstart.md` file... how will Claude do this?

Cost: 13K tokens

1. Execute implementation

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

1. Validate

Claude was telling me to validate using the instructions in the `quickstart.md`
file. Instead I asked it to validate by starting up Kong and going through the
steps. It did so using `docker compose`, generating keys and keysets and routes
for the new endpoints in `local/kong-validate/kong.yaml`.

One fix was needed: `kong.router.get_uri_captures()` doesn't exist in Kong 3.9 —
replaced with `kong.request.get_path():match(...)` which is simpler and fully
PDK-compliant. The PEM-to-JWK conversion (RSA) and JWK passthrough (EC) both
worked correctly on the first try.

Cost: 28K tokens (Sonnet)

## Commentary

### Intervention

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

Even though it was in the constitution and Claude settings not to read in `plugins/trust-registry`. Hmm....
