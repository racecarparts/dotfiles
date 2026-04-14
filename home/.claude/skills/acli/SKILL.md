---
name: acli
description: Interact with Jira via the Atlassian CLI (acli). Use for viewing, searching, creating, editing, transitioning, or commenting on Jira work items. Trigger when the user asks about Jira tickets, issues, sprints, or anything Jira-related.
argument-hint: [jira-action] [KEY-123 or description]
---

# Atlassian CLI (acli) — Jira Workflow

Use `acli jira` to interact with Jira Cloud from the terminal. Below are the most common operations.

## Viewing a work item

```bash
acli jira workitem view KEY-123
# With all fields:
acli jira workitem view KEY-123 --fields '*all'
# Specific fields:
acli jira workitem view KEY-123 --fields 'summary,description,status,assignee,comment'
# JSON output:
acli jira workitem view KEY-123 --json
# Open in browser:
acli jira workitem view KEY-123 --web
```

## Searching with JQL

```bash
# Issues assigned to me in a project
acli jira workitem search --jql "project = PROJ AND assignee = currentUser() ORDER BY updated DESC"
# Open sprint issues
acli jira workitem search --jql "project = PROJ AND sprint in openSprints() ORDER BY priority ASC"
# Issues by status
acli jira workitem search --jql "project = PROJ AND status = 'In Progress'"
# With specific output fields
acli jira workitem search --jql "..." --fields "key,summary,status,assignee"
# JSON for programmatic use
acli jira workitem search --jql "..." --json --limit 50
```

## Creating a work item

```bash
# Basic creation
acli jira workitem create --project PROJ --type Task --summary "My new task"
# With description and assignee
acli jira workitem create --project PROJ --type Story --summary "..." \
  --description "..." --assignee @me
# With parent (for subtasks/child issues)
acli jira workitem create --project PROJ --type Task --summary "..." --parent PROJ-123
# With labels
acli jira workitem create --project PROJ --type Bug --summary "..." --label "bug,urgent"
```

## Editing a work item

```bash
# Change summary
acli jira workitem edit --key PROJ-123 --summary "Updated summary"
# Reassign
acli jira workitem edit --key PROJ-123 --assignee user@example.com
# Self-assign
acli jira workitem edit --key PROJ-123 --assignee @me
# Update description
acli jira workitem edit --key PROJ-123 --description "Updated description"
# Multiple keys at once
acli jira workitem edit --key "PROJ-123,PROJ-124" --assignee @me --yes
```

## Transitioning status

```bash
# Move to a new status
acli jira workitem transition --key PROJ-123 --status "In Progress"
acli jira workitem transition --key PROJ-123 --status "Done"
acli jira workitem transition --key PROJ-123 --status "To Do"
# Without confirmation prompt
acli jira workitem transition --key PROJ-123 --status "In Review" --yes
# Bulk transition via JQL
acli jira workitem transition --jql "project = PROJ AND assignee = currentUser() AND status = 'To Do'" \
  --status "In Progress" --yes
```

## Comments

```bash
# Add a comment
acli jira workitem comment add --key PROJ-123 --comment "This is a comment"
# List comments
acli jira workitem comment list --key PROJ-123
```

## Sprint commands

```bash
# List work items in the active sprint
acli jira sprint list-workitems --id SPRINT_ID
# View sprint details
acli jira sprint view --id SPRINT_ID
```

## Tips

- Use `--json` with any command to get machine-readable output for further processing
- Use `--web` to open the result in the browser
- The project key for this repo's tickets can usually be inferred from the current branch name (e.g., `PROJ-153` → project `PROJ`)
- When the user references a ticket by branch name (e.g., `PROJ-153_my-feature`), extract the key (`PROJ-153`) and use it directly
- If the user says "my tickets" or "my issues", use `assignee = currentUser()` in JQL
- For open sprint work: `sprint in openSprints() AND project = PROJ`
