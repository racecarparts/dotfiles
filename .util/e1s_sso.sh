#!/bin/bash

# ~/.aws/config:
# [profile {{the-profile-name}}]
# sso_start_url  = https://start.us-gov-home.awsapps.com/directory/{{DirectoryId}}
# sso_region     = us-gov-west-1
# sso_account_id = {{AccountId}}
# sso_role_name  = {{RoleName}}
# region         = us-gov-west-1
#
# ~/.aws-e1s-sso-profile:
# {{the-profile-name}}


PROFILE_FILE="$HOME/.aws-e1s-sso-profile"

if [[ ! -f "$PROFILE_FILE" ]]; then
    echo "❌ Profile file not found: $PROFILE_FILE"
    exit 1
fi

PROFILE=$(<"$PROFILE_FILE")

# Check if SSO session is active
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "🔐 AWS SSO session expired or missing. Launching login for profile '$PROFILE'..."
    aws sso login --profile "$PROFILE"

    # Retry and exit if still not logged in
    if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
        echo "❌ AWS SSO login failed. Aborting."
        exit 1
    fi
else
    echo "✅ AWS SSO session active for profile '$PROFILE'."
fi

# Set profile and run e1s
export AWS_PROFILE="$PROFILE"
e1s "$@"
