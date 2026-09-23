#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
#
# github_rulesets_test.sh — verify the repository's ready-to-POST ruleset
# payloads describe the intended branch and tag protections without bypasses.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
branch_ruleset="$repo_root/.github/rulesets/Optimus-Branch.json"
tag_ruleset="$repo_root/.github/rulesets/Immutable-Tags.json"
legacy_tag_ruleset="$repo_root/.github/rulesets/tag-protection.json"
settings="$repo_root/.github/settings.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_json() {
  local file="$1"
  local filter="$2"
  local description="$3"

  jq -e "$filter" "$file" >/dev/null || fail "$description"
}

for ruleset in "$branch_ruleset" "$tag_ruleset"; do
  [[ -f "$ruleset" ]] || fail "missing ruleset payload: $ruleset"
  jq empty "$ruleset" >/dev/null 2>&1 || fail "invalid JSON in $ruleset"
  assert_json "$ruleset" \
    'keys == ["bypass_actors", "conditions", "enforcement", "name", "rules", "target"]' \
    "$ruleset contains unexpected or missing top-level fields"
  assert_json "$ruleset" \
    '.enforcement == "active" and .bypass_actors == []' \
    "$ruleset must be active and grant no bypasses"
  assert_json "$ruleset" \
    '(.rules | length) == ([.rules[].type] | unique | length)' \
    "$ruleset contains duplicate rule types"
done

assert_json "$branch_ruleset" \
  '.name == "Optimus-Branch" and .target == "branch"' \
  "branch ruleset identity or target changed"
assert_json "$branch_ruleset" \
  '.conditions.ref_name == {"include":["~DEFAULT_BRANCH"],"exclude":[]}' \
  "branch ruleset must target only the default branch"
assert_json "$branch_ruleset" \
  '([.rules[].type] | sort) == ["deletion","non_fast_forward","pull_request","required_signatures","required_status_checks"]' \
  "branch ruleset protection types changed"
assert_json "$branch_ruleset" '
  (.rules[] | select(.type == "pull_request") | .parameters) == {
    "required_approving_review_count": 2,
    "dismiss_stale_reviews_on_push": true,
    "require_code_owner_review": true,
    "require_last_push_approval": true,
    "required_review_thread_resolution": true,
    "require_extra_approval_for_unattributed_changes": true,
    "required_reviewers": [],
    "allowed_merge_methods": []
  }' "pull-request review policy changed"
assert_json "$branch_ruleset" '
  (.rules[] | select(.type == "required_status_checks") | .parameters) == {
    "strict_required_status_checks_policy": true,
    "do_not_enforce_on_create": false,
    "required_status_checks": []
  }' "required-status-check policy changed"

assert_json "$tag_ruleset" \
  '.name == "Immutable-Tags" and .target == "tag"' \
  "tag ruleset identity or target changed"
assert_json "$tag_ruleset" \
  '.conditions.ref_name == {"include":["~ALL"],"exclude":[]}' \
  "tag ruleset must cover every tag without exclusions"
assert_json "$tag_ruleset" \
  '([.rules[].type] | sort) == ["creation","deletion","non_fast_forward","required_signatures","update"]' \
  "tag ruleset protection types changed"

[[ ! -e "$legacy_tag_ruleset" ]] || \
  fail "legacy tag-protection.json conflicts with the replacement ruleset"
if grep -Eq '^branches:[[:space:]]*$' "$settings"; then
  fail "settings.yml still declares legacy branch protection alongside rulesets"
fi

echo "PASS: branch and tag ruleset payloads enforce the intended policy"
