# FRC Mentor guard (repository copy)

Installed from the FRC Mentor plugin, version 0.8.4, by `copilot/scripts/install-repo-guard.sh`.
Don't edit these files here: change them in the plugin, then rerun the script.

These run before every Copilot tool call in this repo, in every agent, even with the plugin turned off:

- `edit-guard.mjs` / `edit-guard.ps1`: block changes to project files and shell commands.
  Teaching files in `ai-sandbox/` are allowed. Windows uses the PowerShell copy, so it needs no Node.
- `hard-rule.json`: added to every chat message in VS Code, so every agent is told not to write
  code students could paste in.

The hook config is `.github/hooks/frc-mentor.json`. To turn the guard off for a mentor branch,
remove that file in the branch (it shows in the pull request).
