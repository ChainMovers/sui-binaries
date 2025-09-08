# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository provides pre-compiled binaries for the Sui ecosystem, specifically:
- **suibase-daemon**: A Rust workspace containing daemon functionality for Suibase
- **seal binaries**: Automated builds and releases of SEAL (decentralized secrets management) binaries from MystenLabs
- **site-builder binaries**: Automated downloads and releases of site-builder binaries from Mysten Labs

## Architecture

### Suibase Daemon
- **Location**: `triggers/suibase-daemon/`
- **Structure**: Rust workspace with multiple crates:
  - `crates/suibase-daemon` - Main daemon implementation
  - `crates/poi-server` - Point of Interest server
  - `crates/common` - Shared utilities
- **Build Target**: Cross-platform daemon binary with musl linking on Linux
- **Dependencies**: Uses tokio async runtime, axum web framework, jsonrpsee for RPC, sqlx for database operations

### SEAL Binaries
- **Location**: Built from source at `https://github.com/MystenLabs/seal`
- **Structure**: Rust workspace with three main binaries:
  - `key-server` - Decentralized key management server (~28MB)
  - `seal-cli` - Command-line interface for SEAL operations (~1.5MB)
  - `seal-proxy` - Proxy service for SEAL network communication (~13MB)
- **Build Target**: Native Ubuntu binaries
- **Dependencies**: Uses tokio async runtime, axum web framework, Sui SDK integration
- **Dynamic Toolchain**: Automatically detects and uses SEAL's required Rust version from `rust-toolchain.toml`

### Release Automation
The repository uses GitHub Actions for automated binary building and releases:
- **Suibase Daemon**: Triggered by `Cargo.toml` version changes
- **SEAL Binaries**: Cron-based monitoring every 6 hours for new GitHub releases, with duplicate build prevention
- **Site Builder**: Scheduled downloads from Google Cloud Storage with automatic versioning

## Build Commands

### Suibase Daemon
The daemon is built through Suibase's build system, not direct cargo commands:
```bash
# Download and install Suibase
git clone --branch dev https://github.com/ChainMovers/suibase.git $HOME/suibase
$HOME/suibase/install

# Build the daemon
$HOME/suibase/scripts/dev/update-daemon

# Binary location after build
$HOME/suibase/workdirs/common/bin/suibase-daemon
```

### Dependencies (Linux)
```bash
sudo apt-get update
sudo apt-get install curl cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential
```

### Dependencies (macOS)
```bash
brew install curl cmake
```

### SEAL Binaries
SEAL binaries are built from source using our automated build script:

#### Local Development Build
```bash
# Build latest SEAL version locally
./scripts/build-seal.sh

# Build specific SEAL version
SEAL_VERSION=0.5.9 ./scripts/build-seal.sh

# Get latest version only
./scripts/get-latest-seal-version.sh
```

#### Manual Build Process
```bash
# Clone SEAL repository
VERSION=$(./scripts/get-latest-seal-version.sh)
git clone --branch "seal-v$VERSION" --depth 1 https://github.com/MystenLabs/seal.git /tmp/seal-build

# Build all binaries (requires Rust toolchain)
cd /tmp/seal-build
cargo build --release

# Binaries location after build
# /tmp/seal-build/target/release/{key-server,seal-cli,seal-proxy}
```

#### Dependencies (Linux - for SEAL)
```bash
# Same as Suibase Daemon dependencies
sudo apt-get update
sudo apt-get install curl cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential
```

#### Dependencies (macOS - for SEAL)
```bash
# Same as Suibase Daemon dependencies  
brew install curl cmake
```

## Release Process

### Version Management
- Daemon versions are managed in `triggers/suibase-daemon/Cargo.toml`
- SEAL versions are automatically detected from GitHub releases via `scripts/get-latest-seal-version.sh`
- Version bumps trigger automatic builds for ubuntu-x86_64, macos-arm64, macos-x86_64
- Site-builder versions are extracted from upstream binaries using `--version` flag

### Asset Creation
- All binaries are packaged as `.tgz` archives
- Assets follow naming convention: `{component}-v{version}-{platform}.tgz`
- Releases remain as drafts until all expected platform assets are uploaded

## Development Notes
- Cross-compilation uses musl for Linux compatibility (when applicable)

## Workflow Commands

### Check GitHub Actions Status
```bash
# View workflow runs
gh run list

# View specific run details
gh run view <run-id>
```

### Manual Release Trigger
```bash
# Trigger daemon build workflow manually
gh workflow run build-suibase-daemon.yml

# Trigger SEAL build workflow manually
gh workflow run build-seal.yml
```

### Version Verification
```bash
# Check current daemon version in trigger file
grep '^version' triggers/suibase-daemon/Cargo.toml

# Check latest SEAL version available
./scripts/get-latest-seal-version.sh
```