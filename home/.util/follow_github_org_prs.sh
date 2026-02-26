#!/bin/bash

# Load configuration variables from ~/.github_config
CONFIG_FILE="$HOME/.config/github_org/follow_github_org_prs.cfg"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# Validate required configuration variables
if [[ ${#ORGS[@]} -eq 0 || -z "$MAX_TITLE_LENGTH" || -z "$INTERVAL_MINUTES" || -z "$TEAM_MEMBERS" || -z "$DATE_RANGE_DAYS" ]]; then
  echo "Missing required configuration variables. Please update your $CONFIG_FILE."
  exit 1
fi

if ! command -v gh &>/dev/null; then
  echo "gh CLI not found. Install it with: brew install gh"
  exit 1
fi

if ! gh auth status &>/dev/null; then
  echo "Not authenticated with gh. Run: gh auth login"
  exit 1
fi

# Always compute DATE_RANGE_START dynamically as 60 days ago
DATE_RANGE_START=$(date -v-${DATE_RANGE_DAYS}d -u +"%Y-%m-%dT%H:%M:%SZ")

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
  gh api graphql -f "query=$query"
}

# Build GraphQL query for a given org, optionally scoped to a team
build_query() {
  local org=$1
  local team=$2

  local repos_block
  repos_block='repositories(first: 50) {
        edges {
          node {
            name
            pullRequests(first: 20, states: OPEN, orderBy: {field: CREATED_AT, direction: DESC}) {
              edges {
                node {
                  number
                  title
                  url
                  isDraft
                  createdAt
                  author { login }
                  reviews(first: 20) {
                    edges {
                      node {
                        state
                        author { login }
                      }
                    }
                  }
                  reviewRequests(first: 10) {
                    nodes {
                      requestedReviewer {
                        ... on User {
                          login
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }'

  if [[ -n "$team" ]]; then
    cat <<EOF
{
  organization(login: "$org") {
    team(slug: "$team") {
      $repos_block
    }
  }
}
EOF
  else
    cat <<EOF
{
  organization(login: "$org") {
    $repos_block
  }
}
EOF
  fi
}

# Truncate title function
truncate_title() {
  local title="$1"
  if [ -z "$title" ]; then
    echo "(No Title)"
  elif [ ${#title} -gt "$MAX_TITLE_LENGTH" ]; then
    echo "${title:0:$((MAX_TITLE_LENGTH - 3))}..."
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

NORMAL="\e[0m"
HIGHLIGHT="\e[0;32m"
YELLOW="\e[0;33m"

# Function to execute the GraphQL query and print results
fetch_pull_requests() {
  clear

  echo "Repository                     Title                                    PR Link    Author          Created At                Reviewers"
  echo "----------------------------------------------------------------------------------------------------------------------------------------------------------------------"

  for org_team in "${ORGS[@]}"; do
    local org="${org_team%%:*}"
    local team="${org_team##*:}"
    local query
    query=$(build_query "$org" "$team")
    local response
    response=$(graphql_query "$query")

    local has_team="false"
    [[ -n "$team" ]] && has_team="true"

    echo "$response" | jq -r --arg org "$org" --argjson has_team "$has_team" --arg viewer_login "$VIEWER_LOGIN" '
      (if $has_team then .data.organization.team else .data.organization end)
      | .repositories.edges[]
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
      | (($pr.reviewRequests.nodes // []) | map(.requestedReviewer.login) | any(. == $viewer_login)) as $review_requested
      | "\($org)/\($repo) |\($pr.title) |\($pr.url)|\($pr.author.login) |\($reviewers_with_state) |\($pr.createdAt) |\($pr.number) |\($pr.isDraft) |\($review_requested)"
    ' | while IFS='|' read -r repo title url author reviewers_with_state created_at number isDraft review_requested; do
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

        if [[ "$review_requested" == *"true"* ]]; then
            printf "${YELLOW}%-30s %-40s %-10s %-15s %-25s %-15s${NORMAL}\n" "$repo" "$truncated_title" "$pr_url" "$author" "$created_at_local" "$reviewers_with_state"
        elif [[ ",$TEAM_MEMBERS," == *",$(echo $author | xargs),"* ]]; then
            printf "${HIGHLIGHT}%-30s %-40s %-10s %-15s %-25s %-15s${NORMAL}\n" "$repo" "$truncated_title" "$pr_url" "$author" "$created_at_local" "$reviewers_with_state"
        else
            printf "%-30s %-40s %-10s %-15s %-25s %-15s\n" "$repo" "$truncated_title" "$pr_url" "$author" "$created_at_local" "$reviewers_with_state"
        fi
      fi
    done
  done
}

# Calculate refresh interval in seconds
REFRESH_INTERVAL=$((INTERVAL_MINUTES * 60))

# Get the currently authenticated user's login from the token
VIEWER_LOGIN=$(gh api graphql -f query='{ viewer { login } }' | jq -r '.data.viewer.login')
if [[ -z "$VIEWER_LOGIN" || "$VIEWER_LOGIN" == "null" ]]; then
  echo "Warning: Could not determine viewer login. Review-requested highlighting will be disabled."
  VIEWER_LOGIN=""
fi

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
