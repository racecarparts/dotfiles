#!/bin/bash

# Check if a directory is provided for stowing
DOTFILES_DIR="$1"
if [ -z "$DOTFILES_DIR" ]; then
    echo "Please specify a directory to stow."
    exit 1
fi

# Function to install recommended MesloLGS NF fonts for Powerlevel10k
install_recommended_meslo_fonts() {
    FONT_URL_BASE="https://github.com/romkatv/powerlevel10k-media/raw/master"
    FONT_DIR=""
    
    # Determine the font directory based on the OS
    case "$OSTYPE" in
        linux*)
            FONT_DIR="${HOME}/.local/share/fonts"
            mkdir -p "$FONT_DIR"
            ;;
        darwin*)
            FONT_DIR="${HOME}/Library/Fonts"
            ;;
        *)
            echo "Unsupported OS: $OSTYPE. Please install the MesloLGS NF fonts manually from:"
            echo "https://github.com/romkatv/powerlevel10k/blob/master/font.md"
            return 1
            ;;
    esac

    # Download the recommended fonts
    declare -a FONT_FILES=("MesloLGS%20NF%20Regular.ttf" "MesloLGS%20NF%20Bold.ttf" "MesloLGS%20NF%20Italic.ttf" "MesloLGS%20NF%20Bold%20Italic.ttf")
    for font in "${FONT_FILES[@]}"; do
        FONT_URL="${FONT_URL_BASE}/${font}"
        echo "Downloading ${font//%20/ }..."
        curl -Lo "${FONT_DIR}/${font//%20/ }" "$FONT_URL"
    done

    # Update font cache for Linux
    if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v fc-cache &> /dev/null; then
        echo "Updating font cache on Linux..."
        fc-cache -f "$FONT_DIR"
    fi

    echo "Recommended MesloLGS NF fonts for Powerlevel10k installed successfully."
}

# Function to check if the recommended MesloLGS NF fonts are installed
is_recommended_meslo_fonts_installed() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        fc-list | grep -qi "MesloLGS NF"
        return $?
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ls ~/Library/Fonts | grep -qi "MesloLGS NF"
        return $?
    fi
    return 1
}

# Function to install stow based on the detected OS
install_stow() {
    case "$OSTYPE" in
        linux*)
            if command -v apt-get &> /dev/null; then
                echo "Installing GNU Stow on Debian/Ubuntu..."
                sudo apt-get update && sudo apt-get install -y stow
            elif command -v apk &> /dev/null; then
                echo "Installing GNU Stow on Alpine Linux..."
                sudo apk add stow
            else
                echo "Unsupported Linux distribution. Please install GNU Stow manually."
                exit 1
            fi
            ;;
        darwin*)
            echo "Installing GNU Stow on macOS using Homebrew..."
            if ! command -v brew &> /dev/null; then
                echo "Homebrew is not installed. Please install Homebrew first from https://brew.sh/"
                exit 1
            fi
            brew install stow
            ;;
        *)
            echo "Unsupported OS: $OSTYPE. Please install GNU Stow manually."
            exit 1
            ;;
    esac
}

# Function to install oh-my-zsh
install_oh_my_zsh() {
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

# Function to install powerlevel10k
install_powerlevel10k() {
    echo "Installing powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
}

install_oh_my_zsh_plugin() {
    local plugin_name="$1"
    local plugin_repo="$2"
    local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin_name"

    if [ -d "$plugin_dir" ]; then
        echo "Plugin '$plugin_name' is already installed."
    else
        echo "Installing '$plugin_name'..."
        git clone "$plugin_repo" "$plugin_dir"
        echo "Plugin '$plugin_name' installed successfully."
    fi
}

# Function to check if the recommended MesloLGS NF fonts are installed
is_meslo_font_installed() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        fc-list | grep -qi "MesloLGS NF"
        return $?
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ls ~/Library/Fonts | grep -qi "MesloLGS NF"
        return $?
    fi
    return 1
}

# Check if stow is installed
if ! command -v stow &> /dev/null; then
    echo "GNU Stow is not installed."
    read -p "Would you like to install GNU Stow? (y/N): " install_stow_choice
    if [[ "$install_stow_choice" =~ ^[Yy]$ ]]; then
        install_stow
    else
        echo "GNU Stow installation skipped."
        exit 1
    fi
else
    echo "GNU Stow is already installed."
fi

# Check if oh-my-zsh is installed
if [ ! -d "${ZSH:-$HOME/.oh-my-zsh}" ]; then
    echo "oh-my-zsh is not installed."
    read -p "Would you like to install oh-my-zsh? (y/N): " install_omz
    if [[ "$install_omz" =~ ^[Yy]$ ]]; then
        install_oh_my_zsh
    else
        echo "Skipping oh-my-zsh installation."
    fi
else
    echo "oh-my-zsh is already installed."
fi

# Check if the recommended MesloLGS NF fonts are installed
if is_meslo_font_installed; then
    echo "Recommended MesloLGS NF fonts for Powerlevel10k are already installed."
else
    echo "Recommended MesloLGS NF fonts for Powerlevel10k are not installed."
    read -p "Would you like to install them? (y/N): " install_font_choice
    if [[ "$install_font_choice" =~ ^[Yy]$ ]]; then
        install_recommended_meslo_fonts
    else
        echo "Skipping installation of recommended MesloLGS NF fonts."
    fi
fi

# Check if powerlevel10k is installed
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    echo "powerlevel10k is not installed."
    read -p "Would you like to install powerlevel10k? (y/N): " install_p10k
    if [[ "$install_p10k" =~ ^[Yy]$ ]]; then
        install_powerlevel10k
    else
        echo "Skipping powerlevel10k installation."
    fi
else
    echo "powerlevel10k is already installed."
fi

# Ensure oh-my-zsh is installed before installing plugins
if [ -d "${ZSH:-$HOME/.oh-my-zsh}" ]; then
    # Install zsh-autosuggestions
    install_oh_my_zsh_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions.git"

    # Install zsh-syntax-highlighting
    install_oh_my_zsh_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
else
    echo "oh-my-zsh is not installed. Please install oh-my-zsh first."
fi

# Run stow on the specified directory
stow "$DOTFILES_DIR"

echo "Stow completed."