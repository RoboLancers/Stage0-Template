FROM mcr.microsoft.com/devcontainers/java:3-25-trixie

# post-attach.sh uses Python to package the reload helper for Codespaces.
RUN command -v python3 >/dev/null \
 || (apt-get update && apt-get install -y --no-install-recommends python3 && rm -rf /var/lib/apt/lists/*)

# Pre-install the reload helper for local dev containers. It reloads the window once
# after install-frc-mentor.sh clones the plugin, so Copilot Chat loads it.
# (Codespaces installs it in post-attach.sh instead.)
RUN mkdir -p /home/vscode/.vscode-server/extensions \
 && chown -R vscode:vscode /home/vscode/.vscode-server
COPY --chown=vscode:vscode reload-helper /home/vscode/.vscode-server/extensions/robolancers.devcontainer-reload-helper-1.0.0
