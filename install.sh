#!/bin/bash
# install.sh — switch an existing Homebrew installation to the antimatter-studios fork
# (drop-in: same `brew` command, same prefix, all installed packages untouched).
#
# The fork is upstream Homebrew plus ONE feature: Tapfile tap-content filtering —
# a tap repo may ship a `Tapfile` declaring which of its paths brew materializes,
# so tapping a large monorepo costs ~MBs instead of a full clone (measured:
# 929MB -> 1.5MB). Repos without a Tapfile behave byte-identically to stock brew.
# The `deployed` branch is upstream master + the feature, merged weekly by CI.
#
# Install:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/antimatter-studios/brew/deployed/install.sh)"
#
# Revert to stock brew at any time (also printed at the end of a successful run):
#   git -C "$(brew --repository)" remote set-url origin https://github.com/Homebrew/brew.git
#   git -C "$(brew --repository)" fetch origin
#   git -C "$(brew --repository)" remote set-head origin --auto
#   git -C "$(brew --repository)" config --unset homebrew.devcmdrun
#   brew update
set -euo pipefail

FORK_URL="https://github.com/antimatter-studios/brew.git"
BRANCH="deployed"

command -v brew >/dev/null 2>&1 \
  || { echo "error: no existing Homebrew install found — install stock brew first (https://brew.sh), then re-run." >&2; exit 1; }
BREW_REPO="$(brew --repository)"
[ -d "${BREW_REPO}/.git" ] \
  || { echo "error: ${BREW_REPO} is not a git checkout (unsupported Homebrew install)" >&2; exit 1; }

echo "==> Switching ${BREW_REPO} to ${FORK_URL} (branch: ${BRANCH})"
git -C "${BREW_REPO}" remote set-url origin "${FORK_URL}"
git -C "${BREW_REPO}" fetch --tags --force --quiet origin

# Steer brew's own updater at the fork, so `brew update` keeps this machine on it:
#  - origin/HEAD -> deployed: update.sh derives its branch from
#    `git symbolic-ref refs/remotes/origin/HEAD`
#  - homebrew.devcmdrun: without it brew pins itself to the newest stable TAG on
#    update (HOMEBREW_UPDATE_TO_TAG), which would silently reset this machine off
#    the fork branch — and off the feature.
git -C "${BREW_REPO}" remote set-head origin "${BRANCH}"
git -C "${BREW_REPO}" config homebrew.devcmdrun true

git -C "${BREW_REPO}" checkout --force -B "${BRANCH}" "origin/${BRANCH}" --quiet

# Verify the feature actually landed before declaring success.
[ -f "${BREW_REPO}/Library/Homebrew/tapfile.rb" ] \
  || { echo "error: tapfile.rb missing after checkout — aborting (brew itself still works; see the revert block above)" >&2; exit 1; }

echo "==> $(brew --version | head -1)"
echo
echo "Done — drop-in switch complete: same brew command, same prefix, packages untouched."
echo "New capability: taps that ship a Tapfile clone only their approved paths."
echo
echo "Revert to stock brew at any time:"
echo '  git -C "$(brew --repository)" remote set-url origin https://github.com/Homebrew/brew.git'
echo '  git -C "$(brew --repository)" fetch origin && git -C "$(brew --repository)" remote set-head origin --auto'
echo '  git -C "$(brew --repository)" config --unset homebrew.devcmdrun'
echo '  brew update'
