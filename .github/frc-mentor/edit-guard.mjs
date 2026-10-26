// Copilot preToolUse hook: the Copilot version of the edit guard in hooks/register.tsx.
// Copilot runs this before every tool call, in every agent, while the plugin is enabled.
// Read-only tools and the plugin's own MCP tools pass. File writes pass only for teaching
// files in ai-sandbox/. Everything else (shell, unknown tools, other MCP tools) is denied.
//
// Two callers, two formats:
// - Copilot CLI sends {toolName, toolArgs, cwd} and reads a top-level permissionDecision.
// - VS Code Copilot Chat sends {tool_name, tool_input} (Claude style), runs the hook from the
//   workspace folder, and reads hookSpecificOutput.permissionDecision.
// The guard reads either input and writes both outputs; each caller ignores the other's fields.

import { realpathSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const SANDBOX_FOLDER = 'ai-sandbox'
const SANDBOX_FILE = /(\.(html?|svg|md|txt|csv)|^\.gitignore)$/i
const DENIED =
  "Mentor mode can't change robot code or project files, or run commands. Describe the change so the student can make it. " +
  `Teaching materials (.html, .svg, .md, .txt, .csv) can go in the ${SANDBOX_FOLDER}/ folder when asked. ` +
  'A mentor can turn the FRC Mentor plugin off for themselves.'

// Tools that only read, search, or talk. Anything not listed here or below is denied.
const READ_ONLY_TOOLS = new Set([
  // Copilot CLI
  'view', 'rg', 'grep', 'glob', 'skill', 'web_fetch', 'web_search',
  'report_intent', 'ask_user', 'fetch_copilot_cli_documentation',
  // VS Code Copilot Chat (names the model sees, then the internal ids)
  'read_file', 'list_dir', 'file_search', 'grep_search', 'semantic_search', 'search_workspace_symbols',
  'get_errors', 'get_changed_files', 'read_project_structure', 'view_image', 'fetch_webpage',
  'get_vscode_api', 'test_search', 'github_repo', 'github_text_search', 'manage_todo_list',
  'vscode_askQuestions', 'tool_search', 'read_notebook_cell_output', 'copilot_getNotebookSummary',
  'get_terminal_output', 'terminal_selection', 'terminal_last_command', 'search_subagent', 'explore_subagent',
  'copilot_readFile', 'copilot_listDirectory', 'copilot_findFiles', 'copilot_findTextInFiles',
  'copilot_searchCodebase', 'copilot_searchWorkspaceSymbols', 'copilot_getErrors', 'copilot_getChangedFiles',
  'copilot_readProjectStructure', 'copilot_viewImage', 'copilot_getVSCodeAPI',
])
// Tools that write one file named by a path argument (used by some models instead of apply_patch).
const PATH_WRITE_TOOLS = new Set([
  // Copilot CLI
  'create', 'edit', 'str_replace', 'str_replace_editor', 'write',
  // VS Code Copilot Chat
  'create_file', 'replace_string_in_file', 'insert_edit_into_file',
  'copilot_createFile', 'copilot_replaceString', 'copilot_insertEdit',
])
// VS Code tools that write several files: {replacements: [{filePath, ...}, ...]}.
const MULTI_WRITE_TOOLS = new Set(['multi_replace_string_in_file', 'copilot_multiReplaceString'])
const PATCH_TOOLS = new Set(['apply_patch', 'copilot_applyPatch'])
// The plugin's own MCP tools (mcp/server.mjs). They never touch the robot project: notes go to
// ~/.frc-mentor/notes/ and feedback goes to GitHub. Copilot CLI names MCP tools `<server>-<tool>`;
// the prefix may carry a plugin namespace, so only the end of the name is matched.
const OWN_MCP_TOOL = /(?:^|[-_/:])frc-mentor[-_/](?:file_feedback|notes_read|notes_write|notes_forget)$/
// VS Code names them `mcp_<server label, lowercased, cut to 13 characters>_<tool>`.
const OWN_MCP_TOOL_VSCODE = /^mcp_frc[-_.a-z0-9]{0,12}_(?:file_feedback|notes_read|notes_write|notes_forget)$/

function normalize(path) {
  return path.replace(/\\/g, '/')
}

function isSandboxPath(path, projectRoot) {
  const normalized = normalize(path.trim())
  if (normalized.split('/').includes('..')) {
    return false
  }
  const root = normalize(projectRoot).replace(/\/+$/, '').toLowerCase()
  const lower = normalized.toLowerCase()
  const isInside =
    lower.startsWith(`${root}/${SANDBOX_FOLDER}/`) ||
    lower.startsWith(`${SANDBOX_FOLDER}/`) ||
    lower.startsWith(`./${SANDBOX_FOLDER}/`)
  const name = normalized.slice(normalized.lastIndexOf('/') + 1)
  return isInside && SANDBOX_FILE.test(name)
}

/** Every file an apply_patch touches: added, updated, deleted, or moved to. */
function patchPaths(patch) {
  const paths = []
  for (const line of patch.split(/\r?\n/)) {
    const match = line.match(/^\*\*\* (?:Add|Update|Delete) File: (.+)$/) ?? line.match(/^\*\*\* Move to: (.+)$/)
    if (match) {
      paths.push(match[1])
    }
  }
  return paths
}

function filePathOf(args) {
  return args?.path ?? args?.file_path ?? args?.filePath
}

export function decide(input, projectRoot) {
  const name = input?.toolName ?? input?.tool_name
  const tool = typeof name === 'string' ? name : ''
  const args = input?.toolArgs ?? input?.tool_input
  if (READ_ONLY_TOOLS.has(tool) || OWN_MCP_TOOL.test(tool) || OWN_MCP_TOOL_VSCODE.test(tool)) {
    return {}
  }
  if (PATCH_TOOLS.has(tool)) {
    const patch = typeof args === 'string' ? args : typeof args?.input === 'string' ? args.input : typeof args?.patch === 'string' ? args.patch : ''
    const paths = patchPaths(patch)
    const isAllowed = paths.length > 0 && paths.every(path => isSandboxPath(path, projectRoot))
    return isAllowed ? {} : deny()
  }
  if (PATH_WRITE_TOOLS.has(tool)) {
    const path = filePathOf(args)
    return typeof path === 'string' && isSandboxPath(path, projectRoot) ? {} : deny()
  }
  if (MULTI_WRITE_TOOLS.has(tool)) {
    const edits = Array.isArray(args?.replacements) ? args.replacements : []
    const isAllowed = edits.length > 0 && edits.every(edit => {
      const path = filePathOf(edit)
      return typeof path === 'string' && isSandboxPath(path, projectRoot)
    })
    return isAllowed ? {} : deny()
  }
  return deny()
}

// Both formats: Copilot CLI reads the top-level fields, VS Code reads hookSpecificOutput.
function deny() {
  return {
    permissionDecision: 'deny',
    permissionDecisionReason: DENIED,
    hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: DENIED },
  }
}

async function main() {
  let text = ''
  for await (const chunk of process.stdin) {
    text += chunk
  }
  let decision
  try {
    const input = JSON.parse(text)
    // VS Code sends no cwd, but runs the hook from the workspace folder.
    const root = input.cwd || process.env.COPILOT_PROJECT_DIR || process.cwd()
    decision = decide(input, root)
  } catch {
    // Can't read the request: fail closed.
    decision = deny()
  }
  process.stdout.write(JSON.stringify(decision))
}

// Run only when Copilot starts this file, not when a test imports it.
// Node gives import.meta.url with links resolved, but argv[1] as typed, so compare real paths.
// Otherwise a path through a symlink (PLUGIN_ROOT in a Codespace, an installed-plugin link)
// would print nothing, and Copilot treats no output as "allow".
function isMain() {
  if (!process.argv[1]) {
    return false
  }
  try {
    return realpathSync(fileURLToPath(import.meta.url)) === realpathSync(resolve(process.argv[1]))
  } catch {
    return false
  }
}

if (isMain()) {
  main()
}
