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
