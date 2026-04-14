---
name: gcommit
description: Stage changes and commit using gcommit with a Jira-prefixed message derived from the branch name. Use when the user asks to commit, make a commit, or run gcommit.
argument-hint: [optional extra context or instructions]
---

# gcommit Workflow

Craft a commit message from the diff, then invoke `gcommit` with it.

## Step 1: Gather context

Run these in parallel:

```bash
git rev-parse --abbrev-ref HEAD
```

```bash
git diff --cached --stat
git diff --cached
```

```bash
git status --short
```

```bash
# Detect WIP commits on this branch not yet on the base branch
git log --oneline origin/HEAD..HEAD
```

**WIP commit detection:** If any commits in the branch log have subjects that
are clearly placeholder/WIP (e.g. `WIP`, `wip`, `fixup!`, `squash!`,
`FIXUP`, `temp`, `tmp`, `checkpoint`, or are otherwise not a real commit
message), note them — the squash flag (`-s`) will be needed.

If nothing is staged, check whether the user wants everything staged:

```bash
git diff --stat
```

If there are unstaged changes and nothing staged, ask the user which files to
stage before proceeding.

## Step 2: Extract Jira ticket ID

Parse the branch name for a leading Jira-style key: `[A-Z]+-\d+`

Examples:
- `PROJ-163_my-feature` → `PROJ-163`
- `feature/ENG-42-new-thing` → `ENG-42`
- `fix/some-bug` → no ticket (omit prefix)

## Step 3: Draft the commit message

**Title rules:**
- Format: `TICKET-123 : <short imperative description>`
- Max 80 characters total (including the ticket prefix and ` : `)
- If the title would exceed 80 chars, cap it at ≤60 chars and move detail to
  the body instead
- Use imperative mood ("Add", "Fix", "Remove", not "Added"/"Fixed"/"Removes")
- No trailing period

**Body rules (only when needed):**
- Add a body when the title alone doesn't capture the meaningful "why" or
  when the diff covers multiple distinct concerns
- Use bullet points (`-`) or a single clarifying sentence — not both
- Wrap each line at 80 characters; break longer lines

**What NOT to include:**
- File lists or paths (the diff shows that)
- Noise phrases like "various changes", "minor tweaks", "update stuff"
- Filler words to pad length

## Step 4: Confirm before committing

Show the user the proposed title (and body if any) and ask for approval:

> **Proposed commit:**
> ```
> PROJ-163 : Brief imperative title here
>
> - Bullet one
> - Bullet two
> ```
> Proceed? [Y/n/edit]

If the user says to edit, collect their revision and update accordingly.

## Step 5: Invoke gcommit

`gcommit` is a zsh shell function defined in the user's dotfiles — invoke it
via `zsh -i -c` so the shell loads the user's profile and the function is
available. (If `gcommit` is not found, the user needs to source their dotfiles
or install them first.)

```bash
zsh -i -c 'gcommit -m "TICKET-123 : Your title here"'
```

Add `-s` when squashing WIP commits, `-b` for a body:

```bash
zsh -i -c 'gcommit -s -m "TICKET-123 : Your title here" -b "- Bullet one\n- Bullet two"'
```

**When to use `-s`:** Any time WIP/fixup/temp commits were detected in Step 1.
This squashes all branch commits since the base into one, then amends with the
new message.

`gcommit` handles the co-author trailer, rebase onto the base branch, and push
automatically — do not run those steps manually.

## Step 6: Report

After `gcommit` succeeds:
- Parse the output for a GitHub PR creation URL (lines matching
  `https://github.com/.*/pull/new/.*`) and display it as a clickable link
- Briefly confirm the commit title and whether a body was included

If `gcommit` fails (rebase conflict, hook error, etc.), surface the error
output to the user and stop — do not attempt workarounds.
