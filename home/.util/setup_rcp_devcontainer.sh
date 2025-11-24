#!/bin/bash

# Default values for optional arguments
TAG=""
GIT_USER_NAME=""
GIT_USER_EMAIL=""
GO_VERSION="1.23.2"
PYTHON_VERSION="3.12.7"
ARCHITECTURE="arm64"
PROJECT_PATH=""

# Function to display usage instructions
usage() {
  echo "Usage: ./setup_devcontainer.sh --project-path <path> --git-name <name> --git-email <email> [OPTIONS]"
  echo ""
  echo "Required arguments:"
  echo "  --project-path       Path to the project directory where the .devcontainer setup will be created."
  echo "  --git-name           Name to use for git user configuration."
  echo "  --git-email          Email to use for git user configuration."
  echo ""
  echo "Optional arguments:"
  echo "  --tag                Tag of the rcp-devcontainer release to use (default: latest release)."
  echo "  --go-version         Version of Go to set up (default: ${GO_VERSION})."
  echo "  --python-version     Version of Python to set up (default: ${PYTHON_VERSION})."
  echo "  --architecture       Architecture to target (default: ${ARCHITECTURE})."
  echo "  --help               Show this help message and exit."
  exit 0
}

# Parse command-line flags
while [[ $# -gt 0 ]]; do
  case $1 in
    --project-path)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --tag)
      TAG="$2"
      shift 2
      ;;
    --git-name)
      GIT_USER_NAME="$2"
      shift 2
      ;;
    --git-email)
      GIT_USER_EMAIL="$2"
      shift 2
      ;;
    --go-version)
      GO_VERSION="$2"
      shift 2
      ;;
    --python-version)
      PYTHON_VERSION="$2"
      shift 2
      ;;
    --architecture)
      ARCHITECTURE="$2"
      shift 2
      ;;
    --help)
      usage
      ;;
    -h)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Check if required flags are provided
if [ -z "$PROJECT_PATH" ]; then
  echo "Error: --project-path is required."
  exit 1
fi

if [ -z "$GIT_USER_NAME" ]; then
  echo "Error: --git-name is required."
  exit 1
fi

if [ -z "$GIT_USER_EMAIL" ]; then
  echo "Error: --git-email is required."
  exit 1
fi

# Check if jq is installed for JSON processing
if ! command -v jq &> /dev/null; then
  echo "jq is required but not installed. Please install jq and try again."
  exit 1
fi

# Retrieve latest release tag if not provided
if [ -z "$TAG" ]; then
  echo "Fetching the latest release tag from GitHub..."
  TAG=$(curl -s https://api.github.com/repos/racecarparts/rcp-devcontainer/releases/latest | jq -r .tag_name)
  
  if [ "$TAG" == "null" ]; then
    echo "Error: Could not retrieve the latest release tag. Please specify a tag."
    exit 1
  fi

  echo "Latest tag is $TAG"
fi

# Download the ZIP file for the specified tag to the project directory
download_zip() {
  local url="https://github.com/racecarparts/rcp-devcontainer/archive/refs/tags/$TAG.zip"
  local file="$PROJECT_PATH/$TAG.zip"
  
  echo "Downloading rcp-devcontainer at tag $TAG to $PROJECT_PATH..."
  if ! curl -L -o "$file" "$url"; then
    echo "Error: Failed to download the ZIP file."
    exit 1
  fi
}

# Extract the ZIP file into the specified project path
extract_zip() {
  local file="$PROJECT_PATH/$TAG.zip"
  
  echo "Extracting ZIP file into $PROJECT_PATH..."
  if ! unzip -q "$file" -d "$PROJECT_PATH"; then
    echo "Error: Failed to extract the ZIP file."
    rm -f "$file"
    exit 1
  fi

  # Find the extracted folder, which may have "v" stripped from the tag
  EXTRACTED_DIR=$(find $PROJECT_PATH -maxdepth 1 -type d -name "rcp-devcontainer-*")

  # Check if the .devcontainer folder exists within the extracted directory
  if [ -d "$EXTRACTED_DIR/.devcontainer" ]; then
    cp -r "$EXTRACTED_DIR/.devcontainer/." "$PROJECT_PATH/.devcontainer/"
  else
    echo "Error: .devcontainer folder not found in the extracted files."
    rm -rf "$ZIP_FILE" "$EXTRACTED_DIR"
    exit 1
  fi
}

download_zip
extract_zip

# Function to replace placeholders in template files
replace_placeholders() {
  local template_file=$1
  local output_file=$2

  sed \
    -e "s|{{TEMPLATE_PROJECT_NAME}}|$PROJECT_NAME|g" \
    -e "s|{{TEMPLATE_DOCKER_COMPOSE_FILE_PATH}}|$DOCKER_COMPOSE_FILE_PATH|g" \
    -e "s|{{TEMPLATE_BUILD_CONTEXT}}|$BUILD_CONTEXT|g" \
    -e "s|{{TEMPLATE_WORKSPACE_VOLUME_MOUNT}}|$WORKSPACE_VOLUME_MOUNT|g" \
    -e "s|{{TEMPLATE_GIT_USER_NAME}}|$GIT_USER_NAME|g" \
    -e "s|{{TEMPLATE_GIT_USER_EMAIL}}|$GIT_USER_EMAIL|g" \
    -e "s|{{TEMPLATE_GO_VERSION}}|$GO_VERSION|g" \
    -e "s|{{TEMPLATE_PYTHON_VERSION}}|$PYTHON_VERSION|g" \
    -e "s|{{TEMPLATE_ARCHITECTURE}}|$ARCHITECTURE|g" \
    "$template_file" > "$output_file"
}

# Set default values for placeholders
PROJECT_NAME=$(basename "$PROJECT_PATH")
DOCKER_COMPOSE_FILE_PATH="[\"docker-compose.yml\"]"
BUILD_CONTEXT="."
WORKSPACE_VOLUME_MOUNT=".:/workspace"

# Check if a docker-compose file is present in the main project folder
if [ -f "$PROJECT_PATH/docker-compose.yml" ] || [ -f "$PROJECT_PATH/docker-compose.yaml" ]; then
  DOCKER_COMPOSE_FILE_PATH="[\"../docker-compose.yml\", \"docker-compose.yml\"]"
  BUILD_CONTEXT="."
  WORKSPACE_VOLUME_MOUNT=".:/workspace:cached"
fi

# Create the .devcontainer folder if it doesn't exist
mkdir -p "$PROJECT_PATH/.devcontainer"

# Copy the template files from the script directory to the .devcontainer directory
cp "$PROJECT_PATH/.devcontainer/devcontainer.json.template" "$PROJECT_PATH/.devcontainer/devcontainer.json"
cp "$PROJECT_PATH/.devcontainer/docker-compose.yml.template" "$PROJECT_PATH/.devcontainer/docker-compose.yml"

# Replace placeholders in devcontainer.json, docker-compose.yml
replace_placeholders "$PROJECT_PATH/.devcontainer/devcontainer.json.template" "$PROJECT_PATH/.devcontainer/devcontainer.json"
replace_placeholders "$PROJECT_PATH/.devcontainer/docker-compose.yml.template" "$PROJECT_PATH/.devcontainer/docker-compose.yml"

# Clean up
rm -f "$PROJECT_PATH/$TAG.zip"
rm -rf "$EXTRACTED_DIR"
rm -f "$PROJECT_PATH/.devcontainer/devcontainer.json.template"
rm -f "$PROJECT_PATH/.devcontainer/docker-compose.yml.template"
