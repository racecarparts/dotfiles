---
name: review-pr
description: Fetch unresolved PR review comments, address them, commit, push, and mark threads resolved. Use when the user asks to look at PR comments, fix review feedback, or resolve review threads.
disable-model-invocation: true
argument-hint: [pr-number]
---

# PR Review Workflow

Work through all unresolved review threads on a pull request, fix the issues, commit, push, and mark each thread resolved.

## Step 1: Identify the PR

If `$ARGUMENTS` is provided, use that as the PR number. Otherwise detect from the current branch:

```bash
gh pr view --json number,title,url,headRefName
```

## Step 2: Fetch PR state — threads, labels, and checks

Fetch all three in parallel.

**Labels:**
```bash
gh pr view NUMBER --json labels
```

Look for labels that signal action is needed — common patterns include `needs-changes`, `wip`, `do-not-merge`, `blocked`, `review-requested`, or any label the team uses to gate merges. Note them so they can be removed after the work is done.

**Check suites:**
```bash
gh pr checks NUMBER
```

Note any failing checks and include them in the work summary presented to the user before making changes. If checks are still running, report that too — do not wait for them here.

**Review threads:**
```bash
gh api graphql -f query='
{
  repository(owner: OWNER, name: REPO) {
    pullRequest(number: NUMBER) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 3) {
            nodes {
              body
              author { login }
            }
          }
        }
      }
    }
  }
}'
```

Get OWNER and REPO from the current git remote:
```bash
gh repo view --json owner,name
```

Filter to only `isResolved == false` threads before presenting them.

## Step 3: Update PR description

Fetch the current PR description and the latest commit message:

```bash
gh pr view NUMBER --json title,body
git log --format="%B" -1
```

Use the commit message as the source of truth for what changed. Then review and update the full description:

**Templated PR body** (has section headers like `# Description`, `# Checklist`, etc.):
- Find the `# Description` section and replace its body with the commit message content if it's a placeholder; leave it alone if it's already a real human-written summary
- Remove any stray content sitting above the first `#` header (e.g. commit bullets that were prepended outside the template)

**Blank / unstructured PR body** (no section headers):
- Replace the entire body with the commit message as-is

**For all PR bodies, also do the following:**
- **Checkboxes (general):** Review every `- [ ]` checkbox in the `# Checklist` section. Check any that apply; leave inapplicable ones unchecked — do not delete them.
- **Type of change checkboxes:** The `## Type of change` section instructs you to delete options that are not relevant. Keep only the boxes that apply (checked or unchecked-but-relevant); remove the rest entirely, including any instructional placeholder text like "Please delete options that are not relevant."
- **Placeholder text:** Replace any placeholder text (e.g. "Please describe...", "Ticket Name", `XXXXX`, `YYYYY`) with real content derived from the branch name, commit message, or PR title. For ticket links, look for an issue/ticket ID in the branch name (e.g. `PROJ-162`) and construct the link if the base URL can be inferred from existing links in the body.
- **`# How Has This Been Tested?`**: Fill in based on what tests exist in the repo for this change (check `__tests__/` or similar). If none exist, note that.
- **`# Links`**: Populate ticket links using any ID found in the branch name or PR title. Use `acli jira workitem view KEY-123 --web` to get the canonical browse URL (it prints the redirect URL before opening the browser). Remove any link entries that still contain placeholder text (e.g. `XXXXX`, `YYYYY`, "Ticket Name", "Documentation Link" with no real URL) — do not leave placeholder links in the body.

```bash
gh pr edit NUMBER --body "$(cat <<'EOF'
<updated body here>
EOF
)"
```

When in doubt about intent, show the proposed change to the user and ask before applying.

## Step 4: Address each comment

For each unresolved thread:

1. **Read the file at the indicated path** — use the `line` field to read relevant context (±20 lines around it)
2. **Understand what the reviewer is asking** — read the full comment body carefully
3. **Make the fix** — edit the file to address the concern
4. **Verify** — run the project's type checker (e.g. `pnpm tsc --noEmit`) if the change touches typed code

Work through all threads before moving on.

## Step 5: Run tests

Run the project's test suite to confirm nothing is broken.

## Step 6: Resolve threads

For each thread that was addressed:

1. **Post a reply comment** describing how the issue was resolved, before marking it resolved:

```bash
gh api graphql -f query='mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "THREAD_ID",
    body: "RESOLUTION_COMMENT"
  }) {
    comment { id }
  }
}'
```

Write a concise comment explaining what was changed and why (1–3 sentences). For threads where no code change was made (e.g. the suggestion was stale or intentional), note that and explain why. Always append this footer to every reply so it is clear the comment was AI-generated and not written by the user:

```
\n\n---\n*Generated with [Claude Code](https://claude.com/claude-code)*
```

2. **Then mark the thread resolved:**

```bash
gh api graphql -f query='mutation {
  resolveReviewThread(input: {threadId: "THREAD_ID"}) {
    thread { id isResolved }
  }
}'
```

Only resolve threads where a concrete fix was made or where you've explicitly explained why no change is needed. If a comment is a question or requires discussion, leave it unresolved and flag it to the user.

## Step 7: Commit and push

Stage only the files that were actually modified — avoid `git add -A` which risks accidentally staging `.env` or other unintended files:

```bash
git diff --name-only        # confirm what changed
git add <file1> <file2> ...
git commit --amend --no-edit
git push -f origin $(git branch --show-current)
```

Before pushing, confirm the current branch is not `main` or `master`. If it is a protected branch, stop and ask the user how to proceed.

## Step 7b: Re-check PR description after review fixes

Review the changes just made against the PR description updated in Step 3. If the review fixes introduced something meaningful that isn't captured (e.g. a new approach, a corrected behavior, a notable edge case), update the description to reflect it. If the fixes were minor or already implied by the existing description, leave it alone.

## Step 8: Remove blocking labels

Before removing any labels, **ask the user** which ones (if any) they'd like removed. For example:

> "The following labels are present: `needs-changes`, `missing-tests`. Should I remove any of them? (CI/CD may handle this automatically.)"

Only remove the labels the user explicitly confirms. Then:

```bash
gh pr edit NUMBER --remove-label "label-name"
```

## Step 8: Report

Summarize what was done:
- Which threads were fixed and resolved
- Which threads were skipped and why (needs discussion, etc.)
- Which labels were removed
- Any test failures or type errors that need attention
