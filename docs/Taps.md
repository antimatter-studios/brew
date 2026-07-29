---
last_review_date: "2026-07-18"
---

# Taps (Third-Party Repositories)

The `brew tap` command adds repositories that Homebrew can use for formulae, casks and external commands.
The one-argument form assumes a repository on GitHub, while the two-argument form accepts any URL supported by Git.

Code in a tap can run with your user's privileges.
Read [Tap Trust](Tap-Trust.md) before using a non-official tap.

## The `brew tap` command

`brew tap` without arguments lists the currently tapped repositories.
It prints nothing when no taps are installed.

```console
$ brew tap
petere/postgresql
```

`brew tap <user>/<repository>` clones `https://github.com/<user>/homebrew-<repository>` into Homebrew's tap directory.
Homebrew updates the repository during `brew update`.

Tapping a repository does not grant whole-tap trust.
Install a fully qualified item to trust only that item:

```sh
brew tap user/repository
brew install user/repository/formula
```

Alternatively, use `brew trust` first to access an item by its short name:

```sh
brew trust --formula user/repository/formula
brew install formula
```

See [Tap Trust](Tap-Trust.md#installing-from-a-tap) for formula, cask, command and whole-tap trust options.

`brew tap <user>/<repository> <URL>` clones a repository from the specified Git URL without assuming GitHub or a particular transport.

`brew tap --repair` adds missing tap manpage and shell-completion symlinks.
It also corrects remote references for taps whose upstream default branch has been renamed.

`brew untap <user>/<repository> [...]` removes one or more taps.
Homebrew deletes the local repositories and no longer loads their contents.

## Repository naming conventions

On GitHub, a repository must be named `homebrew-<repository>` to use the one-argument form of `brew tap`.
The `homebrew-` prefix can be omitted from the command:

```sh
brew tap username/foobar
```

This command maps to `https://github.com/username/homebrew-foobar`.
The two-argument form does not impose this naming convention because the full URL is explicit.

## Filtering tap contents

A tap repository can declare which of its paths Homebrew needs by adding a `Tapfile` to its root.
This helps large repositories, such as a monorepo that doubles as its own tap, where a full clone would be much larger than the formulae and casks it contains.

A `Tapfile` holds `gitignore`-style patterns, one per line.
Blank lines and lines beginning with `#` are ignored.
A leading `/` anchors a pattern to the repository root and a leading `!` negates an earlier pattern:

```
/Formula/
!/Formula/internal/
```

Homebrew passes these patterns to Git's sparse checkout unchanged, so Git performs the matching.
The patterns are data and are never executed, and they can only select paths within the tap itself.

When a tap contains a `Tapfile`, Homebrew clones the repository without file contents and then materialises only the matching paths, so unmatched files are never downloaded.
The `Tapfile` itself is always materialised.
Paths added by later commits are matched automatically.

A tap without a `Tapfile` is cloned and materialised in full, exactly as before.
Filtering also needs a Git version and a server that support partial clone and sparse checkout.
When either does not, Git falls back to a full clone.

Editing a tap's `Tapfile` changes which patterns apply.
Homebrew re-reads it during `brew update`, so an already-tapped repository follows the patterns in its current commit.
Removing a `Tapfile` materialises the tap in full again.

## Duplicate names

A tap may contain a formula with the same name as one in `homebrew/core`.
Use the fully qualified name to select the formula from a particular tap:

```sh
brew install vim
brew install username/repository/vim
```

The first command installs `vim` from `homebrew/core`.
The second installs the formula from `username/repository` and trusts that individual formula.

Give customised formulae distinct names when users should be able to select them without qualification.
Dependencies of `homebrew/core` formulae cannot be replaced with formulae from other taps.
