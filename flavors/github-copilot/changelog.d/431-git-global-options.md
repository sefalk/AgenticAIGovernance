### Security

- **`block-dangerous` no longer fails open on git's global options (#431).**
  Every git deny rule was anchored at `git <subcommand>`, so a global option in
  between hid the subcommand. `git -C <path> push --force`,
  `git -C <path> branch -D`, `git -c k=v reset --hard`, `git -C <path> add .`
  and `git --no-pager -C <path> rebase` all ran unchallenged in both hook
  shells. `git -C <absolute path>` is the very form agents are told to use in
  multi-root windows.
  - Both hooks remove git's global options (`-C`, `-c`, `--git-dir`,
    `--work-tree`, `--namespace`, `--config-env`, `--opt=value`, `--no-pager`,
    `-p`/`-P`, …) from each scan unit before the deny rules run. The rules
    themselves are unchanged.
  - The allow tier still judges the command as written, so no auto-approval was
    widened.
  - Side effect, also fixed: `git -C <path> commit -m "… git push --force …"`
    was a false deny, because the commit message was no longer recognised as
    data.
