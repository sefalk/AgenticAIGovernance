### Fixed

- **`test-hooks.ps1` no longer aborts in a consumer whose `RETRO_DIR` is `retros/auto` (#436).** The fixture helper `New-ConfWith` threw when its substitution left the config unchanged, which is exactly what happens when the project already carries the requested value (MP). The whole suite stopped there, so every later case went unexecuted in that consumer. The helper now asserts that the config carries the requested value instead of asserting that something changed; a regression case drives it with a config already set to `retros/auto`.
