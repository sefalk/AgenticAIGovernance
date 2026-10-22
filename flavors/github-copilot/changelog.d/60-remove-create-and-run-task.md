### Removed

- **`createAndRunTask` is removed from every agent and denied by `block-dangerous` (#60).** The coordinator, implementer, refactorer and code-critic no longer hold it. It wrote an agent-authored task into `.vscode/tasks.json`, could never be auto-approved, and minted a new label for every argument set (one consumer: 227 tasks for 118 invocations, #396). Fixed invocations run with `runTask`; argument-bearing ones go through `af-command`'s `run_script`. Where `af-command` is not registered, agents report BLOCKED instead of falling back. Both hook dialects drop the creation allowlist and the #396 duplicate check (about 170 lines each) and `hooks/scripts/task-duplicate.py`; every task-creation payload now denies with a reason that names the two routes left.

### Changed

- **`AF_SCRIPT_APPROVAL=ask` documents that chat "Allow all" answers the prompt (#60).** Measured in the 2026-10-22 live check: with "Allow all" VS Code answers the server's elicitation itself, so `ask` gives no human gate. Keep default chat permissions with `af-command`.
