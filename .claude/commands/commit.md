---
allowed-tools: Bash(git:*)
argument-hint: [message]
description: Stage all changes, commit with a message, and push to remote
---

# Git Commit and Push Workflow

## Current Status

Check the current git status and see what changes are ready to commit:

!`git status`

## Task

Stage all changes, create a commit with the provided message, and push to the remote repository.

**Commit message:** $ARGUMENTS

**Instructions:**
1. Run `git add -A` to stage all changes
2. Create a commit with the message provided above, adding the co-author line:
   ```
   git commit -m "$ARGUMENTS" -m "Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
   ```
3. Run `git push` to push to the current branch
4. Show a summary of what was committed and pushed

**Notes:**
- If there are no changes to commit, inform the user
- If the push fails, show the error and suggest solutions
- Display the commit hash after successful commit
