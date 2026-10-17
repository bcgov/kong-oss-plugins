# Plugin bundle releases

APS-5011 introduces independent, immutable **repository bundle** versions for the plugins consumed by the SDX edge image. This does not rewrite each plugin's existing LuaRocks rockspec version. Individual rockspec/package releases remain separate; the bundle tag identifies the exact compatible source snapshot.

`.github/release/components.json` declares the `kong-oss-plugins` source component. Namespaced tags use `kong-oss-plugins/vX.Y.Z`; GitHub releases contain scoped commit notes, the promotion PR, an exact commit, a source archive and its SHA-256 receipt. Historical unscoped `v1.x.y-N` tags are preserved. The explicit initial baseline is 1.5.0 (first patch -> kong-oss-plugins/v1.5.1); confirm this baseline before activating the workflow. It is not a claim that a new stable 1.5.0 release has been published.

## Branch and version flow

1. Feature/** PRs into dev request automatic squash merge after required checks/reviews. The metadata-only workflow excludes forks and drafts; it does not run PR code with a merge token. Busted/integration tests now cover dev pushes/PRs as well as feature branches and PRs to main.
2. Promote dev to main through a reviewed PR with exactly one `release=major`, `release=minor` or `release=patch` label. The release-policy check previews the next bundle version. Multiple/missing/invalid labels block validation. Use a merge commit for this long-lived branch promotion; squash/rebase promotion is rejected.
3. On merge, the source bundle, immutable namespaced tag and GitHub notes are created from the exact merge commit. The release job runs directly; it does not depend on tag-triggered workflows. Missing labels or wrong branch ancestry stop publication.
4. In aps-devops, update `KONG_PLUGINS_REVISION` to the released bundle's full commit in a reviewed PR. Build/test the edge image, then release the edge image and chart. There is no automatic cross-repository dependency update or deployment.

Changes to plugins, testsuite, Dockerfiles or shared release/CI tooling select a bundle release. Documentation-only changes outside those paths do not release. Source archive checksums and revision receipts are attached before a draft release becomes public. A retry retains the tag/version for the same commit; already published releases are checked and not amended. Tag/revision conflicts stop the job.

## Rollout prerequisites

The draft workflow PR targets feature/mtls because that is the existing integration branch and **dev does not currently exist**. Review/merge the workflow changes there, then carry them through the separately reviewed feature/mtls -> dev migration and eventual dev -> main promotion. This PR does not create dev, migrate the 135-commit branch, change main's default status or publish a release. Release events remain dormant until the dev -> main path exists.

Before activation, confirm the APS Technical Change Management Process and baseline, create release labels, enable repository auto-merge/squash merging, allow merge commits into main and protect dev/main with required reviews and current Busted/integration/release-tooling checks. Require `Release policy / plan` on main promotions. The auto-merge workflow fails if classic dev protection has no required checks/reviews; ruleset-only protection needs an adapted check. Auto-merge was disabled at audit time (October 16, 2026).

Configure `AUTOMERGE_TOKEN` as a bot or GitHub App credential that can read branch protection and enable/perform merges without bypassing requirements. Supplying/refreshing installation tokens and changing settings are external setup steps. A non-GITHUB_TOKEN merge credential is needed to trigger subsequent dev workflows; see [GitHub token event behavior](https://docs.github.com/en/actions/concepts/security/github_token). Validate contents-write rights for release publication. No external permission changes are included here.

Serialize promotions: wait for one release workflow before merging the next. GitHub concurrency is not a durable queue (one active/one pending); repeated promotions may replace pending runs. For urgent fixes, review the fix through dev and promote it, or apply the approved emergency procedure and synchronize main back into dev. Rollback means consuming a prior approved bundle commit in aps-devops, not moving tags.

## Validation

Run `python3 -m unittest discover -s tests/release -v`, `actionlint` and the repository's existing Busted/integration CI. Planner tests use temporary Git repositories and exercise exact merge commits, invalid labels, isolated component selection, retry versions and tag collisions. Publication tests mock GitHub and exercise artifact identity, collision and upload-failure handling. No live release is required for these tests; a controlled release rehearsal remains a rollout gate.
