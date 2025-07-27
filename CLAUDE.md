# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository provides pre-compiled binaries for the Sui ecosystem, specifically:
- **suibase-daemon**: A Rust workspace containing daemon functionality for Suibase
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

### Release Automation
The repository uses GitHub Actions for automated binary building and releases:
- **Suibase Daemon**: Triggered by `Cargo.toml` version changes
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
sudo apt-get install curl cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential musl musl-tools musl-dev
```

### Dependencies (macOS)
```bash
brew install curl cmake
```

## Release Process

### Version Management
- Daemon versions are managed in `triggers/suibase-daemon/Cargo.toml`
- Version bumps trigger automatic builds for ubuntu-x86_64, macos-arm64, macos-x86_64
- Site-builder versions are extracted from upstream binaries using `--version` flag

### Asset Creation
- All binaries are packaged as `.tgz` archives
- Assets follow naming convention: `{component}-v{version}-{platform}.tgz`
- Releases remain as drafts until all expected platform assets are uploaded

## Development Notes

- No traditional Rust development workflow (no `cargo build/test` in this repo)
- Primary development happens in the Suibase repository
- This repository serves as a distribution point for compiled binaries
- The daemon requires specific Suibase environment setup for building
- Cross-compilation uses musl for Linux compatibility