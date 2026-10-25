### Fixed

- **An empty `skills/_available/{name}/` folder is no longer reported as a duplicate activation (#464).** `deploy.ps1` and `validate-skills.py` tested for the folder, not for the skill. In MP the four stale copies were removed with `git rm`, OneDrive kept the empty folders, and every following dry run still listed all four under `Duplicate activations`, asking the user to remove copies that no longer existed. Both checks now count a duplicate only when `_available/{name}/SKILL.md` exists; a folder holding one is still reported.
