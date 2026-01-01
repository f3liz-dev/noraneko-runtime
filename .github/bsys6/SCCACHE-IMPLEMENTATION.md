# sccache with Cloudflare R2 - Implementation Summary

## What Was Done

Successfully implemented sccache with Cloudflare R2 support in the Noraneko build system (bsys6).

### Files Created

1. **`.github/bsys6/src/utils/setup_sccache.sh`**
   - Downloads and installs sccache v0.8.2
   - Configures sccache with Cloudflare R2 (when credentials are provided)
   - Falls back to local disk caching if R2 credentials are not available
   - Auto-detects architecture (x86_64, aarch64) and OS (Linux, macOS)
   - **Security: Completely hides all sensitive information in logs**
     - No credentials are displayed in console output
     - Only shows confirmation when credentials are configured

2. **`.github/bsys6/SCCACHE-R2-CONFIG.md`**
   - Complete documentation on how to configure R2
   - Step-by-step guide for creating R2 API tokens
   - List of required GitHub Secrets
   - Security best practices

### Files Modified

1. **`.github/bsys6/src/prepare-host.sh`**
   - Added call to `setup_sccache.sh` during host preparation

2. **`.github/bsys6/assets/linux.mozconfig`**
   - Added `ac_add_options --with-ccache=sccache` to enable sccache for Linux builds

3. **`.github/bsys6/assets/windows.mozconfig`**
   - Added `ac_add_options --with-ccache=sccache` to enable sccache for Windows builds

4. **`.github/workflows/bsys6-build.yml`**
   - Added environment variables for R2 configuration to both "Prepare host" and "Build" steps
   - Passes GitHub secrets to the build environment

5. **`.github/workflows/bsys6-daily-build.yml`**
   - Updated all build jobs (Linux x86_64, Linux aarch64, Windows x86_64, and PGO final)
   - Added environment variables for R2 configuration to both "Prepare host" and "Build" steps

## Required GitHub Secrets

You need to add these secrets to your GitHub repository:

### 1. SCCACHE_BUCKET
- **Description**: Name of your Cloudflare R2 bucket
- **Example**: `noraneko-cache`

### 2. SCCACHE_ENDPOINT
- **Description**: R2 endpoint URL with your account ID
- **Format**: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
- **Example**: `https://abc123def456.r2.cloudflarestorage.com`
- **How to find Account ID**: https://developers.cloudflare.com/fundamentals/get-started/basic-tasks/find-account-and-zone-ids/

### 3. SCCACHE_AWS_ACCESS_KEY_ID
- **Description**: R2 API token access key ID
- **Where to get**: Cloudflare Dashboard → R2 → Manage R2 API Tokens → Create API Token

### 4. SCCACHE_AWS_SECRET_ACCESS_KEY
- **Description**: R2 API token secret access key
- **Where to get**: Same place as access key ID (shown only once when created)

## How to Set Up R2

### Step 1: Create R2 Bucket
1. Log in to Cloudflare Dashboard
2. Navigate to R2
3. Click "Create bucket"
4. Name it (e.g., `noraneko-cache`)
5. Note the bucket name for the `SCCACHE_BUCKET` secret

### Step 2: Create R2 API Token
1. In Cloudflare Dashboard → R2
2. Click "Manage R2 API Tokens"
3. Click "Create API Token"
4. Configure:
   - **Permission**: Admin Read & Write (or Object Read & Write for specific bucket)
   - **TTL**: Optional (leave blank for no expiration)
   - **Bucket restrictions**: Optional (recommended to restrict to your cache bucket)
5. Click "Create API Token"
6. Copy both:
   - Access Key ID → Use for `SCCACHE_AWS_ACCESS_KEY_ID`
   - Secret Access Key → Use for `SCCACHE_AWS_SECRET_ACCESS_KEY`
   - **Important**: Secret Access Key is shown only once!

### Step 3: Find Your Account ID
1. Cloudflare Dashboard → Click on any site
2. In the right sidebar, look for "Account ID"
3. Or visit: https://dash.cloudflare.com/?to=/:account/workers
4. Account ID is in the URL or displayed on the page

### Step 4: Add Secrets to GitHub
1. Go to your GitHub repository
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Add each of the 4 secrets:
   - `SCCACHE_BUCKET`
   - `SCCACHE_ENDPOINT` (format: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`)
   - `SCCACHE_AWS_ACCESS_KEY_ID`
   - `SCCACHE_AWS_SECRET_ACCESS_KEY`

## How It Works

1. **Prepare Host**: 
   - The `setup_sccache.sh` script downloads and installs sccache
   - If R2 credentials are present, it configures sccache with R2
   - If no credentials, sccache uses local disk cache

2. **Build**:
   - Mozilla's build system uses sccache as the compiler wrapper (via `--with-ccache=sccache`)
   - sccache intercepts compilation commands
   - Checks R2 for cached objects
   - If cache hit: Returns cached result (fast!)
   - If cache miss: Compiles and stores in R2 for future use

3. **Benefits**:
   - Dramatically faster rebuilds (can be 10x+ faster)
   - Shared cache across all GitHub Actions runners
   - Persistent cache (not limited by GitHub Actions cache size/retention)

## Fallback Behavior

If you don't configure R2 secrets:
- ✅ Builds will still work
- ✅ sccache will use local disk cache
- ❌ Cache won't be shared across workflow runs
- ❌ Each runner starts with empty cache

## Testing

Once secrets are added, trigger a workflow:
1. Manual trigger: Actions → Build (bsys6) → Run workflow
2. Or wait for automatic daily build

In the workflow logs, look for:
```
-> Installing sccache v0.8.2
   Downloading from: https://github.com/mozilla/sccache/releases/...
   Extracting sccache
   Installing to /usr/local/bin
   sccache installed successfully: sccache 0.8.2
-> Configuring sccache with Cloudflare R2
   R2 credentials configured (not shown for security)
-> Starting sccache server
   sccache server started successfully
-> sccache statistics:
```

**Note**: All sensitive information is completely hidden in logs for security. You can verify your secrets in the GitHub repository web console if needed.

## Reference

- Mozilla sccache repository: https://github.com/mozilla/sccache
- Cloned to `/tmp/sccache` for reference during implementation
- R2 configuration docs: See `.github/bsys6/SCCACHE-R2-CONFIG.md`

## Next Steps

1. Set up R2 bucket and API tokens in Cloudflare
2. Add the 4 required secrets to GitHub repository
3. Trigger a build workflow to test
4. Monitor the first build (will populate cache)
5. Monitor subsequent builds (should show cache hits and faster build times)

## Support

For issues or questions:
- Check workflow logs for sccache output
- Verify secrets are set correctly
- Check R2 bucket permissions
- Review `.github/bsys6/SCCACHE-R2-CONFIG.md` for detailed configuration
