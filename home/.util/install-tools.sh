#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Homebrew packages
install_brew_packages() {
    local packages=("$@")

    if ! command_exists brew; then
        log_error "Homebrew is not installed. Install from https://brew.sh/"
        return 1
    fi

    for package in "${packages[@]}"; do
        if brew list "$package" &> /dev/null; then
            log_info "Homebrew package '$package' is already installed"
        else
            log_info "Installing Homebrew package '$package'..."
            brew install "$package"
        fi
    done
}

# Python pip packages
install_pip_packages() {
    local packages=("$@")

    if ! command_exists pip3 && ! command_exists pip; then
        log_error "pip is not installed. Please install Python and pip first."
        return 1
    fi

    local pip_cmd="pip3"
    if ! command_exists pip3; then
        pip_cmd="pip"
    fi

    for package in "${packages[@]}"; do
        if $pip_cmd show "$package" &> /dev/null; then
            log_info "pip package '$package' is already installed"
        else
            log_info "Installing pip package '$package'..."
            $pip_cmd install --user "$package"
        fi
    done
}

# Go packages
install_go_packages() {
    local packages=("$@")

    if ! command_exists go; then
        log_error "Go is not installed. Please install Go first."
        return 1
    fi

    for package in "${packages[@]}"; do
        # Extract binary name from package path (last component after /)
        local binary_name="${package##*/}"
        # Remove @version if present
        binary_name="${binary_name%%@*}"

        if command_exists "$binary_name"; then
            log_info "Go package '$package' (binary: $binary_name) is already installed"
        else
            log_info "Installing Go package '$package'..."
            go install "$package"
        fi
    done
}

# Install from direct curl download
# Usage: install_from_curl <url> <destination_path> <binary_name>
install_from_curl() {
    local url="$1"
    local dest_path="$2"
    local binary_name="$3"

    if [ -f "$dest_path" ]; then
        log_info "Binary '$binary_name' already exists at $dest_path"
        return 0
    fi

    log_info "Downloading '$binary_name' from $url..."

    # Create destination directory if it doesn't exist
    mkdir -p "$(dirname "$dest_path")"

    # Download the file
    if curl -fsSL "$url" -o "$dest_path"; then
        chmod +x "$dest_path"
        log_info "Successfully installed '$binary_name' to $dest_path"
    else
        log_error "Failed to download '$binary_name' from $url"
        return 1
    fi
}

# Install from curl with extraction (for tar.gz, zip, etc.)
# Usage: install_from_archive <url> <extract_dir> <binary_name> <binary_path_in_archive>
install_from_archive() {
    local url="$1"
    local extract_dir="$2"
    local binary_name="$3"
    local binary_path_in_archive="$4"
    local final_dest="${5:-$HOME/.local/bin/$binary_name}"

    if [ -f "$final_dest" ]; then
        log_info "Binary '$binary_name' already exists at $final_dest"
        return 0
    fi

    log_info "Downloading and extracting '$binary_name' from $url..."

    local tmp_dir=$(mktemp -d)
    local archive_file="$tmp_dir/archive"

    # Download the archive
    if ! curl -fsSL "$url" -o "$archive_file"; then
        log_error "Failed to download archive from $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Detect archive type and extract
    if [[ "$url" == *.tar.gz ]] || [[ "$url" == *.tgz ]]; then
        tar -xzf "$archive_file" -C "$tmp_dir"
    elif [[ "$url" == *.zip ]]; then
        unzip -q "$archive_file" -d "$tmp_dir"
    else
        log_error "Unsupported archive format for $url"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Move the binary to destination
    mkdir -p "$(dirname "$final_dest")"
    if [ -f "$tmp_dir/$binary_path_in_archive" ]; then
        mv "$tmp_dir/$binary_path_in_archive" "$final_dest"
        chmod +x "$final_dest"
        log_info "Successfully installed '$binary_name' to $final_dest"
    else
        log_error "Binary not found in archive at path: $binary_path_in_archive"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"
}

# ============================================================================
# Define your tools here
# ============================================================================

# Example Homebrew packages
BREW_PACKAGES=(
    "jq"
    "uv"
    "lsd"
    "switchaudio-osx"
    # "ripgrep"
    # "fzf"
    # "git"
)

# Example pip packages
PIP_PACKAGES=(
    # "uv"
    # "pytest"
    # "requests"
)

# Example Go packages (must include @version or @latest)
GO_PACKAGES=(
    # "github.com/junegunn/fzf@latest"
    # "golang.org/x/tools/gopls@latest"
)

# Example curl installations
# Uncomment and modify as needed:

# install_from_curl \
#     "https://github.com/user/repo/releases/download/v1.0.0/binary-name" \
#     "$HOME/.local/bin/binary-name" \
#     "binary-name"

# Example archive installations:
# install_from_archive \
#     "https://github.com/user/repo/releases/download/v1.0.0/tool.tar.gz" \
#     "$HOME/.local" \
#     "tool" \
#     "tool/bin/tool" \
#     "$HOME/.local/bin/tool"

# ============================================================================
# Main installation
# ============================================================================

main() {
    log_info "Starting tool installation..."

    # Install Homebrew packages (macOS/Linux)
    if [[ ${#BREW_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installing Homebrew packages..."
        install_brew_packages "${BREW_PACKAGES[@]}"
    fi

    # Install pip packages
    if [[ ${#PIP_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installing pip packages..."
        install_pip_packages "${PIP_PACKAGES[@]}"
    fi

    # Install Go packages
    if [[ ${#GO_PACKAGES[@]} -gt 0 ]]; then
        log_info "Installing Go packages..."
        install_go_packages "${GO_PACKAGES[@]}"
    fi

    log_info "Tool installation complete!"
}

# Run main function
main "$@"
