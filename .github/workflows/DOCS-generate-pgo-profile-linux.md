# Generate PGO Profile (Linux)

**File**: `generate-pgo-profile-linux.yml`

## Function

Stage 2 of PGO: Run instrumented browser with tests to collect profile data.

## Inputs

- `browser-artifact-name`: Instrumented browser from Stage 1
- `target-arch`: x86_64 | aarch64
- `runner`: ubuntu-latest (x64) | macos-latest (arm64)

## Steps

1. Download instrumented browser
2. Setup: Install deps, Python, LLVM 19
3. Extract browser → `obj-firefox/dist/firefox/`
4. Start Xvfb (3-sec delay)
5. Run profileserver.py:
   - Initialize profile
   - Run tests at `http://localhost:8888/index.html`
   - Collect *.profraw files
6. Merge: `llvm-profdata merge *.profraw → merged.profdata`
7. Upload: merged.profdata + en-US.log

## Container

Debian Bookworm, platform: linux/amd64 (x64) or linux/arm64 (arm64)

## Timing

- Profile generation: ~20 minutes
- Timeout: 5x normal (instrumented browser slower)
- Xvfb startup: 3 seconds

## Output

- **merged.profdata**: LLVM profile data (5-50MB)
- **en-US.log**: JAR access log (1-5MB)
- **Retention**: 7 days
