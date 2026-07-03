#!/bin/bash
# sync-upstream.sh — merge upstream Homebrew/brew into this fork's `deployed`
# branch, from a machine you control.
#
# Why this is a local script and not CI: syncing requires a credential that can
# push `.github/workflows/*` changes (upstream touches them constantly), which
# the Actions `GITHUB_TOKEN` structurally cannot do — there is no `workflows`
# key in a workflow `permissions:` block. The only CI fix is storing a PAT or
# deploy key as a repo secret, and we deliberately don't: `deployed` is what
# team machines pull via `brew update`, and brew executes Ruby straight from
# that checkout, so write access to `deployed` is remote code execution on
# every team machine. We are not putting such a credential in a job that
# ingests ~800 commits/week of third-party code. A local push over SSH is not
# subject to the workflow-scope restriction, so this works where CI can't.
#
# Two invariants, inherited from the CI job this replaces:
#
#   1. History on `deployed` only ever grows. We merge (never rebase or
#      force-push) so every client `git pull` / `brew update` is a plain
#      fast-forward. Rewriting `deployed` would strand every machine on a
#      diverged history.
#
#   2. On conflict, stop. No auto-resolution, nothing pushed. Machines stay on
#      the previous known-good state until a human resolves it.
#
# Usage:
#   ./sync-upstream.sh              # merge + verify, then stop for review
#   ./sync-upstream.sh --push       # same, and push once verification passes
set -euo pipefail

UPSTREAM_URL="https://github.com/Homebrew/brew.git"
BRANCH="deployed"
PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

cd "$(dirname "$0")"

[[ -z "$(git status --porcelain)" ]] ||
  {
    echo "error: working tree is dirty — commit or stash first" >&2
    exit 1
  }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "${BRANCH}" ]] ||
  {
    echo "error: not on ${BRANCH} (on $(git rev-parse --abbrev-ref HEAD))" >&2
    exit 1
  }

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "${UPSTREAM_URL}"

echo "==> Fetching upstream"
git fetch upstream master

if git merge-base --is-ancestor upstream/master HEAD
then
  echo "==> Already up to date with upstream/master — nothing to do"
  exit 0
fi

echo "==> Merging upstream/master into ${BRANCH} ($(git rev-list --count HEAD..upstream/master) commits)"
# Invariant 2: a conflict here leaves the merge in progress and exits non-zero.
# Resolve by hand keeping Tapfile semantics, then re-run with --push.
git merge --no-edit upstream/master

# A textually clean merge is NOT proof the fork still works: upstream has
# silently broken the Tapfile feature before by adding `--end-of-options` to
# its `git clone` invocation, which stranded our `--filter=blob:none` flags in
# positional-argument territory. Always verify before pushing.
echo "==> Verifying the Tapfile feature survived the merge"
[[ -f Library/Homebrew/tapfile.rb ]] ||
  {
    echo "error: tapfile.rb missing after merge — resolve before pushing" >&2
    exit 1
  }
./bin/brew typecheck
./bin/brew tests --only=tap

if [[ "${PUSH}" == true ]]
then
  echo "==> Pushing ${BRANCH}"
  # Never force-push: see invariant 1.
  git push origin "${BRANCH}"
  # Keep the fork's `master` current too, so upstream PRs branch from it.
  git push origin "upstream/master:master"
  echo "==> Done — team machines will pick this up on their next \`brew update\`"
else
  echo
  echo "==> Verified, NOT pushed. Review, then publish with:"
  echo "      git push origin ${BRANCH}"
  echo "      git push origin upstream/master:master   # keep fork master current"
fi
