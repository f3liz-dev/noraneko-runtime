# Pull Upstream Workflow

**File**: `misc-pull-upstream.yml`

## Function

Sync upstream Firefox changes daily, create/update PR.

## Triggers

- **Schedule**: Daily 11:40 AM UTC (8:40 PM JST)
- **Manual**: On demand

## Process

1. Get versions: Current vs upstream
2. Check for existing sync PR
3. Clone upstream (--depth 200)
4. Find latest released commit (before version bump)
5. Sync files: `rsync --delete` (exclude .github, noraneko, branding)
6. Normalize patches
7. Validate: `git apply --check` on all patches
8. Commit changes
9. Create/update PR with version info

## Release Commit Detection

The latest `FIREFOX_<major>_<minor>[_<patch>]_RELEASE` tag (betas and ESR excluded) is the source of truth. The tag is fetched into the shallow `release` clone and checked out; `browser/config/version.txt` at that commit is the new version.

Walking the `release` branch for "the last commit before a version bump" is wrong: after a release the branch keeps receiving unshipped commits for the next dot release while `version.txt` still says the old version (2026-09-04: 155.0 tag = `d065a04`, the walk picked `6c6177d`, three commits later).

## Version Detection

Parse `browser/config/version.txt`:
- MAJOR.MINOR.PATCH (e.g., 134.0.3)
- Detect: MAJOR, MINOR, PATCH, or no_version_change

## PR Management

**New PR**: `sync: {TYPE} upstream {OLD} → {NEW}`
**Update PR**: Append version history, update title

**Failed patches**: Listed in PR with ⚠️ warning

## Bot

`@f3liz-bot patch` on PR → generates patches in `.github/patches/upstream/`

## Overlays (3-way merge)

`.github/overlays/<path>` is merged as `ours` against `base` = the file at `UPSTREAM_BASE` in the **upstream** clone, and `theirs` = the new upstream file.

- If `UPSTREAM_BASE` is already the detected release commit, the run stops early (no rsync, no merge, no commit).
- If the base commit is not reachable, the run fails. Merging without a base makes every file a whole-file conflict.
- Conflicted files are committed with markers so `@f3liz-bot resolve` can work on them. A file that still has markers is **skipped** on later runs (not re-merged), so markers never nest.
- `UPSTREAM_BASE` only advances when no conflict remains.
- One comment per conflicted file (bodies capped at 60,000 chars, 1.5 s apart).
