---
description: Generate a Conventional Commits message, stage, commit, and optionally push
agent: build
---

Load the commit skill. Gather git context (branch, status, staged/unstaged changes, recent log). Generate a Conventional Commits message describing what the change does and why. Stage specific files (never `git add .`), commit with the generated message, and optionally push.
