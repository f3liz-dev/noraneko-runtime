# Pull Upstream Workflow Documentation

**File**: `misc-pull-upstream.yml`

## Purpose

Automatically syncs upstream Firefox changes from Mozilla's repository into Noraneko's codebase. Creates or updates a PR with the changes, validates that existing patches still apply, and tracks version changes.

## Why This Workflow Exists

**The Challenge**:
- Noraneko is based on Firefox (forked from mozilla-firefox/firefox)
- Firefox releases new versions regularly (every 4 weeks for minor, 1 year for major)
- Must stay up-to-date with security fixes and features
- Manual sync is time-consuming and error-prone

**The Solution**:
- Daily automated sync from upstream release branch
- Automatic PR creation with version tracking
- Patch compatibility validation
- Incremental updates (PR updated as changes accumulate)

## Triggers

```yaml
on:
  workflow_dispatch:  # Manual trigger
  workflow_call:      # Callable by other workflows
  schedule:
    - cron: '40 11 * * *'  # Daily at 11:40 AM UTC (8:40 PM JST)
```

**Why 11:40 AM UTC / 8:40 PM JST**:
- After Firefox's typical release time (early UTC morning)
- Evening in Japan (developers can review before next workday)
- Before midnight in Japan (avoids middle-of-night notifications)

## Dependencies Graph

```
misc-pull-upstream.yml (Single Job)
    │
    ├─ Repository Setup
    │   ├─→ Checkout main branch (fetch-depth: 0 for full history)
    │   └─→ Clone upstream Firefox (--depth 1 for latest only)
    │
    ├─ Version Analysis
    │   ├─→ Get current version (from browser/config/version.txt)
    │   ├─→ Get upstream version (from upstream repo)
    │   └─→ Compare versions (calculate change type: MAJOR/MINOR/PATCH)
    │
    ├─ PR Management
    │   ├─→ Check for existing PR (search by title pattern)
    │   └─→ Checkout existing PR branch (if found)
    │
    ├─ Sync Process
    │   ├─→ Sync upstream files (rsync with exclusions)
    │   ├─→ Normalize patch files (line endings, trailing newlines)
    │   └─→ Check patches compatibility (git apply --check)
    │
    ├─ Change Detection
    │   └─→ Check if there are any changes (git diff)
    │
    ├─ Branch Management (if changes exist)
    │   ├─→ Commit to existing PR branch (if PR exists)
    │   └─→ Create new PR branch (if no PR exists)
    │
    └─ GitHub PR Operations
        ├─→ Update existing PR (title + body with changelog)
        └─→ Create new PR (title + body with version info)
```

## Data Flow Between Steps

### Version Detection Flow

```
Current Repo: browser/config/version.txt
    → Example: "134.0.2"
    → Stored in: steps.old_version.outputs.version

Upstream Repo: ../upstream_release/browser/config/version.txt
    → Example: "134.0.3"
    → Stored in: steps.new_version.outputs.version

Compare:
    → Split: 134 . 0 . 2  vs  134 . 0 . 3
    → Diff:  MAJOR MINOR PATCH
    → Result: "PATCH" (only patch version changed)
    → Stored in: steps.version_diff.outputs.change_type
```

### Version Change Types

```bash
if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
  change_type="no_version_change"  # File changes only
elif [ "$OLD_MAJOR" != "$NEW_MAJOR" ]; then
  change_type="MAJOR"  # 133.x.x → 134.x.x
elif [ "$OLD_MINOR" != "$NEW_MINOR" ]; then
  change_type="MINOR"  # 134.0.x → 134.1.x
elif [ "$OLD_PATCH" != "$NEW_PATCH" ]; then
  change_type="PATCH"  # 134.0.2 → 134.0.3
else
  change_type="unknown"  # Shouldn't happen
fi
```

### File Sync with rsync

```bash
rsync -a --delete \
  --exclude='.git' \              # Don't copy git metadata
  --exclude='/.github/' \         # Don't overwrite our workflows
  --exclude='/noraneko/' \        # Don't touch Noraneko-specific code
  --exclude='/.gitmodules' \      # Don't change submodule config
  --exclude='/README.md' \        # Keep our README
  ../upstream_release/ ./
```

