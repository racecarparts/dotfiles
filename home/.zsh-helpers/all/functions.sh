function story() {
  echo "# As a <role>, I would like to <function> so that I can <result>
  
  ✅ Acceptance Criteria
  * <a list of things to do>
  
  🤖 Technical Considerations
  * <things to consider before you start>
  
  ⛔️ Blockers
  * [ ] <a list of things to clear>
  
  ℹ️ Additional Resources
  * <some additional resources>
  
  🧪 Testing
  * How to test" | pbcopy
}

function endpoint_story() {
  echo '## Request

  * Method: `{HTTP Method}`
  * URL: `/api/{resource}`

  Body:
  ```json
  {
    "field1": "value",
    "field2": "value"
  }
  ```
  
## Response 
  Success: `200 OK`
  ```json
  {
    "data": "example",
    "message": "Operation successful"
  }
  ```' | pbcopy
}

function uuid_generator() {
  if [ -z "$1" ]
  then
    echo "error: numerical arg required (number of uuids to generate)"
    return 1 
  fi

  num_uuids=$1
  num_chars=$2

  re_num_uuids='^[0-9]+$'
  if ! [[ $num_uuids =~ $re_num_uuids ]] ; then
    echo "error: arg is not a number" >&1;
    return 1
  fi

  re_num_chars='^[0-9]*$'
  if ! [[ $num_chars =~ $re_num_chars ]]; then
    echo "error: arg for number of UUID chars is not a number" >&2;
    return 1
  fi
  
  for i in $(seq 1 $num_uuids);
  do
    u=$(uuidgen | tr "[:upper:]" "[:lower:]")
    if [ -z "$num_chars" ]; then
      echo ${u}
    else
      echo ${u:0:$num_chars}
    fi 
  done
}

function copy_file_contents() {
  if [ -f "$1" ]; then
        cat "$1" | pbcopy
        echo "Copied contents of $1 to the clipboard."
    else
        echo "File not found: $1"
    fi
}

function gcommit() {
  local OPTIND opt
  local message="" body="" co_author="Claude Sonnet 4.6 <noreply@anthropic.com>"
  local no_co_author=0 squash=0 base_branch=""

  while getopts ":m:b:c:B:snh" opt; do
    case $opt in
      m) message="$OPTARG" ;;
      b) body="$OPTARG" ;;
      c) co_author="$OPTARG" ;;
      B) base_branch="$OPTARG" ;;
      s) squash=1 ;;
      n) no_co_author=1 ;;
      h)
        echo "Usage: gcommit -m <message> [-b <body>] [-c <co-author>] [-n] [-s] [-B <base-branch>]"
        echo "  -m  commit message (required)"
        echo "  -b  commit body"
        echo "  -c  co-author trailer (default: Claude Sonnet 4.6 <noreply@anthropic.com>)"
        echo "  -n  omit co-author trailer"
        echo "  -s  squash WIP commits since base branch into one"
        echo "  -B  base branch (default: auto-detected from origin/HEAD, fallback: main)"
        return 0
        ;;
      :) echo "Option -$OPTARG requires an argument." >&2; return 1 ;;
      \?) echo "Unknown option: -$OPTARG" >&2; return 1 ;;
    esac
  done

  if [[ -z "$message" ]]; then
    local reply
    read -r "reply?Squash WIP commits? [y/N] "
    [[ "$reply" =~ ^[Yy]$ ]] && squash=1

    read -r "message?Commit message: "
    [[ -z "$message" ]] && { echo "Commit message required." >&2; return 1; }

    echo "Commit body (optional, empty line to finish):"
    local line
    while IFS= read -r "line?> "; do
      [[ -z "$line" ]] && break
      body="${body:+$body$'\n'}$line"
    done

    read -r "reply?Add co-author trailer? [Y/n] "
    if [[ "$reply" =~ ^[Nn]$ ]]; then
      no_co_author=1
    else
      read -r "reply?Co-author [${co_author}]: "
      [[ -n "$reply" ]] && co_author="$reply"
    fi
  fi

  if [[ -z "$base_branch" ]]; then
    base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    base_branch="${base_branch:-main}"
  fi

  local branch
  branch=$(git rev-parse --abbrev-ref HEAD) || return 1

  local trailer=""
  [[ $no_co_author -eq 0 ]] && trailer="Co-authored-by: $co_author"

  local full_message
  if [[ -n "$body" && -n "$trailer" ]]; then
    full_message="$(printf '%s\n\n%s\n\n%s' "$message" "$body" "$trailer")"
  elif [[ -n "$body" ]]; then
    full_message="$(printf '%s\n\n%s' "$message" "$body")"
  elif [[ -n "$trailer" ]]; then
    full_message="$(printf '%s\n\n%s' "$message" "$trailer")"
  else
    full_message="$message"
  fi

  if [[ $squash -eq 1 ]]; then
    echo "Squashing commits since origin/$base_branch..."
    GIT_SEQUENCE_EDITOR="perl -i -pe 's/^pick/fixup/ if \$. > 1'" \
      git rebase -i "origin/$base_branch" || return 1
    git commit --amend -m "$full_message" || return 1
  else
    git commit -m "$full_message" || return 1
  fi

  echo "Fetching origin..."
  git fetch origin || return 1

  echo "Rebasing onto origin/$base_branch..."
  if ! git rebase "origin/$base_branch"; then
    echo ""
    echo "Rebase conflict — resolve conflicts, then run:"
    echo "  git rebase --continue"
    echo "  git push origin $branch"
    return 1
  fi

  echo "Pushing to origin/$branch..."
  git push origin "$branch"
}

function follow_github_prs() {
  ~/.util/follow_github_org_prs.sh
}

function e1s_sso() {
  ~/.util/e1s_sso.sh
}

gprev() {
  echo "=== Matches and previous line(s) ==="
  grep "$1" -R -B1 .

  echo
  echo "=== Only previous line(s) ==="
  grep "$1" -R -B1 . | grep -v "$1"
}

gnext() {
  echo "=== Matches and next line(s) ==="
  grep "$1" -R -A1 .

  echo
  echo "=== Only next line(s) ==="
  grep "$1" -R -A1 . | grep -v "$1"
}

function zero_stl() {
  uv run ~/.util/python/zero_stl.py "$@"
}

function install_env_tools() {
  ~/.util/install-tools.sh
}

source ~/.util/mlx.sh
