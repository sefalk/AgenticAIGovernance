### Changed

- **`run_script` progress names the start time and the walltime bound (#508).**
  The progress line used to read `1351s: <last line>`. It now reads
  `14:02:11 - 1351s/2400s max: <last line>`:
  - the local time the script started (not the approval wait);
  - the elapsed seconds;
  - the walltime that applies to this run, whether explicit, learned from past
    runs, or taken from the suite budget.

  The collapsed subagent overview in VS Code still shows only
  `Running run_script`. That line is drawn by the client, and a server cannot
  change it.