**What this does**:
- **-a**: Archive mode (preserves permissions, timestamps)
- **--delete**: Remove files that don't exist upstream (clean sync)
- **--exclude**: Protect Noraneko-specific files and configs

**Result**: All upstream changes copied, Noraneko customizations preserved

### Patch Validation Flow

```
For each .patch file in .github/patches/upstream/:
    │
    ├─→ Normalize (fix line endings, add trailing newline)
    │
    └─→ Check if applies cleanly
        ├─ git apply --check --ignore-space-change --ignore-whitespace
        │
        ├─ Success: Patch compatible with upstream
        │   └─→ Mark as "✓ applies cleanly"
        │
        └─ Failure: Patch conflicts with upstream
            ├─→ Mark as "✗ failed to apply"
            └─→ Add to failed patches list
```

**Output**:
- `steps.patch_check.outputs.patch_failed`: true/false
- `env.FAILED_PATCHES`: List of patch files that don't apply

## State Changes

### Repository State Before Workflow

```
noraneko_runtime/ (main branch)
├── browser/config/version.txt → "134.0.2"
├── .github/
│   └── patches/upstream/
│       ├── browser-app-profile-firefox.js.patch
│       └── [other patches]
└── [source files at version 134.0.2]
```

### After Upstream Sync

```
noraneko_runtime/ (sync/upstream-134.0.3 branch)
├── browser/config/version.txt → "134.0.3" (updated)
├── .github/
│   └── patches/upstream/
│       ├── browser-app-profile-firefox.js.patch (unchanged)
│       └── [patches validated, some may fail]
├── MOZ_README.md (moved from README.md)
└── [source files updated to 134.0.3]
```

### PR State Progression

**First sync (no existing PR)**:
```
Create: Pull Request #123
Title: "sync: PATCH upstream 134.0.2 → 134.0.3"
Body:
  ## Upstream Sync
  - Previous version: 134.0.2
  - New version: 134.0.3
  - Change type: PATCH
  
  ## Version History
  ### 134.0.3
  - Synced at: 2024-01-15T11:40:00Z
  - ✅ All patches applied successfully
```

**Second sync (PR exists, new patch version)**:
```
Update: Pull Request #123
Title: "sync: PATCH upstream 134.0.2 → 134.0.4" (updated)
Body: (original) +
  
  ### 134.0.4
  - Synced at: 2024-01-16T11:40:00Z
  - ⚠️ Patch issues detected:
    - browser-app-profile-firefox.js.patch
```

**Third sync (file changes without version change)**:
```
Update: Pull Request #123 (title unchanged)
Body: (previous) +
  
  ### File changes without version change
  - Synced at: 2024-01-17T11:40:00Z
  - ✅ All patches applied successfully
```

## Hidden Dependencies

### Git Configuration Requirements

```bash
git config user.name "f3liz-bot[bot]"
git config user.email "230694705+f3liz-bot@users.noreply.github.com"
```

**Why f3liz-bot**:
- Identifies automated commits
- Prevents triggering other workflows (bot commits)
- GitHub recognizes [bot] suffix for special handling

### dos2unix Dependency

```bash
find .github/patches/upstream -name "*.patch" \
  -exec dos2unix {} \; 2>/dev/null || true
```

**Why needed**:
- Windows developers may create patches with CRLF line endings
- Linux git apply expects LF line endings
- Normalization prevents "patch does not apply" errors
- `|| true`: Don't fail if dos2unix not installed (Linux already has LF)

### Trailing Newline Requirement

```bash
for patch_file in .github/patches/upstream/*.patch; do
  if [ -s "$patch_file" ] && \
     [ "$(tail -c1 "$patch_file" | wc -l)" -eq 0 ]; then
    echo "" >> "$patch_file"
  fi
done
```

**Why needed**:
- POSIX requires text files end with newline
- git apply expects final newline
- Some editors don't add trailing newline automatically

