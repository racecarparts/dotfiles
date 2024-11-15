#!/bin/bash

source_files_in_directory() {
    local dir="$1"
    if [ -d "$dir" ]; then
        for file in "$dir"/*.sh; do
            # Check if the file exists and is readable
            [ -r "$file" ] && source "$file"
        done
    else
        echo "Directory $dir does not exist."
    fi
}

# Determine the OS type
OS_TYPE=$(uname -s)

if [[ "$OS_TYPE" == "Linux" ]]; then
    # echo "Detected Linux. Sourcing files in ~/.zsh-helpers/linux"
    source_files_in_directory "$HOME/.zsh-helpers/linux"
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    # echo "Detected Darwin. Sourcing files in ~/.zsh-helpers/darwin"
    source_files_in_directory "$HOME/.zsh-helpers/darwin"
else
    echo "Unsupported OS: $OS_TYPE"
fi

source_files_in_directory "$HOME/.zsh-helpers/all"
