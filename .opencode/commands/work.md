---
description: Execute a work plan, specification, or task list systematically
agent: build
---

Load the work skill. If $ARGUMENTS is a file path (plan), execute that plan. If empty, discover plans in `.claude/plans/`. If no plan exists, treat $ARGUMENTS as a task description. Follow the 5-phase workflow: load, setup, build, check, ship.
