### Fixed

- **Producer gates now check the repository the edited file belongs to, not the repository the hook is deployed in (#456).** In a multi-root workspace only one repository ships agents, so its `test-writer-pretooluse` and `refactorer-pretooluse` fire for edits in every root, and each proved the branch of its own checkout. In the MP + AF workspace, a test-writer editing AF tests on `agent/454-…` was refused because MP sat on `dev`. The reverse case, an edit in a second repository on `dev`, passed whenever the deploying repository was on an `agent/*` branch.
  - Both hooks, in both dialects, now resolve each written path's repository with `git rev-parse --show-toplevel --show-prefix`, asking the nearest existing ancestor so new files work too. They prove that repository's branch.
  - The test-writer also takes `SRC_DIR` from the edited repository's `.github/af-env.conf`. A repository without one inherits the deploying repository's value, so a second repository is never guarded more weakly than before.
  - Calls that name no path, and paths outside any repository, keep the old behaviour.
  - An edit in the main checkout while a worktree sentinel is active is now judged by the main checkout's branch, as the edited file dictates.
  - The deny reason names the repository root.
  - The stop gates are not yet repo-aware; they follow with #101.
