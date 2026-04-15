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

1. Install Claude Code

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

```sh
claude --verbose --model claude-opus-4-6


1. Establish the project constitution (used Sonnet 4.6)

```sh
claude /speckit-constitution <<'EOF'
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

1. 