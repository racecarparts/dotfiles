#!/bin/bash

# Load configuration variables from ~/.github_config
CONFIG_FILE="$HOME/.github_org.cfg"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Validate required configuration variables
if [[ -z "$GITHUB_TOKEN" || -z "$ORG_NAME" || -z "$TEAM_SLUG" || -z "$MAX_TITLE_LENGTH" || -z "$GRAPHQL_QUERY" || -z "$DATE_RANGE_START" || -z "$INTERVAL_MINUTES" || -z "$TEAM_MEMBERS" ]]; then
  echo "Missing required configuration variables. Please update your ~/.github_config."
  exit 1
fi

# Function to convert ISO 8601 date to Unix timestamp
iso_to_unix() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS date command
    date -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" "+%s" 2>/dev/null || echo ""
  else
    # Linux (GNU date command)
    date -d "$1" "+%s" 2>/dev/null || echo ""
  fi
}

# Function to make GraphQL request
graphql_query() {
  local query=$1
  curl -s -H "Authorization: bearer $GITHUB_TOKEN" \
          -H "Content-Type: application/json" \
          -X POST \
          -d "{\"query\": $query}" \
          https://api.github.com/graphql
}

# Truncate title function
truncate_title() {
  local title="$1"
  if [ -z "$title" ]; then
    echo "(No Title)"
  elif [ ${#title} -gt "$MAX_TITLE_LENGTH" ]; then
    echo "${title:0:$MAX_TITLE_LENGTH}..."
  else
    echo "$title"
  fi
}

# Function to compare two dates using Unix timestamps
date_in_range() {
  local created_date_unix
  local date_range_start_unix

  # Trim leading/trailing whitespace and convert to Unix timestamp
  created_date_unix=$(iso_to_unix "$(echo "$1" | sed 's/^ *//;s/ *$//')")
  date_range_start_unix=$(iso_to_unix "$DATE_RANGE_START")

  if [ -z "$created_date_unix" ] || [ -z "$date_range_start_unix" ]; then
    return 1 # False
  fi

  if [ "$created_date_unix" -gt "$date_range_start_unix" ]; then
    return 0 # True
  else
    return 1 # False
  fi
}

# Escape newlines and quotes to create a valid JSON payload
GRAPHQL_QUERY_JSON=$(echo "$GRAPHQL_QUERY" | jq -Rsa .)
NORMAL="\e[0m"
HIGHLIGHT="\e[0;32m"

# Function to execute the GraphQL query and print results
fetch_pull_requests() {
  local response=$(graphql_query "$GRAPHQL_QUERY_JSON")

  # Clear the screen
  clear

  url_spacer=0
  # Parse and print response (using jq and awk)
  echo "Repository                Title                                    PR Link    Author          Created At                Reviewers"
  echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------"
  echo "$response" | jq -r '
    .data.organization.team.repositories.edges[]
    | .node.name as $repo
    | .node.pullRequests.edges[]
    | .node as $pr
    | $pr.reviews.edges
    | group_by(.node.author.login)
    | map({
        author: .[0].node.author.login,
        states: (map(.node.state) | unique | map(
          . | if . == "APPROVED" then "✅"
            elif . == "COMMENTED" then "💬"
            elif . == "REQUESTED_CHANGES" then "🔄"
            elif . == "PENDING" then "⏳"
            elif . == "DISMISSED" then "🚫"
            else "❔" end
        ) | join(" "))
      })
    | map("\(.author) (\(.states))")
    | join(", ") as $reviewers_with_state
    | "\($repo) |\($pr.title) |\($pr.url)|\($pr.author.login) |\($reviewers_with_state) |\($pr.createdAt) |\($pr.number) |\($pr.isDraft)"
  ' | while IFS='|' read -r repo title url author reviewers_with_state created_at number isDraft; do
    if date_in_range "$created_at"; then
      if [ "$isDraft" = "true" ]; then
        title="DRAFT: $title"
      fi
      truncated_title=$(truncate_title "$title")
      # Create a hyperlink for terminals that support it
      number=$(printf %-10s $number)
      pr_url=$(printf "\e]8;;%s\e\\\\%s\e]8;;\e\\" "$url" "$number")

      created_at_iso=$(echo "$created_at" | sed 's/[[:space:]]*$//;s/Z$//')
      # Convert to UTC first, then adjust to local time
      created_at_local=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$created_at_iso" +"%s")
      created_at_local=$(date -r "$created_at_local" +"%Y-%m-%d %I:%M:%S %p")

      # Adjust printf formatting to match the widest expected content
      if [[ ",$TEAM_MEMBERS," == *",$(echo $author | xargs),"* ]]; then
          printf "${HIGHLIGHT}%-25s %-40s %-10s %-15s %-25s %-15s${NORMAL}\n" "$repo" "$truncated_title" "$pr_url" "$author" "$created_at_local" "$reviewers_with_state"
      else
          printf "%-25s %-40s %-10s %-15s %-25s %-15s\n" "$repo" "$truncated_title" "$pr_url" "$author" "$created_at_local" "$reviewers_with_state"
      fi      
    fi
  done
}

# Calculate refresh interval in seconds
REFRESH_INTERVAL=$((INTERVAL_MINUTES * 60))

# Continuously fetch and print pull requests at the specified interval
while true; do
  fetch_pull_requests
  echo
  echo "Press Enter to refresh immediately."
  echo "fetched: $(date '+%I:%M:%S %p')"
  echo "next:    $(date -v+${REFRESH_INTERVAL}S '+%I:%M:%S %p')"
  read -s -r -n 1 -t "$REFRESH_INTERVAL" key
  if [[ $key == $'\x0a' ]]; then # Check for the Enter key (newline)
        continue # Refresh the results immediately on Enter key press
    else
        continue # Refresh after timeout if no key is pressed
    fi
done
