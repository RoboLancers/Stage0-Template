#!/usr/bin/env bash
# Installs the FRC Mentor plugin for GitHub Copilot.
# Runs once when the container is created. Safe to rerun by hand:
#   bash .devcontainer/install-frc-mentor.sh
set -uo pipefail

REPO_URL="https://github.com/RoboLancers/frc-mentor"
BRANCH="copilot-port"
DEST="$HOME/frc-mentor"

# Copilot CLI (needs Node, which the node feature installs).
if ! command -v copilot >/dev/null 2>&1; then
  npm install -g @github/copilot || { echo "Could not install the Copilot CLI."; exit 0; }
fi

# frc-mentor is private, so clone it with your git credentials,
# which VS Code forwards into the container.
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only || true
else
  if ! git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$DEST"; then
    echo "Could not clone $REPO_URL ($BRANCH). Sign in to GitHub, then rerun:"
    echo "  bash .devcontainer/install-frc-mentor.sh"
    exit 0
  fi
fi

export COPILOT_AUTO_UPDATE=false
copilot plugin marketplace add "$DEST" || true
copilot plugin install frc-mentor@frc-mentor || true
copilot plugin list || true

echo
echo "FRC Mentor installed. Pick the 'frc-mentor:mentor' agent in Copilot Chat,"
echo "or run: copilot --agent frc-mentor:mentor"
