// Reloads the VS Code window once when the dev container's setup is done.
// VS Code can't be reloaded from a shell script, so post-attach.sh drops a marker
// file (after all setup scripts finish) and this extension, running in the
// container, watches for it.
// It never reloads before the folder is trusted, so the Workspace Trust prompt
// is answered once, up front, and isn't interrupted by a reload.
const vscode = require("vscode");
const fs = require("fs");
const os = require("os");
const path = require("path");

const MARKER = path.join(os.homedir(), ".cache", "devcontainer-reload-window");
const POLL_MS = 2000;
const GIVE_UP_MS = 60 * 60 * 1000; // setup never takes this long

function activate(context) {
  const started = Date.now();
  const timer = setInterval(() => {
    if (Date.now() - started > GIVE_UP_MS) {
      clearInterval(timer);
      return;
    }
    if (!vscode.workspace.isTrusted) return; // wait for the Trust answer
    if (!fs.existsSync(MARKER)) return;
    try {
      // Only the window that deletes the marker reloads, so this happens once.
      fs.unlinkSync(MARKER);
    } catch {
      return;
    }
    clearInterval(timer);
    vscode.commands.executeCommand("workbench.action.reloadWindow");
  }, POLL_MS);
  context.subscriptions.push({ dispose: () => clearInterval(timer) });
}

function deactivate() {}

module.exports = { activate, deactivate };
