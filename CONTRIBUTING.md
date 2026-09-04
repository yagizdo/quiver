# Contributing to Quiver

Thanks for helping out. Quiver has one maintainer, so small, focused PRs get merged fastest. If you found a bug, open a PR. If you want to add a skill, an agent, or a hook, or change how one behaves, open an issue first so we can agree on the approach before you spend an evening on it. Every feature has to pass the admission test in `CLAUDE.md`: useful on its own, and able to feed or consume other skills.

## Setup

Quiver is prompts and bash. There is nothing to build.

```bash
git clone https://github.com/yagizdo/quiver.git
cd quiver
```

To try your changes in Claude Code without installing them, start a session with the clone as a plugin directory:

```bash
claude --plugin-dir /path/to/quiver
```

For OpenCode, `./install.sh` symlinks the clone into place, so every edit is live. Cursor and the Codex CLI have their own plugin managers; see [Installation](README.md#installation) in the README.

## Tests

```bash
bash tests/run-all.sh
```

CI runs the same command on every PR. The tests are bash scripts under `tests/`, and most of them are contract checks: they read the real skill, agent, hook, and manifest files and fail when two copies of the same string drift apart. If you rename a heading or a frontmatter field and a test goes red, the test is pointing at the copy you have not updated yet. Fix the copy, not the test.

A new test goes at `tests/<area>/test-<name>.sh`. The runner discovers it, so nothing else needs editing. It must run under `bash` from any directory, exit 0 on pass, and exit nonzero on fail. Shared helpers are named `lib-*.sh` so the runner does not treat them as tests.

Skill behaviour has no automated tests; the contract tests only check that a skill's strings still match their copies elsewhere. Each `SKILL.md` ends with a `## Test Plan` section. Run it in a real session and say in the PR what you saw.

## Code

- Skills are prompts, not scripts. The shell blocks gather data; the prose tells the model what to do with it. What a shell block may and may not contain is listed under "Adding a Skill" in `CLAUDE.md`, and the hard rules are in `.claude/rules/skill-rules.md`.
- Agents are persona prompts under `agents/<category>/`. Run `/quiver:create-agent` to scaffold one. It fills in the capability profile that `tests/agents/test-capability-profile-contract.sh` checks.
- A new skill or agent also needs a row in the README. `.claude/rules/readme-structure.md` says where it goes and which skills are deliberately left out.
- Hooks are bash scripts under `hooks/scripts/`, registered in `hooks/hooks.json`.
- ASCII only, unless the file already contains Unicode.
- Do not bump the version. It lives in three manifests and the README badge, and the maintainer's release script moves all four at once. `tests/manifests/test-manifest-parity.sh` fails when they disagree.
- `docs/` is gitignored. Notes that explain a PR belong in the PR description or in an issue.

## Pull requests

Branch from `master` and keep each PR to one change. The PR title usually becomes the commit subject on `master`, so write it in the imperative mood, like "Add a PreToolUse guard for destructive Bash commands". In the description, say what problem the PR solves, what changed, and how you tested it.

## AI tools

Quiver is a plugin for AI coding tools, so using one to work on it is expected. Read and understand every line before you submit it, because you are the one I will be talking to in review. Keep AI out of the git metadata: no "Generated with Claude Code" style lines in commits or PR descriptions, and no `Co-Authored-By:` trailers naming an AI tool. GitHub turns those trailers into contributor credits, and that list is for people. `AGENTS.md` and `CLAUDE.md` carry the rules a coding agent needs; point yours at them if it does not read them on its own.

Contributions are licensed under the [MIT License](LICENSE).
