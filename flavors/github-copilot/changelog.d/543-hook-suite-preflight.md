### Fixed

- **Fail fast when the hook suite cannot find pytest (#543).** The suite now verifies its pytest-capable interpreter and prepares the fixture venv before hook tests, so missing prerequisites are reported immediately.
