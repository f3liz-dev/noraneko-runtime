# Daily Build Workflow

**File**: `daily-build.yml`

## Function

Orchestrates daily builds for all platforms in parallel.

## Triggers

- **Schedule**: Daily 6 AM UTC (`0 6 * * *`)
- **Manual**: With optional debug/pgo parameters

## Execution

```
daily-build.yml
├─→ Windows (wrapper-build-windows → common-build)
├─→ Linux x64 (wrapper-build-linux → common-build)
└─→ Linux ARM64 (wrapper-build-linux arch:aarch64 → common-build)
```

All 3 platforms build in parallel (~4 hours total).

## Parameters

- `debug`: true (schedule), user choice (manual) - default true
- `pgo`: false (schedule), user choice (manual) - default true

**Schedule builds**: Always debug, never PGO (faster daily testing)
**Manual builds**: User controls both options

## Architecture

| Platform | Runner | Time |
|----------|--------|------|
| Windows x64 | windows-latest | 2-3 hrs |
| Linux x64 | ubuntu-latest | 2-3 hrs |
| Linux ARM64 | macos-latest + Docker | 3-4 hrs |

Linux ARM64 uses Docker/QEMU (no native Linux ARM64 runners).

## Failure Handling

- Independent builds - one can fail without affecting others
- No automatic retry
- Partial success valid
