# Quick Reference - .github Directory

## Workflows

| Workflow | Function | Trigger | Output |
|----------|----------|---------|--------|
| daily-build.yml | Orchestrate builds | Daily 6 AM UTC | 3 browser packages |
| common-build.yml | Core build engine | Called by wrappers | Compiled browser |
| wrapper-build-{linux,windows}.yml | Platform builds | Called by daily-build | Platform packages |
| generate-pgo-profile-*.yml | Generate PGO profiles | PGO Stage 2 | merged.profdata + en-US.log |
| cleanup-large-caches.yml | Cache management | Daily 2 AM UTC | Free space |
| misc-pull-upstream.yml | Sync Firefox | Daily 11:40 AM UTC | PR with changes |
| autodiff-per-file-pr.yml | Generate patches | `@f3liz-bot patch` | .patch files |

## Build Flow

**Standard**: daily-build → wrapper-build → common-build (2-3 hrs each, parallel)

**PGO**: 3 stages (5-7 hrs total)
1. Build with profiling (2-3 hrs)
2. Generate profiles (20-30 min)
3. Rebuild optimized (2-3 hrs) → 15-30% faster

## Key Environment Variables

```bash
# Build
MOZ_NUM_JOBS=$(nproc * 3/4)  # Parallel jobs
CARGO_INCREMENTAL=0           # For PGO
SCCACHE_GHA_ENABLED=on        # Cache

# PGO
LLVM_PROFDATA                 # llvm-profdata path
JARLOG_FILE=en-US.log         # JAR log
MOZ_PGO_TIMEOUT_MULTIPLIER=5  # 5x timeouts

# Linux
DISPLAY=:99                   # Xvfb display
LIBGL_ALWAYS_SOFTWARE=1       # Software GL
```

## Resources

- **Disk**: 30-40 GB (standard), 40-50 GB (PGO)
- **Memory**: 8 GB RAM + 30 GB swap (20-30 GB peak linking)
- **CPU**: (nproc * 3/4) jobs; 2-4 hrs (cold), 30-60 min (warm cache)
- **Artifacts**: Browser (90d, 100-200 MB), PGO profiles (7d, 5-50 MB)

## Common Failures

| Issue | Symptom | Fix |
|-------|---------|-----|
| Out of disk | "No space left" | allocate-swap.sh frees ~30GB |
| Patch fails | "patch does not apply" | Update/remove patch |
| PGO missing | "Artifact not found" | Re-run full PGO pipeline |
| Timeout | Job >6 hours | sccache (auto) |
| Empty profile | 0-byte merged.profdata | Check Xvfb, increase timeouts |

## Quick Commands

```bash
# Build
gh workflow run daily-build.yml
gh workflow run wrapper-build-linux.yml -f debug=false -f pgo=true

# Cache
gh workflow run cleanup-large-caches.yml -f dry_run=true -f size_threshold_mb=1

# Sync
gh workflow run misc-pull-upstream.yml
gh pr list --label sync

# Patches (comment on PR)
@f3liz-bot patch
@f3liz-bot patch rm=file1,file2
```

## Architecture

| Platform | Arch | Runner | Container |
|----------|------|--------|-----------|
| Linux | x64, arm64 | ubuntu/macos | Debian (arm64) |
| Windows | x64 | windows | None |

## Triggers

| Workflow | Schedule | Manual | Called |
|----------|----------|--------|--------|
| daily-build | 6 AM UTC | ✅ | - |
| common-build | - | - | ✅ |
| wrapper-build | - | ✅ | ✅ |
| generate-pgo | - | - | ✅ |
| cleanup-caches | 2 AM UTC | ✅ | - |
| pull-upstream | 11:40 AM UTC | ✅ | ✅ |
| autodiff | - | - | ✅ (PR comment) |

## File Structure

```
.github/
├── workflows/*.yml              # Workflow definitions
├── workflows/scripts/           # Build helpers
├── workflows/mozconfigs/        # Platform configs
├── scripts/firefox-profileserver/ # PGO tool
├── assets/branding/            # Branding files
└── patches/                    # Code patches
```

## Dependencies

- **Rust**: 1.86.0 (LLVM 20 compat)
- **LLVM**: 20 (PGO)
- **Firefox**: release branch
- **GitHub Actions**: checkout, upload/download-artifact, delete-artifact, setup-uv
- **System**: GTK 3.0, X11/Xvfb

For detailed docs, see `DOCS-*.md` files in `.github/workflows/`.
