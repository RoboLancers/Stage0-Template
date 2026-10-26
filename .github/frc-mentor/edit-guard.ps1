# Copilot preToolUse hook, PowerShell version: the same decisions as edit-guard.mjs, so the
# guard runs on Windows without Node. hooks.json runs this file for the `powershell` entry
# (Windows, in both Copilot CLI and VS Code). Keep the two files in step: the parity test in
# tests/copilot/edit-guard-ps.test.mjs runs both on the same inputs and compares the results.
#
# Works in Windows PowerShell 5.1 and PowerShell 7. hooks.json loads it with Invoke-Expression,
# not `& file.ps1`, because Windows blocks running .ps1 files by default (execution policy).
# Keep this file ASCII only: Windows PowerShell 5.1 reads files without a BOM as ANSI.
#
# It reads one JSON tool call on stdin, from either caller:
# - Copilot CLI: {toolName, toolArgs, cwd}; reads a top-level permissionDecision.
# - VS Code Copilot Chat: {tool_name, tool_input}; reads hookSpecificOutput.permissionDecision.
# It always prints a decision and exits 0. An empty object means "no objection".

$FrcSandboxFolder = 'ai-sandbox'
$FrcDenied = "Mentor mode can't change robot code or project files, or run commands. Describe the change so the student can make it. " +
  "Teaching materials (.html, .svg, .md, .txt, .csv) can go in the $FrcSandboxFolder/ folder when asked. " +
  'A mentor can turn the FRC Mentor plugin off for themselves.'

function New-FrcSet([string[]]$Items) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($item in $Items) { [void]$set.Add($item) }
  return ,$set
}

# Tools that only read, search, or talk. Anything not listed here or below is denied.
$FrcReadOnlyTools = New-FrcSet @(
  # Copilot CLI
  'view', 'rg', 'grep', 'glob', 'skill', 'web_fetch', 'web_search',
  'report_intent', 'ask_user', 'fetch_copilot_cli_documentation',
  # VS Code Copilot Chat (names the model sees, then the internal ids)
  'read_file', 'list_dir', 'file_search', 'grep_search', 'semantic_search', 'search_workspace_symbols',
  'get_errors', 'get_changed_files', 'read_project_structure', 'view_image', 'fetch_webpage',
  'get_vscode_api', 'test_search', 'github_repo', 'github_text_search', 'manage_todo_list',
  'vscode_askQuestions', 'tool_search', 'read_notebook_cell_output', 'copilot_getNotebookSummary',
  'get_terminal_output', 'terminal_selection', 'terminal_last_command', 'search_subagent', 'explore_subagent',
  'copilot_readFile', 'copilot_listDirectory', 'copilot_findFiles', 'copilot_findTextInFiles',
  'copilot_searchCodebase', 'copilot_searchWorkspaceSymbols', 'copilot_getErrors', 'copilot_getChangedFiles',
  'copilot_readProjectStructure', 'copilot_viewImage', 'copilot_getVSCodeAPI'
)
# Tools that write one file named by a path argument.
$FrcPathWriteTools = New-FrcSet @(
  'create', 'edit', 'str_replace', 'str_replace_editor', 'write',
  'create_file', 'replace_string_in_file', 'insert_edit_into_file',
  'copilot_createFile', 'copilot_replaceString', 'copilot_insertEdit'
)
# VS Code tools that write several files: {replacements: [{filePath, ...}, ...]}.
$FrcMultiWriteTools = New-FrcSet @('multi_replace_string_in_file', 'copilot_multiReplaceString')
$FrcPatchTools = New-FrcSet @('apply_patch', 'copilot_applyPatch')
# The plugin's own MCP tools, as Copilot CLI and VS Code name them. \z, not $: in .NET, $ also
# matches before a final newline.
$FrcOwnMcpTool = '(?:^|[-_/:])frc-mentor[-_/](?:file_feedback|notes_read|notes_write|notes_forget)\z'
$FrcOwnMcpToolVscode = '^mcp_frc[-_.a-z0-9]{0,12}_(?:file_feedback|notes_read|notes_write|notes_forget)\z'
$FrcSandboxFile = '(\.(html?|svg|md|txt|csv)|^\.gitignore)\z'

function Get-FrcValue($Object, [string[]]$Names) {
  # The first named property that isn't null, like `a ?? b` in the Node guard.
  # Only for objects from ConvertFrom-Json; anything else has no properties here.
  if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return $null }
  foreach ($name in $Names) {
    $property = $Object.PSObject.Properties[$name]
    # The comma stops PowerShell from turning a one-item array into its item.
    if ($null -ne $property -and $null -ne $property.Value) { return ,$property.Value }
  }
  return $null
}

