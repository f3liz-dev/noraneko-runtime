# Cleanup Large Caches

**File**: `cleanup-large-caches.yml`

## Function

Delete GitHub Actions caches larger than threshold (default: 1MB).

## Triggers

- **Schedule**: Daily 2 AM UTC
- **Manual**: With parameters (size_threshold_mb, dry_run)

## Process

1. Fetch all caches via GitHub API
2. Filter by size > threshold
3. Delete (or list if dry_run=true)

## Parameters

- `size_threshold_mb`: Min size to delete (default: 1)
- `dry_run`: List only, don't delete (default: false)

## Timing

- Runs at 2 AM UTC (after nightly builds)
- Duration: ~1 minute for 20 caches

## Rate Limits

- 5,000 API requests/hour
- Max ~2,500 caches deletable/hour

See README-cache-cleanup.md for detailed usage examples.
