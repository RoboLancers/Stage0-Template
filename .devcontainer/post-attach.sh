#!/usr/bin/env bash
# Runs each time VS Code attaches, after every postCreateCommand has finished.
set -euo pipefail

# In Codespaces, files pre-copied into ~/.vscode-server/extensions never activate,
# so install the reload helper through the code CLI. A VSIX is a zip with two
# manifest files plus the extension folder, so build one with Python.
if [ "${CODESPACES:-}" = "true" ]; then
  echo "Installing dev container reload helper..."
  python3 - "$(dirname "$0")/reload-helper" /tmp/reload-helper.vsix << 'PYEOF'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
content_types = """<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension=".json" ContentType="application/json"/>
  <Default Extension=".js" ContentType="application/javascript"/>
  <Default Extension=".vsixmanifest" ContentType="text/xml"/>
</Types>
"""
manifest = """<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="devcontainer-reload-helper" Version="1.0.0" Publisher="robolancers"/>
    <DisplayName>Dev container reload helper</DisplayName>
    <Description xml:space="preserve">Reloads the window once after dev container setup.</Description>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
"""
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("extension.vsixmanifest", manifest)
    for name in os.listdir(src):
        z.write(os.path.join(src, name), "extension/" + name)
PYEOF
  code --install-extension /tmp/reload-helper.vsix --force
  rm /tmp/reload-helper.vsix
fi

# If install-frc-mentor.sh asked for a reload, hand it to the reload helper,
# which waits for the folder to be trusted, then reloads once.
if [ -f ~/.cache/devcontainer-reload-pending ]; then
  rm ~/.cache/devcontainer-reload-pending
  touch ~/.cache/devcontainer-reload-window
fi
