#!/usr/bin/env bash
# Exercise the real helper against temporary Git history; no remote writes.
set -euo pipefail
helper="$(cd "$(dirname "$0")/.." && pwd)/.github/scripts/release-plan.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
git init -q -b main
git config user.email release-test@example.invalid
git config user.name 'Release test'
mkdir -p .github/release source other chart
cat > .github/release/components.json <<'JSON'
{"components":[
 {"name":"sdx-access-point","kind":"image","paths":["source/"],"context":".","baseline":"0.0.0"},
 {"name":"other","kind":"image","paths":["other/"],"context":"other","baseline":"1.9.0"},
 {"name":"sdx-edge","kind":"chart","paths":["chart/"],"context":"chart","baseline":"0.3.11"}
],"shared_paths":[".github/workflows/"]}
JSON
echo base > source/file
echo base > other/file
git add .
git commit -qm base
base=$(git rev-parse HEAD)
git tag sdx-access-point/v0.9.0
git tag sdx-access-point/v0.10.0
git tag other/v99.0.0
git checkout -qb dev
echo change > source/file
git commit -qam change
head=$(git rev-parse HEAD)
export GITHUB_EVENT_PATH="$fixture/event.json" GITHUB_OUTPUT="$fixture/outputs"
event() {
  jq -n --arg base "$base" --arg head "$head" --argjson labels "$1" \
    '{pull_request:{base:{ref:"main",sha:$base,repo:{full_name:"test/repo"}},head:{ref:"dev",sha:$head,repo:{full_name:"test/repo"}},labels:$labels,merged:false}}' > "$GITHUB_EVENT_PATH"
}
event '[{"name":"release=patch"}]'
bash "$helper"
jq -e 'length==2 and .[0].tag=="sdx-access-point/v0.10.1" and .[1].tag=="sdx-edge/v0.3.12"' release-plan.json >/dev/null
grep -q 'has_edge=true' "$GITHUB_OUTPUT"
grep -q 'has_images=false' "$GITHUB_OUTPUT"
# No changed paths means no release; a fork cannot supply a promotion.
jq --arg head "$head" '.pull_request.base.sha=$head' "$GITHUB_EVENT_PATH" > empty.json
mv empty.json "$GITHUB_EVENT_PATH"
bash "$helper"
jq -e 'length==0' release-plan.json >/dev/null
event '[{"name":"release=patch"}]'
jq '.pull_request.head.repo.full_name="fork/repo"' "$GITHUB_EVENT_PATH" > fork.json
mv fork.json "$GITHUB_EVENT_PATH"
if bash "$helper" >/dev/null 2>&1; then echo 'Accepted fork promotion' >&2; exit 1; fi
event '[{"name":"release=minor"}]'
bash "$helper"
jq -e '.[0].version=="0.11.0" and .[1].version=="0.4.0"' release-plan.json >/dev/null
event '[{"name":"release=major"}]'
bash "$helper"
jq -e '.[0].version=="1.0.0" and .[1].version=="1.0.0"' release-plan.json >/dev/null
for labels in '[]' '[{"name":"release=patch"},{"name":"release=minor"}]' '[{"name":"release=invalid"}]'; do
  event "$labels"
  if bash "$helper" >/dev/null 2>&1; then echo "Accepted invalid labels: $labels" >&2; exit 1; fi
done
event '[{"name":"release=patch"}]'
git checkout -q main
git merge -q --no-ff dev -m promotion
sha=$(git rev-parse HEAD)
jq --arg sha "$sha" '.pull_request.merged=true | .pull_request.merge_commit_sha=$sha' "$GITHUB_EVENT_PATH" > merged.json
mv merged.json "$GITHUB_EVENT_PATH"
bash "$helper"
git tag sdx-access-point/v0.10.1
git tag sdx-edge/v0.3.12
bash "$helper"
jq -e '.[0].version=="0.10.1" and .[1].version=="0.3.12"' release-plan.json >/dev/null
# A squash/rebase result must not silently substitute for a promotion merge.
git checkout -q dev
jq --arg sha "$head" '.pull_request.merge_commit_sha=$sha' "$GITHUB_EVENT_PATH" > wrong.json
mv wrong.json "$GITHUB_EVENT_PATH"
if bash "$helper" >/dev/null 2>&1; then echo 'Accepted promotion without merge ancestry' >&2; exit 1; fi
echo 'Release selection, dependency, version, label and retry checks passed.'