**What this does**:
1. Checks if file exists and non-empty (`-s`)
2. Checks if last character is newline (`tail -c1 | wc -l`)
3. If not, adds newline (`echo ""`)

### GitHub API Query Complexity

```javascript
const syncPR = pulls.data.find(pr => 
  pr.title.match(/^sync: (MAJOR|MINOR|PATCH|no_version_change) upstream/) &&
  pr.user.login.includes('bot')
);
```

**What this finds**:
- Open PRs with title matching sync pattern
- Created by bot user (not manual PRs)
- Returns first match (assumes only one sync PR exists)

**Edge case handling**:
- Multiple sync PRs: Uses first found (should be prevented by workflow logic)
- Manual sync PR: Ignored (doesn't match bot filter)
- Closed sync PR: Ignored (state: 'open' filter)

## Architecture Variations

### Branch Naming Strategy

**With version change**:
```bash
BRANCH_NAME="sync/upstream-$VERSION"
# Example: sync/upstream-134.0.3
```

**Without version change**:
```bash
BRANCH_NAME="sync/upstream-no-version-$(date +%Y%m%d-%H%M%S)"
# Example: sync/upstream-no-version-20240115-114000
```

**Why different naming**:
- Version changes: Use semantic name (easier to track)
- No version changes: Use timestamp (avoids conflicts)

### Commit Message Variations

**With version change**:
```bash
git commit -m "sync: upstream gecko-dev $VERSION"
# Example: "sync: upstream gecko-dev 134.0.3"
```

**Without version change**:
```bash
git commit -m "sync: upstream gecko-dev (file changes without version change)"
```

**Why different messages**:
- Version changes: Clear what version synced to
- No version changes: Explicit that it's just file updates

## Process Logic

### Version Comparison Algorithm

```bash
IFS='.' read -r OLD_MAJOR OLD_MINOR OLD_PATCH <<< "$OLD_VERSION"
IFS='.' read -r NEW_MAJOR NEW_MINOR NEW_PATCH <<< "$NEW_VERSION"
```

**Example**:
```
OLD_VERSION="134.0.2"
    ↓ Split by '.'
OLD_MAJOR=134, OLD_MINOR=0, OLD_PATCH=2

NEW_VERSION="134.1.0"
    ↓ Split by '.'
NEW_MAJOR=134, NEW_MINOR=1, NEW_PATCH=0

Compare:
    OLD_MAJOR (134) == NEW_MAJOR (134) → Not major change
    OLD_MINOR (0) != NEW_MINOR (1) → MINOR change!
```

### Incremental PR Updates

**Why update existing PR instead of creating new one**:
- Keeps review history
- Single PR for entire release cycle
- Easier to track accumulated changes
- Reduces PR clutter

**When new PR is created**:
1. No existing sync PR found
2. Previous sync PR was closed/merged
3. Different change type (MAJOR vs MINOR vs PATCH)

**When existing PR is updated**:
1. Found matching open sync PR
2. New commits pushed to same branch
3. PR description appended with new version info

### Patch Failure Handling

**Non-blocking**:
```bash
HAS_FAILED=0
for patch_file in *.patch; do
  if git apply --check "$patch_file"; then
    echo "✓ applies cleanly"
  else
    echo "✗ failed to apply"
    HAS_FAILED=1
  fi
done

# Set output but don't exit
echo "patch_failed=$HAS_FAILED" >> $GITHUB_OUTPUT
```

**Why non-blocking**:
- Patch failures don't prevent PR creation
- PR description shows which patches failed
- Allows developers to fix patches before merge
- Better than silent failure

## When Timing Is Critical

### Upstream Clone Depth

```bash
git clone -b release --single-branch \
  https://github.com/mozilla-firefox/firefox \
  --depth 1 ../upstream_release
```

**--depth 1 benefits**:
- Downloads only latest commit (not full history)
- Saves time: ~5 minutes vs ~30 minutes
- Saves bandwidth: ~500 MB vs ~3 GB
- Sufficient for sync (only need latest files)

**Trade-off**:
- Cannot access commit history
- Cannot cherry-pick specific commits
- For sync purposes, this is acceptable

### Working Directory Context

```yaml
defaults:
  run:
    working-directory: ./noraneko_runtime
```

**Why needed**:
- Checkout uses path: noraneko_runtime
- All commands expect to run in this directory
- Default working directory prevents cd commands in every step

**Without this**:
```bash
cd noraneko_runtime  # Would need this in every step
git status
```

## When Steps Can Be Skipped

### Conditional PR Update

```yaml
- name: Update existing PR
  if: steps.version_diff.outputs.change_type != 'none' && env.UPDATE_EXISTING == 'true'
```

**Skipped when**:
- No version change AND no file changes (`change_type == 'none'`)
- Creating new PR instead of updating (`UPDATE_EXISTING == 'false'`)

### Conditional PR Creation

```yaml
- name: Create new Pull Request
  if: steps.check_changes.outputs.has_changes == 'true' && 
      env.UPDATE_EXISTING == 'false' && 
      env.BRANCH_NAME != ''
```

**Skipped when**:
- No changes detected
- Updating existing PR instead
- Branch name not set (shouldn't happen)

### Early Exit Logic

```bash
- name: Check if there are any changes
  id: check_changes
  run: |
    if git diff --quiet --exit-code; then
      echo "has_changes=false" >> $GITHUB_OUTPUT
      echo "No changes from upstream."
    else
      echo "has_changes=true" >> $GITHUB_OUTPUT
    fi
```

**If no changes**:
- Subsequent commit/push steps skipped
- No PR created or updated
- Workflow completes successfully (exit 0)

## Common Scenarios

### Scenario 1: Regular Patch Version Update
```
Day 1: Firefox 134.0.2 released
Day 1 11:40 UTC: Workflow creates PR #123 (sync: PATCH 134.0.1 → 134.0.2)
Day 2-7: No upstream changes
Day 8: Firefox 134.0.3 released
Day 8 11:40 UTC: Workflow updates PR #123 (sync: PATCH 134.0.1 → 134.0.3)
```

### Scenario 2: Minor Version Update
```
Day 1: Firefox 134.0.5 (current)
Day 15: Firefox 134.1.0 released (minor bump)
Day 15 11:40 UTC: Workflow updates PR #123 (sync: MINOR 134.0.1 → 134.1.0)
```

### Scenario 3: File Changes Without Version
```
Day 1: Firefox 134.0.2 (version unchanged)
Day 1: Upstream fixes typo in README
Day 1 11:40 UTC: Workflow updates PR (adds "file changes without version change")
```

### Scenario 4: Patch Failure
```
Day 1: Firefox 135.0.0 released
Day 1: Upstream refactored file that patch modifies
Day 1 11:40 UTC: Workflow creates PR with ⚠️ warning:
  "Patch issues detected:
   - browser-app-profile-firefox.js.patch"
Developer: Reviews conflict, updates patch file, pushes fix
```

## Monitoring & Debugging

### Success Indicators
- PR created/updated with ✅ checkmark
- All patches apply cleanly
- Version number incremented correctly

### Warning Signs
- ⚠️ Patch issues detected in PR description
- Multiple sync PRs open (should be only one)
- Version change type "unknown" (parsing error)

### Debugging Steps

**Check current version**:
```bash
cat browser/config/version.txt
```

**Manually sync to test**:
```bash
git clone -b release --depth 1 \
  https://github.com/mozilla-firefox/firefox /tmp/ff
rsync -a --delete \
  --exclude='.git' --exclude='/.github/' --exclude='/noraneko/' \
  /tmp/ff/ ./
```

**Test patch compatibility**:
```bash
for patch in .github/patches/upstream/*.patch; do
  git apply --check "$patch" && echo "✓ $patch" || echo "✗ $patch"
done
```

## Related Workflows

- **autodiff-per-file-pr.yml**: Generates patches that this workflow validates
- **daily-build.yml**: Uses synced codebase for builds
- **common-build.yml**: Applies patches during build

## Related Files

- **browser/config/version.txt**: Version tracking file
- **.github/patches/upstream/**: Patches validated by this workflow
- **MOZ_README.md**: Upstream README (preserved during sync)