function Test-FrcSandboxPath([string]$Path, [string]$ProjectRoot) {
  $normalized = $Path.Trim().Replace('\', '/')
  if (($normalized.Split('/') | Where-Object { $_ -ceq '..' }).Count -gt 0) { return $false }
  $root = $ProjectRoot.Replace('\', '/').TrimEnd('/').ToLowerInvariant()
  $lower = $normalized.ToLowerInvariant()
  $ordinal = [StringComparison]::Ordinal
  $isInside = $lower.StartsWith("$root/$FrcSandboxFolder/", $ordinal) -or
    $lower.StartsWith("$FrcSandboxFolder/", $ordinal) -or
    $lower.StartsWith("./$FrcSandboxFolder/", $ordinal)
  $name = $normalized.Substring($normalized.LastIndexOf('/') + 1)
  return [bool]($isInside -and ($name -match $FrcSandboxFile))
}

function Get-FrcPatchPaths([string]$Patch) {
  # Every file a patch touches: added, updated, deleted, or moved to.
  $paths = @()
  foreach ($line in ($Patch -split '\r?\n')) {
    if ($line -cmatch '^\*\*\* (?:Add|Update|Delete) File: ([^\r\n]+)\z') { $paths += $Matches[1] }
    elseif ($line -cmatch '^\*\*\* Move to: ([^\r\n]+)\z') { $paths += $Matches[1] }
  }
  return ,$paths
}

function Get-FrcFilePath($ToolArgs) {
  $path = Get-FrcValue $ToolArgs @('path', 'file_path', 'filePath')
  if ($path -is [string]) { return $path }
  return $null
}

function Get-FrcDecision($ToolCall, [string]$ProjectRoot) {
  $name = Get-FrcValue $ToolCall @('toolName', 'tool_name')
  $tool = if ($name -is [string]) { $name } else { '' }
  $toolArgs = Get-FrcValue $ToolCall @('toolArgs', 'tool_input')

  if ($FrcReadOnlyTools.Contains($tool) -or $tool -cmatch $FrcOwnMcpTool -or $tool -cmatch $FrcOwnMcpToolVscode) {
    return $true
  }
  if ($FrcPatchTools.Contains($tool)) {
    $patch = ''
    if ($toolArgs -is [string]) { $patch = $toolArgs }
    else {
      $inner = Get-FrcValue $toolArgs @('input')
      if ($inner -isnot [string]) { $inner = Get-FrcValue $toolArgs @('patch') }
      if ($inner -is [string]) { $patch = $inner }
    }
    $paths = Get-FrcPatchPaths $patch
    if ($paths.Count -eq 0) { return $false }
    foreach ($path in $paths) {
      if (-not (Test-FrcSandboxPath $path $ProjectRoot)) { return $false }
    }
    return $true
  }
  if ($FrcPathWriteTools.Contains($tool)) {
    $path = Get-FrcFilePath $toolArgs
    return [bool]($null -ne $path -and (Test-FrcSandboxPath $path $ProjectRoot))
  }
  if ($FrcMultiWriteTools.Contains($tool)) {
    $edits = Get-FrcValue $toolArgs @('replacements')
    if ($edits -isnot [array] -or $edits.Count -eq 0) { return $false }
    foreach ($edit in $edits) {
      $path = Get-FrcFilePath $edit
      if ($null -eq $path -or -not (Test-FrcSandboxPath $path $ProjectRoot)) { return $false }
    }
    return $true
  }
  return $false
}

function Write-FrcDecision([bool]$IsAllowed) {
  if ($IsAllowed) {
    [Console]::Out.Write('{}')
    return
  }
  # Both formats: Copilot CLI reads the top-level fields, VS Code reads hookSpecificOutput.
  $decision = [ordered]@{
    permissionDecision = 'deny'
    permissionDecisionReason = $FrcDenied
    hookSpecificOutput = [ordered]@{
      hookEventName = 'PreToolUse'
      permissionDecision = 'deny'
      permissionDecisionReason = $FrcDenied
    }
  }
  [Console]::Out.Write(($decision | ConvertTo-Json -Compress -Depth 5))
}

function Invoke-FrcEditGuard {
  try {
    $text = [Console]::In.ReadToEnd()
    $toolCall = $text | ConvertFrom-Json -ErrorAction Stop
    $root = Get-FrcValue $toolCall @('cwd')
    if ($root -isnot [string] -or $root -eq '') { $root = $env:COPILOT_PROJECT_DIR }
    if (-not $root) { $root = (Get-Location).ProviderPath }
    $isAllowed = Get-FrcDecision $toolCall $root
  } catch {
    # Can't read the request: fail closed.
    $isAllowed = $false
  }
  try {
    Write-FrcDecision $isAllowed
  } catch {
    # Couldn't even print a decision. Exit code 2 blocks the call in both Copilot CLI and VS Code.
    [Console]::Error.WriteLine('FRC Mentor edit guard failed, so this tool call was blocked.')
    exit 2
  }
  exit 0
}

Invoke-FrcEditGuard
