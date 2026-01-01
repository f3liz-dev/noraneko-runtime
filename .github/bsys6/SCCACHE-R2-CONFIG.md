# sccache with Cloudflare R2 Configuration

This document describes how sccache is configured to use Cloudflare R2 for build caching in the Noraneko build system.

## Overview

sccache is a compiler caching tool that speeds up compilation by caching previous builds. It's configured to use Cloudflare R2 (S3-compatible object storage) as the cache backend.

## GitHub Secrets Configuration

To enable sccache with Cloudflare R2, you need to configure the following GitHub repository secrets:

### Required Secrets

1. **`SCCACHE_BUCKET`**
   - The name of your Cloudflare R2 bucket
   - Example: `my-noraneko-cache`

2. **`SCCACHE_ENDPOINT`**
   - The R2 endpoint URL
   - Format: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
   - You can find your account ID in the [Cloudflare Dashboard](https://developers.cloudflare.com/fundamentals/get-started/basic-tasks/find-account-and-zone-ids/)
   - Example: `https://1234567890abcdef.r2.cloudflarestorage.com`

3. **`SCCACHE_AWS_ACCESS_KEY_ID`**
   - R2 API token access key ID
   - Create from Cloudflare Dashboard → R2 → Manage R2 API Tokens

4. **`SCCACHE_AWS_SECRET_ACCESS_KEY`**
   - R2 API token secret access key
   - Created along with the access key ID

### How to Create R2 API Tokens

1. Log in to your Cloudflare Dashboard
2. Go to R2 → Manage R2 API Tokens
3. Click "Create API Token"
4. Configure permissions:
   - Permission: Admin Read & Write (or Object Read & Write for more security)
   - Optionally restrict to specific bucket
5. Copy the Access Key ID and Secret Access Key
6. Add them to your GitHub repository secrets as:
   - `SCCACHE_AWS_ACCESS_KEY_ID`
   - `SCCACHE_AWS_SECRET_ACCESS_KEY`

## How It Works

1. **Installation**: The `setup_sccache.sh` script downloads and installs sccache during the "Prepare host" step
2. **Configuration**: Environment variables are passed to configure R2 as the storage backend
3. **Integration**: The mozconfig files are configured with `--with-ccache=sccache` to use sccache as the compiler wrapper
4. **Build**: During compilation, sccache caches compiled objects in R2
5. **Reuse**: Subsequent builds reuse cached objects from R2, speeding up compilation

## Fallback Behavior

If R2 credentials are not configured:
- sccache will still be installed
- It will use local disk caching instead of R2
- Builds will still work but won't benefit from shared caching across runners

## Monitoring

To check sccache statistics:
```bash
sccache --show-stats
```

This will show:
- Cache hits/misses
- Cache size
- Storage backend status

## Files Modified

- `.github/bsys6/src/utils/setup_sccache.sh` - sccache installation and configuration script
- `.github/bsys6/src/prepare-host.sh` - Calls setup_sccache.sh
- `.github/bsys6/assets/linux.mozconfig` - Added `--with-ccache=sccache`
- `.github/bsys6/assets/windows.mozconfig` - Added `--with-ccache=sccache`
- `.github/workflows/bsys6-build.yml` - Pass R2 secrets to build steps
- `.github/workflows/bsys6-daily-build.yml` - Pass R2 secrets to all build jobs

## Environment Variables

The following environment variables are configured in the workflows:

- `SCCACHE_BUCKET` - R2 bucket name (from secrets)
- `SCCACHE_ENDPOINT` - R2 endpoint URL (from secrets)
- `SCCACHE_REGION` - Set to `auto` (R2 doesn't use regions)
- `AWS_ACCESS_KEY_ID` - R2 access key ID (from secrets)
- `AWS_SECRET_ACCESS_KEY` - R2 secret access key (from secrets)

## Security Notes

- Never commit R2 credentials directly in the code
- Always use GitHub Secrets for sensitive values
- Consider using read-only tokens for pull request builds
- R2 API tokens can be restricted to specific buckets for additional security
