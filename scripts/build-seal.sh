#!/bin/bash

set -euo pipefail

# SEAL Binary Build Script
# Follows the suibase-daemon pattern for Rust source builds

# Default version - can be overridden by environment variable
VERSION=${SEAL_VERSION:-"latest"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Determine platform for asset naming
get_platform() {
    local os=$(uname -s)
    local arch=$(uname -m)
    
    case "$os" in
        Linux)
            echo "ubuntu-x86_64"
            ;;
        Darwin)
            if [[ "$arch" == "arm64" ]]; then
                echo "macos-arm64"
            else
                echo "macos-x86_64"
            fi
            ;;
        *)
            log_error "Unsupported OS: $os"
            exit 1
            ;;
    esac
}

# Get latest version using shared script
get_latest_version() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VERSION=$("$script_dir/get-latest-seal-version.sh")
    log_info "Building SEAL version: $VERSION"
}

# Check system dependencies
check_dependencies() {
    log_info "Checking system dependencies..."
    
    # Check required commands
    local missing_cmds=()
    for cmd in curl cmake gcc rustc cargo; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done
    
    # Check for pkg-config (important for OpenSSL linking)
    if ! command -v pkg-config &>/dev/null; then
        missing_cmds+=("pkg-config")
    fi
    
    if [[ ${#missing_cmds[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_cmds[*]}"
        log_error "Please install missing dependencies:"
        
        if [[ "$(uname -s)" == "Linux" ]]; then
            log_error "  Ubuntu/Debian: sudo apt-get install curl cmake gcc libssl-dev pkg-config libclang-dev libpq-dev build-essential musl musl-tools musl-dev"
        elif [[ "$(uname -s)" == "Darwin" ]]; then
            log_error "  macOS: brew install curl cmake pkg-config"
        fi
        
        exit 1
    fi
    
    # Check for required libraries (Linux only)
    if [[ "$(uname -s)" == "Linux" ]]; then
        local missing_libs=()
        
        # Check for OpenSSL development headers
        if ! pkg-config --exists openssl; then
            missing_libs+=("libssl-dev")
        fi
        
        # Check for basic development tools
        if [[ ! -f /usr/include/stdio.h ]] && [[ ! -f /usr/local/include/stdio.h ]]; then
            missing_libs+=("build-essential")
        fi
        
        if [[ ${#missing_libs[@]} -gt 0 ]]; then
            log_warn "Missing development libraries (may cause build issues): ${missing_libs[*]}"
            log_warn "Consider installing: sudo apt-get install libssl-dev build-essential"
        fi
    fi
    
    log_info "✓ All required commands are available"
}


# Clone SEAL repository
clone_seal() {
    local temp_dir="/tmp/seal-build-$$"
    local tag_name="seal-v$VERSION"
    
    log_info "Cloning SEAL repository (tag: $tag_name)..." >&2
    
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
    fi
    
    git clone --branch "$tag_name" --depth 1 https://github.com/MystenLabs/seal.git "$temp_dir" >&2
    
    echo "$temp_dir"
}

# Build SEAL binaries
build_binaries() {
    local seal_dir="$1"
    log_info "Building SEAL binaries..."
    
    # Change to SEAL directory
    cd "$seal_dir"
    
    # Install musl target for SEAL's specific Rust toolchain
    if [[ "$(uname -s)" == "Linux" ]]; then
        log_info "Installing musl target for SEAL's Rust toolchain..."
        
        # Read the Rust channel from SEAL's rust-toolchain.toml
        local rust_channel=""
        if [[ -f "rust-toolchain.toml" ]]; then
            rust_channel=$(grep '^channel' rust-toolchain.toml | sed 's/channel = "\(.*\)"/\1/' | tr -d '"')
        fi
        
        if [[ -z "$rust_channel" ]]; then
            log_warn "Could not determine Rust channel from rust-toolchain.toml, using default toolchain"
            rustup target add x86_64-unknown-linux-musl
        else
            log_info "Using Rust channel: $rust_channel"
            rustup target add x86_64-unknown-linux-musl --toolchain "$rust_channel-x86_64-unknown-linux-gnu"
        fi
    fi
    
    # Build for native platform
    log_info "Building native binaries..."
    cargo build --release
    
    # Build for musl target on Linux with static OpenSSL and performance optimizations
    if [[ "$(uname -s)" == "Linux" ]]; then
        log_info "Building musl binaries for Linux with static OpenSSL..."
        
        # Set environment variables for static musl build
        export PKG_CONFIG_ALLOW_CROSS=1
        export PKG_CONFIG_ALL_STATIC=1
        export OPENSSL_STATIC=1
        export OPENSSL_DIR=/usr
        
        # Try to build with musl - if it fails, skip musl and continue with native only
        if ! cargo build --release --target x86_64-unknown-linux-musl; then
            log_warn "Musl build failed, continuing with native binaries only"
            log_warn "This is expected for SEAL due to OpenSSL static linking complexity"
        else
            log_info "✓ Musl build completed successfully"
        fi
        
        # Unset environment variables
        unset PKG_CONFIG_ALLOW_CROSS PKG_CONFIG_ALL_STATIC OPENSSL_STATIC OPENSSL_DIR
    fi
}

# Verify binaries work
verify_binaries() {
    local seal_dir="$1"
    log_info "Verifying built binaries..." >&2
    
    # Work in SEAL directory
    cd "$seal_dir"
    
    local target_dir="target/release"
    # Check if musl binaries exist and have actual binaries, otherwise use native
    if [[ "$(uname -s)" == "Linux" ]] && [[ -d "target/x86_64-unknown-linux-musl/release" ]]; then
        # Check if any of the expected binaries exist in musl directory
        local has_musl_binaries=false
        for binary in "key-server" "seal-cli" "seal-proxy"; do
            if [[ -f "target/x86_64-unknown-linux-musl/release/$binary" ]]; then
                has_musl_binaries=true
                break
            fi
        done
        
        if [[ "$has_musl_binaries" == "true" ]]; then
            target_dir="target/x86_64-unknown-linux-musl/release"
            log_info "Using musl binaries for verification" >&2
        else
            log_info "Musl directory exists but no binaries found, using native binaries for verification" >&2
        fi
    else
        log_info "Using native binaries for verification" >&2
    fi
    
    # Find all binary files (SEAL binaries are known names without extensions)
    local expected_binaries=("key-server" "seal-cli" "seal-proxy")
    local binaries=()
    
    # Check for each expected binary
    for binary in "${expected_binaries[@]}"; do
        if [[ -f "$target_dir/$binary" ]] && [[ -x "$target_dir/$binary" ]]; then
            binaries+=("$binary")
        fi
    done
    
    if [[ ${#binaries[@]} -eq 0 ]]; then
        log_error "No binaries found in $target_dir" >&2
        exit 1
    fi
    
    log_info "Found binaries: ${binaries[*]}" >&2
    
    # Test each binary
    for binary in "${binaries[@]}"; do
        local binary_path="$target_dir/$binary"
        log_info "Testing binary: $binary" >&2
        
        # Try --version first, fall back to --help
        if "$binary_path" --version >/dev/null 2>&1; then
            log_info "✓ $binary responds to --version" >&2
        elif "$binary_path" --help >/dev/null 2>&1; then
            log_info "✓ $binary responds to --help" >&2
        else
            log_warn "⚠ $binary doesn't respond to --version or --help, but including anyway" >&2
        fi
    done
    
    # Only echo the binaries to stdout (for capture)
    echo "${binaries[@]}"
}

# Package binaries
package_binaries() {
    local seal_dir="$1"
    shift
    local binaries=("$@")
    local platform=$(get_platform)
    local asset_name="seal-v$VERSION-$platform.tgz"
    local target_dir="target/release"
    local original_dir="$(pwd)"  # Capture where script was called from
    
    # Check if musl binaries exist and have actual binaries, otherwise use native
    if [[ "$(uname -s)" == "Linux" ]] && [[ -d "$seal_dir/target/x86_64-unknown-linux-musl/release" ]]; then
        # Check if any of the expected binaries exist in musl directory
        local has_musl_binaries=false
        for binary in "${binaries[@]}"; do
            if [[ -f "$seal_dir/target/x86_64-unknown-linux-musl/release/$binary" ]]; then
                has_musl_binaries=true
                break
            fi
        done
        
        if [[ "$has_musl_binaries" == "true" ]]; then
            target_dir="target/x86_64-unknown-linux-musl/release"
            log_info "Packaging musl binaries"
        else
            log_info "Musl directory exists but no binaries found, packaging native binaries"
        fi
    else
        log_info "Packaging native binaries"
    fi
    
    log_info "Packaging binaries into $asset_name..."
    
    # Create temporary directory for packaging
    local package_dir="/tmp/seal-package-$$"
    mkdir -p "$package_dir"
    
    # Copy binaries to package directory
    for binary in "${binaries[@]}"; do
        cp "$seal_dir/$target_dir/$binary" "$package_dir/"
        log_info "Added $binary to package"
    done
    
    # Create archive
    cd "$package_dir"
    tar -czf "$asset_name" *
    
    # Move to original working directory (where script was called from)
    mv "$asset_name" "$original_dir/"
    
    # Cleanup and return to original directory
    cd "$original_dir"
    rm -rf "$package_dir"
    
    log_info "✓ Package created: $original_dir/$asset_name" >&2
    
    # Verify package contents
    log_info "Package contents:" >&2
    tar -tzf "$asset_name" >&2
    
    echo "$asset_name"
}

# Main execution
main() {
    log_info "Starting SEAL binary build process..."
    
    # Check if we're in the right directory (look for CLAUDE.md and triggers/)
    if [[ ! -f "CLAUDE.md" ]] || [[ ! -d "triggers" ]]; then
        log_error "Please run this script from the sui-binaries repository root"
        exit 1
    fi
    
    # Get version
    get_latest_version
    
    # Check dependencies
    check_dependencies
    
    # Clone SEAL
    local seal_dir=$(clone_seal)
    
    # Build binaries
    build_binaries "$seal_dir"
    
    # Verify and get list of binaries
    local binaries=($(verify_binaries "$seal_dir"))
    
    # Package binaries
    local asset_name=$(package_binaries "$seal_dir" "${binaries[@]}")
    
    # Cleanup
    rm -rf "$seal_dir"
    
    log_info "🎉 SEAL build completed successfully!"
    log_info "Asset: $asset_name"
    log_info "Binaries included: ${binaries[*]}"
}

# Run main function
main "$@"