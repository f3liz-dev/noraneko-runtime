# Cleanup Large Caches Workflow Documentation

**File**: `cleanup-large-caches.yml`

## Purpose

Automatically manages GitHub Actions cache storage by deleting caches larger than a configurable threshold. Prevents hitting GitHub's 10GB total cache limit per repository.

## Why This Workflow Exists

**GitHub Actions Cache Limits**:
- **Per repository**: 10 GB total across all caches
- **Per cache**: No individual limit, but total must be under 10 GB
- **Eviction**: Least recently used (LRU) when limit exceeded

**The Problem**:
- Browser builds create large sccache caches (100+ MB each)
- Multiple branches × multiple platforms = many large caches
- Hitting 10 GB limit causes:
  - Build slowdowns (can't create new caches)
  - Automatic cache eviction (unpredictable)
  - Wasted CI time recreating caches

**The Solution**:
- Proactively delete large caches before hitting limit
- Keep only recent/small caches
- Predictable cache management

## Triggers

```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
    
  workflow_dispatch:
    inputs:
      size_threshold_mb: string (default: '1')
      dry_run: boolean (default: false)
```

**Scheduled**: Runs daily at 2 AM UTC
- Low runner usage time
- Before business hours in most timezones
- After nightly builds complete (caches created)

**Manual**: Can be triggered with custom parameters
- **size_threshold_mb**: Minimum size to delete (MB)
- **dry_run**: List caches without deleting

## Dependencies Graph

```
cleanup-large-caches.yml (Single Job)
    │
    ├─ Setup
    │   ├─→ Checkout repository (for script location)
    │   └─→ Setup Node.js 20
    │
    ├─ Script Creation
    │   └─→ Create cache cleanup script (inline JavaScript)
    │
    ├─ Dependency Installation
    │   └─→ Install @octokit/rest (GitHub API client)
    │
    └─ Execution
        └─→ Run cache cleanup (Node.js script with GitHub token)
```

**No parallelization**: Single job, sequential steps

## Data Flow Between Steps

### Input Parameters
```yaml
inputs:
  size_threshold_mb: string
    # Examples: '1' (default), '10', '0.1'
    # Converted to bytes: parseFloat(value) * 1024 * 1024
    
  dry_run: boolean
    # true: List caches only (no deletion)
    # false: Actually delete caches
```

### Environment Variables
```yaml
GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  # Provides authentication for GitHub API
  # Required permissions: actions:write
  
REPOSITORY: ${{ github.repository }}
  # Format: "owner/repo" (e.g., "f3liz-dev/noraneko-runtime")
  
SIZE_THRESHOLD_MB: ${{ inputs.size_threshold_mb || '1' }}
  # Passed to script, defaults to '1' MB
  
DRY_RUN: ${{ inputs.dry_run || false }}
  # Passed to script, defaults to false (actual deletion)
```

### Script Logic Flow

```javascript
// 1. Fetch all caches (paginated)
const caches = await octokit.paginate(octokit.rest.actions.getActionsCacheList, {
  owner, repo, per_page: 100
});

// 2. Filter by size
const largeCaches = caches.filter(cache => 
  cache.size_in_bytes > sizeThresholdBytes
);

// 3. Delete or list
if (dryRun) {
  console.log("Would delete...");  // List only
} else {
  for (const cache of largeCaches) {
    await octokit.rest.actions.deleteActionsCacheById({
      owner, repo, cache_id: cache.id
    });
  }
}
```

## State Changes

### What This Workflow Deletes

**Typical cache names** (examples):
```
sccache-linux-x86_64-1234567890        (125 MB)
sccache-windows-x86_64-0987654321      (89 MB)
Linux-build-cache-v1                   (234 MB)
Windows-pgo-build-20240115             (456 MB)
```

**After cleanup** (threshold: 1 MB):
- All caches > 1 MB deleted
- Small caches (< 1 MB) retained:
  - Configuration caches
  - Metadata caches
  - Python package caches

### File System Changes
**None** - This workflow only deletes GitHub Actions caches (cloud storage)

### Repository State Changes
**None** - No commits, no file modifications

## Hidden Dependencies

### GitHub API Rate Limits

**Authenticated requests**: 5,000 per hour
- Each cache list page: 1 request
- Each cache deletion: 1 request
- **Example**: 100 caches to delete = 1 list + 100 deletes = 101 requests

**Calculation**:
```
Max caches deletable per hour = 5000 requests / 2 requests per cache ≈ 2500 caches
```

**In practice**:
- Noraneko-runtime rarely has > 50 caches
- Rate limit not a concern for this workflow

### Required Permissions

```yaml
permissions:
  actions: write    # Required: delete caches
  contents: read    # Required: read repository info
```

**Why actions:write**:
- `deleteActionsCacheById` requires write permission
- Default `GITHUB_TOKEN` has this for repository workflows
- Forked PRs cannot run this workflow (no write access)

### Pagination Handling

**GitHub API returns max 100 items per page**:
```javascript
const caches = await octokit.paginate(octokit.rest.actions.getActionsCacheList, {
  owner, repo, per_page: 100
});
```

**octokit.paginate automatically**:
1. Fetches first page (100 caches)
2. Checks for `next` link in response
3. Fetches next page if exists
4. Repeats until all caches retrieved
5. Returns combined array

**Why this matters**:
- Repositories with > 100 caches need pagination
- Without pagination, only first 100 caches processed
- Noraneko-runtime: typically 20-50 caches (single page)

## Process Logic

### Why 1 MB Default Threshold

**Cache size distribution** (typical):
```
< 1 MB:   Configuration, metadata, small dependencies (10-20 caches)
1-10 MB:  Python packages, Node modules (5-10 caches)
10+ MB:   sccache (compiled objects), large dependencies (2-5 caches)
100+ MB:  Full build caches (1-3 caches)
```

**1 MB threshold**:
- **Conservative**: Doesn't delete useful small caches
- **Effective**: Targets large sccache and build caches
- **Safe**: Unlikely to delete wrong caches

**Alternative thresholds**:
- **0.1 MB**: Aggressive, deletes almost everything
- **10 MB**: Only targets very large caches
- **100 MB**: Only build caches, may miss medium caches

### Dry Run Mode Usage

**When to use dry run**:
```bash
# First time running: see what would be deleted
gh workflow run cleanup-large-caches.yml -f dry_run=true -f size_threshold_mb=1

# After verifying output: actually delete
gh workflow run cleanup-large-caches.yml -f dry_run=false -f size_threshold_mb=1
```

**Dry run output**:
```
Found 8 caches larger than 1 MB:

ID: 12345, Key: sccache-linux-x86_64-1234567890, Size: 125.50 MB
ID: 12346, Key: sccache-windows-x86_64-0987654321, Size: 89.25 MB
...

Would delete 8 caches totaling 847.32 MB
```

### Error Handling Strategy

**Continues on individual failures**:
```javascript
for (const cache of largeCaches) {
  try {
    await octokit.rest.actions.deleteActionsCacheById(...);
    console.log(`✅ Successfully deleted cache ${cache.id}`);
    deletedCount++;
  } catch (error) {
    console.log(`❌ Failed to delete cache ${cache.id}: ${error.message}`);
    failedCount++;
  }
}
```

**Why continue on failure**:
- One corrupted cache shouldn't block all deletions
- Cache may already be deleted (race condition)
- Permission issues for specific cache

**Final status**:
```
Successfully deleted: 7 caches
Failed to delete: 1 cache
```

## When Timing Is Critical

### Why 2 AM UTC Schedule

**Considerations**:
1. **After nightly builds**: Daily builds start at 6 AM UTC, complete by ~11 AM UTC
2. **Before morning builds**: Developers may trigger manual builds after 8 AM UTC
3. **Low contention**: Few workflows running at 2 AM UTC
4. **Cache staleness**: Day-old caches are good deletion candidates

**Time zone analysis**:
- **UTC+9 (Japan)**: 11 AM (late morning, after standup)
- **UTC+0 (UK)**: 2 AM (middle of night)
- **UTC-8 (US West)**: 6 PM previous day (evening)

**Result**: Caches cleaned before business hours in most locations

### Execution Duration

**Typical workflow time**:
```
Checkout + Setup:         ~30 seconds
Install dependencies:     ~10 seconds
Fetch caches:            ~2 seconds (1 API call)
Delete caches:           ~1 second per cache
Total:                   ~1 minute for 20 caches
```

**Maximum duration** (if deleting 100 caches):
- ~2 minutes total
- Well within GitHub Actions time limits

## When Steps Can Be Skipped

### No steps can be skipped
All steps required for workflow to function

### Early exits in script

**No caches to delete**:
```javascript
if (largeCaches.length === 0) {
  console.log(`✅ No caches found larger than ${sizeThresholdMB} MB`);
  return;  // Exit successfully
}
```

**Dry run mode**:
```javascript
if (dryRun) {
  console.log('🧪 Dry run mode - no caches will be deleted');
  console.log(`Would delete ${largeCaches.length} caches`);
  return;  // Exit without deletion
}
```

## Common Usage Scenarios

### Scenario 1: Routine Maintenance
**Trigger**: Automatic (daily at 2 AM UTC)
**Parameters**: Default (1 MB threshold)
**Result**: Removes large build caches, keeps useful small caches

### Scenario 2: Emergency Cleanup (Hitting 10 GB Limit)
```bash
# Step 1: See what's taking space
gh workflow run cleanup-large-caches.yml \
  -f dry_run=true \
  -f size_threshold_mb=0.1

# Step 2: Aggressive cleanup
gh workflow run cleanup-large-caches.yml \
  -f dry_run=false \
  -f size_threshold_mb=0.1
```

### Scenario 3: Targeted Cleanup (Specific Size)
```bash
# Only delete caches > 50 MB
gh workflow run cleanup-large-caches.yml \
  -f dry_run=false \
  -f size_threshold_mb=50
```

### Scenario 4: Branch-Specific Cleanup
**Not directly supported** - This workflow deletes based on size only

**Workaround**: Modify script to filter by cache key pattern
```javascript
const largeCaches = caches.filter(cache => 
  cache.size_in_bytes > sizeThresholdBytes &&
  cache.key.includes('old-branch')  // Add filter
);
```

## Monitoring & Debugging

### Success Indicators
```
🎉 Cache cleanup completed!
Successfully deleted: 8 caches
```

### Warning Signs
```
⚠️ Found 50 caches larger than 1 MB
```
- **Indicates**: Many large caches accumulating
- **Action**: Consider more aggressive threshold or manual cleanup

### Error Indicators
```
Failed to delete: 5 caches
```
- **Causes**: Permission issues, caches already deleted, rate limits
- **Action**: Check workflow logs for specific error messages

### Dry Run Output Analysis

**Example output**:
```
Found 8 caches larger than 1 MB:

ID: 12345, Key: sccache-linux-x86_64-1234567890, Size: 125.50 MB, Created: 2024-01-15
ID: 12346, Key: sccache-windows-x86_64-0987654321, Size: 89.25 MB, Created: 2024-01-14
```

**What to look for**:
- **Size distribution**: Are most caches huge or just a few?
- **Creation dates**: Are old caches not being cleaned up?
- **Key patterns**: Which builds creating largest caches?

## Limitations

### What This Workflow Cannot Do

1. **Selective deletion by branch**
   - GitHub API doesn't expose cache branch info in list
   - Would need to parse cache keys manually

2. **Keep N most recent caches**
   - Deletion is size-based only
   - Cannot implement LRU (least recently used) policy

3. **Delete caches by age**
   - No direct age filter in API
   - Would need to parse `created_at` timestamp

4. **Prevent cache creation**
   - Only cleans up after caches exist
   - Cannot prevent builds from creating large caches

### Workarounds

**Branch-specific cleanup**: Modify script to filter cache.key
```javascript
cache.key.startsWith('main-') || cache.key.includes('-main-')
```

**Age-based cleanup**: Add time filter
```javascript
const now = new Date();
const cacheAge = now - new Date(cache.created_at);
const oneWeek = 7 * 24 * 60 * 60 * 1000;
if (cacheAge > oneWeek) { /* delete */ }
```

## Related Documentation

- **README-cache-cleanup.md**: User-facing documentation with examples
- **sccache-action**: Creates the large caches this workflow cleans
- **common-build.yml**: Workflow that generates most cache usage

## Related Workflows

- **common-build.yml**: Creates sccache caches (largest consumers)
- **daily-build.yml**: Runs multiple builds (multiplies cache usage)
- All workflows using `sccache-action`: Generate caches
