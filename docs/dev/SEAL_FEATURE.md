# SEAL Binary Distribution Implementation Plan

## Overview
Implement automated building and distribution of SEAL binaries (key-server, seal-cli, etc...) from source, following the existing suibase-daemon pattern for Rust source-based builds.

## Implementation Pattern
Follows suibase-daemon build pattern exactly, except triggered by scheduled monitoring of upstream MystenLabs/seal releases instead of Cargo.toml changes.

## Implementation Components


### 1. Build Script
```
scripts/build-seal.sh
```
- Clone MystenLabs/seal repository
- Build all SEAL binaries
- Package as .tgz archives
- Enable local testing and debugging before CI runs
- Provide single source of truth for build logic

### 2. GitHub Actions Workflows

- Triggered by scheduled cron (4x daily) + manual dispatch
- Build matrix: ubuntu-x86_64 (native)
- Creates `seal-v{version}-{platform}.tgz` with all SEAL binaries

## Key Implementation Details

### Build Requirements
- **Dependencies**: Same as suibase-daemon (curl, cmake, gcc, libssl-dev, pkg-config, libclang-dev, libpq-dev, build-essential)
- **Build**: `cargo build --release`
- **Platforms**: ubuntu-x86_64 (native)
- **Verification**: Test with `--version` or `--help` before packaging

## Files to Create

### Core Files
1. `scripts/build-seal.sh` - Build script for development and CI consistency

### GitHub Actions
2. `.github/workflows/build-seal.yml` - Combined monitoring and build workflow (calls build script)

### Documentation
3. `SEAL_FEATURE.md` - Implementation documentation (this file)
4. Update `CLAUDE.md` with SEAL build commands

### Recovery Strategy
- **Idempotent builds**: Safe to re-run on existing releases. Like for suibase-daemon, do proper gating from draft to published release (like suibase-daemon does).
- **Failed builds/release retry on next cron run**

## Build Commands Reference
```bash
# Clone upstream source
git clone --branch seal-v{version} https://github.com/MystenLabs/seal.git

# Build binaries
cargo build --release
```