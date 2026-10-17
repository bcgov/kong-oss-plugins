# Plugin bundle releases

Use one repository bundle version, tagged `kong-oss-plugins/vX.Y.Z`. Existing individual LuaRocks rockspec versions and historical tags remain unchanged. GitHub provides the source archives automatically.

Feature PRs into dev request squash auto-merge through `gh pr merge --auto --squash`; GitHub enforces required checks/reviews. Drafts and forks are excluded. Existing Busted/integration tests cover feature/dev builds and main promotion PRs.

Promote dev -> main through a reviewed merge-commit PR with exactly one `release=major`, `release=minor` or `release=patch` label. The small `.github/scripts/release-plan.sh` helper uses `git diff` and the standard `semver` CLI to select the bundle and increment its own latest namespaced tag. `.github/release/components.json` records paths and the initial 1.5.0 baseline (first patch -> 1.5.1); review the baseline before activation.

On merge, the workflow creates the Git tag at the exact merged commit, obtains notes with `git log`, and calls `gh release create`. There is no custom GitHub client, archive builder or publication engine. Existing tags must identify the same commit; already published releases are skipped. An interrupted draft is finished using `gh release edit`; tags are never moved.

In aps-devops, update `sdx/image/plugins.json` to the released tag and commit through a reviewed PR. Edge Docker builds receive `KONG_PLUGINS_REF` and `KONG_PLUGINS_REVISION`; edge publication then updates/packages/publishes its chart. Deployment and rollback remain explicit operations using approved versions.

This draft targets feature/mtls because dev does not yet exist. Carry the workflows through the separately reviewed feature/mtls -> dev migration before promoting to main. Confirm the APS Technical Change Management Process, initial version and required branch protections/reviews/CI; enable repository auto-merge and provide an App/bot `AUTOMERGE_TOKEN` without bypass rights. Permit squash into dev and merge commits into main. No settings, branch migration, merge or release is performed by this draft.

Promote one PR at a time and resolve failed publications before the next promotion. GitHub concurrency is not a durable queue. Validate with `bash tests/release.sh` (jq, Git, semver), `actionlint` and existing Busted/integration CI. A controlled publishing rehearsal remains a rollout gate.
