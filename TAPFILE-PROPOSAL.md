<!-- DRAFT — to be posted as a GitHub Discussion, "Ideas" category, on Homebrew/brew.
     Reference implementation lives in THIS fork: branch `tap-filter`
     (commits f84d12c867 "Add Tapfile, a repo-defined tap content filter"
            + ddd47b8e06 "tap: honour a tap's Tapfile via partial clone and sparse checkout").
     The `deployed` branch is master + that feature, as run on our machines. -->

# Idea: repo-defined tap filtering via a root `Tapfile` (partial clone + sparse checkout for taps)

## Problem

`brew tap <user>/<repo> <url>` always performs an unconditional full clone of the tap
repository. For classic dedicated tap repos that's fine — they contain little besides
`Formula/`. But a tap doesn't have to be a dedicated repo: a team can (and we do) serve
formulae straight out of a production monorepo, so that `brew install` always tracks the
same repo the binaries are built from. In that case every developer machine clones the
entire monorepo just to get a handful of formula files.

Measured on our production monorepo served as a tap:

| | on-disk cost |
|---|---|
| `brew tap` today (full clone) | **929 MB** |
| the same tap through the reference implementation below | **1.5 MB** |

A ~620x reduction, per machine — and the gap grows with the repo's history forever after.

## Prior art

Homebrew already adopted exactly this git machinery for formula **source** downloads:
Homebrew/brew#13188 (issue) and Homebrew/brew#14035 (PR, merged Oct 2022) added partial
clone + sparse checkout to `GitDownloadStrategy` via `only_path:`, for checkouts where
only a subdirectory is needed. Taps were left out of that work, and as far as I can find
(I searched issues and discussions) nothing existing covers applying it to taps.

## Proposed design: the filter belongs to the repo, not the user

A root-level `Tapfile` in the tap repository declares which paths brew needs, via a
`tap_filter` block:

```ruby
tap_filter do |path|
  path.start_with?("Formula/")
end
```

Ownership is the crux of the design:

- The **user needs zero knowledge of the repo layout**. `brew tap` stays a two-argument
  command; no flags to remember or get wrong.
- The filter is **versioned with the repo** and follows it through `brew update` — when
  the repo reorganizes, the same commit that moves the formulae updates the filter. A CLI
  flag (`brew tap --sparse-paths=...`) would rot the moment the layout changes, and every
  already-tapped machine would break.

### Mechanics

1. `brew tap` clones with `--filter=blob:none --no-checkout` — the full path/tree
   skeleton, no file contents.
2. Brew reads the root `Tapfile` (one small blob fetched on demand). No `Tapfile`?
   Plain checkout — byte-identical behavior to today.
3. The `tap_filter` block is evaluated against the repo's path list (`git ls-tree -r
   --name-only HEAD` — tree metadata is already local, so this costs no downloads) to
   produce the approved path set. `Tapfile` itself is always included.
4. `git sparse-checkout` is set to the approved paths; only those blobs are ever
   downloaded.
5. On tap update, the `Tapfile` is re-read from the new HEAD and the sparse set
   re-applied — so a filter change (or removal) in the repo propagates to every tapped
   machine on its next `brew update`.

### Compatibility

- **Repos without a `Tapfile`**: byte-identical behavior to today — full materialization,
  nothing changes for the existing tap ecosystem (verified against a control repo, see
  measured results).
- **Git servers without partial-clone/filter support**: git itself degrades gracefully to
  a full clone, so the worst case is exactly today's behavior.
- **Old brew versions tapping a repo that has a `Tapfile`**: the file is inert — taps
  tolerate arbitrary files, so nothing breaks in either direction. Purely additive.
- Partial clones are not shallow clones: full history is present (bodiless), so the
  existing shallow-tap handling is untouched.

### Trust note

A `Tapfile` is Ruby evaluated by brew, so it's fair to ask whether that widens the attack
surface. It doesn't introduce a new trust boundary: a formula is already arbitrary Ruby
executed on the user's machine, and taps already ship executable command extensions
(`cmd/`). Tapping a repo has always meant trusting its Ruby; the `Tapfile` runs at the
same trust level and does strictly less (it only selects paths).

## Reference implementation

Working in this fork: `antimatter-studios/brew`, branch `tap-filter` — commits
`f84d12c867` (Tapfile evaluation, `Library/Homebrew/tapfile.rb`) and `ddd47b8e06`
(`Tap#install`/update integration). ~170 lines total, `brew style` clean, reusing the
partial-clone plumbing that #14035 introduced. Happy to be told the design is wrong in
part or whole — the fork exists so the idea can be judged against running code rather
than prose.

### Measured results (all from the fork)

- **Production monorepo as tap** (full git history, served over the git protocol with
  `uploadpack.allowfilter=true`): stock-behavior full clone **929 MB**; via `Tapfile`
  (filter = `Formula/`) the tap directory lands at **1.5 MB** including `.git`, only
  `Formula/` + `Tapfile` materialized, and `brew info <tap>/<formula>` resolves normally.
- **Synthetic repo** (one formula + 50 MB of junk data): filtered tap `.git` = **80 KB**;
  the unfiltered control (identical repo, no `Tapfile`) = 104.9 MB with all files
  materialized — i.e. no-Tapfile behavior is unchanged.
- **Update path**: after the upstream repo gained a new formula plus 10 MB more junk, the
  update re-apply materialized the new formula and kept the junk out (`.git` grew
  80 KB → 120 KB).
- **Filter removal**: deleting the `Tapfile` upstream and updating disables sparse
  checkout and fully materializes the tap — the escape hatch works.
- `brew tap` list/`brew untap`/formula resolution all behave normally on filtered taps.

## Offer

If maintainers think this direction is worth pursuing, I'll prepare a PR with tests
(unit tests for the `Tapfile` evaluation and the sparse-checkout path set, plus
integration coverage for the no-Tapfile and no-server-support fallbacks). Equally happy
to adjust the mechanism (naming, file format, opt-in strategy) to whatever fits brew's
conventions.
