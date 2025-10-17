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
3. Clone upstream (--depth 1)
4. Sync files: `rsync --delete` (exclude .github, noraneko, branding)
5. Normalize patches
6. Validate: `git apply --check` on all patches
7. Commit changes
8. Create/update PR with version info

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
