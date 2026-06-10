---
description: Run a code review using the review orchestration pipeline
agent: build
---

Load the review skill and run a code review on the current diff. Use `git diff` against the base branch to gather the changeset, then orchestrate the appropriate review agents based on the scope and risk profile of the changes.
