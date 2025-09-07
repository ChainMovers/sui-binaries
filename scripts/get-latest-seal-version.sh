#!/bin/bash

set -euo pipefail

# Get Latest SEAL Version Script
# Reusable script to fetch the latest SEAL version from GitHub API
# Used by both build scripts and CI/CD workflows to avoid rebuilding existing versions

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

# Get latest SEAL version from GitHub API
get_latest_seal_version() {
    local version="${SEAL_VERSION:-latest}"
    
    if [[ "$version" == "latest" ]]; then
        local latest_tag=$(curl -s https://api.github.com/repos/MystenLabs/seal/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        if [[ -z "$latest_tag" ]]; then
            log_error "Failed to fetch latest version from GitHub API"
            exit 1
        fi
        version="$latest_tag"
    fi
    
    # Remove 'seal-v' prefix if present
    version=${version#seal-v}
    
    # Verify the version string format
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format: $version"
        exit 1
    fi
    
    echo "$version"
    exit 0
}

# Main execution - output the version
main() {
    local version=$(get_latest_seal_version)
    echo "$version"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi