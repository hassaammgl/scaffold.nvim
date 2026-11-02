# Forge.nvim

A native, lightweight project and development environment manager for Neovim.

Forge.nvim lives entirely inside Neovim. It creates projects from declarative
templates, keeps a small metadata registry, detects languages and build
systems, inspects installed toolchains, and runs project commands in terminal
buffers. It has no required plugin dependencies, no daemon, no background
watcher, and no automatic installation.

- **Native UI**: `vim.ui.select`, `vim.ui.input`, floating windows.
- **Native execution**: `vim.system`, terminal buffers, argv arrays only.
- **Native persistence**: `vim.json` plus atomic registry writes.
- **Extensible**: register languages and templates without patching core code.
- **Safe by default**: no overwrites, no deletion of project files, no silent
  dependency installation, no automatic execution of project configuration.

Requires Neovim **0.11+** (developed and tested against 0.12.x). Linux is the
primary target; Arch Linux and Debian/Ubuntu package names are supported for
optional install plans.

---

## Installation

Forge is a plain Neovim runtime directory. Copy or clone it somewhere, then add
that directory to `runtimepath` before calling `setup()`.

```lua
-- ~/.config/nvim/init.lua
vim.opt.rtp:prepend(vim.fn.expand("~/Projects/forge.nvim"))

require("forge").setup({
  projects_dir = "~/Projects",
  confirm_before_install = true,
})
```

There is no lazy-loading requirement. If you use a plugin manager, point it at
the repository and call `require("forge").setup(...)`; Forge does not depend on
the manager.

For a quick isolated check:

```sh
nvim --clean --cmd 'set rtp^=/path/to/forge.nvim' -c 'Forge'
```

`:Forge` opens the dashboard. `:ForgeCreate` starts the project wizard.

---

## Quick start

1. `:ForgeCreate`
2. Choose a language (C, C++, JavaScript, TypeScript, Bun, Python, Java).
3. Choose a project type/template.
4. Choose a runtime, package manager, or build system when the template offers
   more than one.
5. Enter a project name and parent directory.
6. Set template options (for example C++ standard, C++ project kind, Java
   release).
7. Review the file and command preview.
8. Press `<CR>` to create. Existing files are never overwritten.
9. Forge optionally runs `git init`, registers the project, and opens it.
10. If the template has dependency commands, Forge prints them. It does not run
    them.

The dashboard exposes the same actions:

```
:Forge
  Projects    Open, Recent, Search, Current
  Create      New project, Browse templates
  Development Build, Run, Test, Clean, Dependencies, Running commands
  Environment Runtimes, Toolchains, Doctor
  Settings    Registry and paths, Unregister project
```

Dashboard keys: `j`/`k` move, `<CR>` select, `g?` help, `q`/`<Esc>` close.
Other screens use `q` to close and may add `r` (refresh) or `i` (install plan).

---

## Commands

| Command | Description |
| --- | --- |
| `:Forge` | Open the dashboard. |
| `:ForgeCreate` | Start the project creation wizard. |
| `:ForgeOpen [project\|dir]` | Open a registered project or directory (changes cwd). Without an argument, choose from a list. |
| `:ForgeRecent` | Choose from recently opened projects. |
| `:ForgeDetect [dir]` | Inspect project markers and confidence. Defaults to the current buffer/cwd. |
| `:ForgeBuild` | Build the current project. |
| `:ForgeTest` | Run the project test command. |
| `:ForgeRun` | Run the project. |
| `:ForgeClean` | Clean build artifacts (always asks for confirmation). |
| `:ForgeTools [tool]` | Show runtime status; with a tool name, show its path, version, and install plan. |
| `:ForgeDoctor` | Run `:checkhealth forge`. |
| `:ForgeInstall [tool]` | Build and confirm an install command for a tool. |
| `:ForgeTemplates [language]` | Browse templates. |
| `:ForgeRemove [project]` | Remove a project from the registry. **Files are kept.** |
| `:ForgeCancel` | List running Forge commands and cancel one. |

Commands complete project names, directories, language ids, and tool names
where applicable. Forge installs **no global keymaps** unless you configure
them (see below).

---

## Configuration

`require("forge").setup()` is optional; defaults are usable. Options are merged
over the defaults, so calling `setup()` more than once is safe.

```lua
require("forge").setup({
  projects_dir = "~/Projects",           -- where new projects are created
  registry_path = vim.fn.stdpath("data") .. "/forge/projects.json",
  templates_dir = "~/Projects/forge-templates", -- optional external templates
  confirm_before_install = true,         -- ask before package installation
  confirm_before_project_commands = true, -- first run of project commands
  open_after_create = true,              -- prompt default in the wizard
  allow_lua_project_config = true,       -- set false to disable .forge.lua
  runtime_cache_ttl = 300,               -- seconds; 0 disables version caching
  terminal_split = "botright 14split",   -- terminal used for commands
  keymaps = {},                          -- no global maps unless populated
})
```

Optional keymaps (Forge refuses to overwrite an existing mapping):

```lua
require("forge").setup({
  keymaps = {
    dashboard = "<leader>fp",
    create = "<leader>fn",
    open = "<leader>fo",
    recent = "<leader>fr",
    detect = "<leader>fd",
    build = "<leader>fb",
    test = "<leader>ft",
    run = "<leader>fx",
    clean = "<leader>fc",
    tools = "<leader>fy",
    doctor = "<leader>fh",
    install = "<leader>fi",
    templates = "<leader>fm",
    remove = "<leader>fR",
    cancel = "<leader>fk",
  },
})
```

---

## Supported templates

Built-in templates are declarative and versioned.

| Language | Template ids |
| --- | --- |
| C | `c-cmake`, `c-make` |
| C++ | `cpp-cmake`, `cpp-make` |
| JavaScript | `js-vanilla`, `js-express` |
| TypeScript | `ts-node`, `ts-bun` |
| Bun | `bun-ts` |
| Python | `python-cli`, `python-fastapi` |
| Java | `java-maven`, `java-gradle`, `java-plain` |

C++ templates support C++17/20/23 and console or library layouts. JavaScript,
TypeScript, and Bun templates support npm, pnpm, yarn, and Bun package
managers where applicable. Python templates use a `src/` layout and do not
create a virtual environment automatically. Java Maven/Gradle templates expect
`mvn`/`gradle`; `java-plain` needs `javac` and `java`.

Runtime detection recognizes: `gcc`, `g++`, `clang`, `clang++`, `clangd`,
`make`, `cmake`, `ninja`, `gdb`, `node`, `npm`, `pnpm`, `yarn`, `bun`, `tsc`,
`python3`, `pip`, `pipx`, `ruff`, `basedpyright`, `pytest`, `java`, `javac`,
`mvn`, `gradle`, `jdtls`, and `git`.

Forge never starts a language server to check whether it is installed. Version
checks are executed only when a status screen or API call asks for them, and
are cached for `runtime_cache_ttl`.

---

## Build, test, run, clean

Command resolution is deterministic:

1. Explicit argv passed through the API.
2. Project configuration (`.forge.json`, or approved `.forge.lua`).
3. Commands recorded in the registry when the project was created.
4. The template's commands, re-rendered with stored options.
5. Build-system heuristics (`CMakeLists.txt`, `Makefile`, `package.json`,
   `pyproject.toml`, `pom.xml`, `build.gradle`, `Cargo.toml`, `go.mod`, ...).

Commands always run as argv arrays with an explicit working directory. Nothing
is passed through a shell. Long-running commands run in a terminal buffer and
can be cancelled with `:ForgeCancel`; Forge does not block the editor.

A newly created CMake project has no `build/` directory yet, so the first Build
configures with CMake and tells you to Build again to compile.

Project-provided commands are confirmed once per Neovim session. Clean commands
always ask for confirmation. Registry/template commands recorded by Forge run
without an extra prompt.

---

## Project configuration

`.forge.json` is declarative and is read automatically:

```json
{
  "language": "typescript",
  "runtime": "bun",
  "package_manager": "bun",
  "commands": {
    "build": ["bun", "run", "build"],
    "test": ["bun", "test"],
    "run": ["bun", "run", "dev"]
  }
}
```

Command entries may also include a working directory:

```json
{
  "commands": {
    "build": { "argv": ["make", "-C", "native"], "cwd": "native" }
  }
}
```

`.forge.lua` is executable Lua and is **never loaded silently**. The first time
a project's `.forge.lua` is needed, Forge asks for approval for that session.
The file is evaluated with a restricted environment (no `io`, `os`, `package`,
`require`, or `vim`), but treat it as executable code: only approve projects
you trust. Set `allow_lua_project_config = false` to disable it entirely.

```lua
return {
  language = "typescript",
  runtime = "bun",
  package_manager = "bun",
  commands = {
    build = { "bun", "run", "build" },
    test = { "bun", "test" },
    run = { "bun", "run", "dev" },
  },
}
```

The registry stores metadata only. `.forge.json` / `.forge.lua` describes a
project's own configuration. Unregistering a project never deletes files.

---

## Custom languages and templates

```lua
require("forge").register_language("rust", {
  name = "Rust",
  extensions = { "rs" },
  runtimes = { "rustc", "cargo" },
  build_systems = { "cargo" },
  templates = { "rust-binary" },
  markers = { "Cargo.toml" },
})

require("forge").register_template({
  id = "rust-binary",
  name = "Rust binary",
  language = "rust",
  version = 1,
  files = {
    ["src/main.rs"] = 'fn main() { println!("Hello from {{project_name}}"); }\n',
    ["Cargo.toml"] = '[package]\nname = "{{project_slug}}"\nversion = "0.1.0"\nedition = "2021"\n',
    [".gitignore"] = "/target/\n",
  },
  commands = {
    build = { "cargo", "build" },
    run = { "cargo", "run" },
    test = { "cargo", "test" },
  },
})
```

Templates are data. File paths are validated against traversal and absolute
paths, file contents may be strings or functions of the render context, and
existing files are skipped unless the API is explicitly told to overwrite.

Render context variables include `project_name`, `project_slug`,
`project_module`, `project_path`, `selected_language`, `selected_runtime`,
`selected_build_system`, `selected_package_manager`, `template_id`, `year`,
`date`, `author`, plus every template option both as its own name and as
`selected_<option>` (for example `standard` and `selected_standard`).

Template options support `input`, `select`, and `confirm` types:

```lua
options = {
  standard = { type = "select", values = { "17", "20", "23" }, default = "23" },
  tests = { type = "confirm", default = true },
  author = { type = "input", default = "" },
}
```

External templates can be placed in the configured `templates_dir`. Each `.lua`
file returns a template table or `{ templates = { ... } }`. External modules run
in a restricted environment; they are trusted local code, not a hard sandbox.

See `templates/README.md` for an external template example.

---

## Registry

Default path: `vim.fn.stdpath("data") .. "/forge/projects.json"`.

Each record looks like:

```json
{
  "id": "unique-project-id",
  "name": "my-project",
  "path": "/home/user/Projects/my-project",
  "language": "cpp",
  "template": "cpp-cmake",
  "runtime": "g++",
  "build_system": "cmake",
  "package_manager": null,
  "created_at": 0,
  "last_opened": 0,
  "commands": {}
}
```

Features: registration, duplicate prevention, unregistration (metadata only),
opening, recent projects, search, rename, metadata updates, missing-path
detection and pruning, schema versioning and migration, and corrupt-file
backups (`.corrupt-<timestamp>`). Writes are atomic: a temp file is fsynced and
renamed over the target.

If the registry is corrupt, Forge keeps a backup and starts from an empty
registry instead of crashing. Project files are never touched.

---

## Security model

- argv arrays only; no shell interpolation or concatenation.
- project names, template paths, destinations, and commands are validated.
- path traversal and absolute template paths are rejected.
- existing files are never overwritten during project creation.
- unregistering or pruning never deletes project files.
- `.forge.lua` and external templates are not loaded silently; `.forge.lua`
  requires approval, and both run with restricted globals.
- no automatic runtime or dependency installation.
- install plans show the exact command and require confirmation; Forge never
  runs sudo on its own, never uses AUR helpers, and only maps pacman/apt
  packages.
- no language server is started for detection.
- no background daemon, watcher, polling, or indexing.

The sandbox for configuration/template Lua reduces accidental access; it is not
a security boundary against deliberately malicious code. Only approve files you
trust.

---

## Public API

```lua
local forge = require("forge")

forge.setup(opts)                         -- merge configuration
forge.create_project(opts)                -- create (or plan with dry_run)
forge.open_project(target)                -- registry record, id, or path
forge.detect_project(path)                -- detection result or nil, err
forge.get_current_project()               -- registry record or detected project
forge.run_command(kind_or_argv, opts)     -- build/test/run/clean or argv
forge.projects()                          -- all registry records
forge.project(id)                         -- one record
forge.register_project(record)            -- register metadata
forge.unregister_project(id)              -- remove metadata (keeps files)
forge.recent_projects(limit)              -- recent records
forge.search_projects(query)              -- search by name/path/language
forge.languages()                         -- language definitions
forge.templates(language)                 -- template definitions
forge.register_language(id, definition)
forge.register_template(template)
forge.refresh_tools()                     -- refresh runtime detection
forge.install_tool(tool)                  -- show plan + confirm + terminal
forge.cancel_commands()                   -- cancel all Forge jobs
forge.open_dashboard()
forge.events()                            -- in-process event bus
```

`create_project` accepts `name`, `language`, `template`, `parent_dir`,
`runtime`, `build_system`, `package_manager`, `options`, `git`, `open`, and
`dry_run`. With `dry_run = true` it returns the plan without writing anything.

Events: `project_created`, `project_opened`, `job_started`, `job_exited` (see
`lua/forge/core/events.lua` for the exact payloads).

Errors are returned as `nil, message`, often with a third metadata table. Forge
does not throw for ordinary validation and process failures.

---

## Health check

```vim
:checkhealth forge
```

Checks Neovim version, registry readability/schema, missing project paths,
projects directory, template and language counts, external template directory,
`git`, package-manager detection, and common runtimes. It does not run version
checks or start language servers.

---

## Testing

The test suite is dependency-free and runs in a clean headless Neovim:

```sh
nvim --headless --clean -u NONE -l tests/run.lua
```

76 tests cover validation, path traversal, filesystem safety, registry
recovery/schema migration, detection, runtime parsing, template rendering,
project creation, command resolution, process behavior, extension APIs, user
commands, and health checks. Tests skip missing toolchains; they only execute
real build commands in the separate integration smoke test described in
`CONTRIBUTING.md`. An optional headless UI wiring test is available at
`tests/ui_smoke.lua`.

Filter by name:

```sh
FORGE_TEST_FILTER=registry nvim --headless --clean -u NONE -l tests/run.lua
```

---

## Known limitations

- Neovim 0.11+ is required; older versions are not supported.
- The install workflow only understands `pacman` and `apt`, and only package
  names listed in `lua/forge/runtimes/installer.lua`. It never uses AUR
  helpers. Tools without a mapping get a manual hint instead.
- Built-in templates are intentionally small starters. They do not install
  frameworks, pin lockfiles, or configure LSP. Java templates require an
  existing Maven or Gradle installation.
- The MVP ships 14 templates. Hono, Flask, Django, Spring Boot, and
  Ninja-specific project scaffolds are not built in; they can be added through
  the language/template extension API (see `templates/README.md`) without
  patching Forge.
- Runtime version parsing is heuristic (`X.Y.Z`, then `X.Y`, then `X`).
- Detection is marker-based and bounded; it inspects a directory and its
  parents (plus `src/` for C/C++ source hints), not an entire repository.
- `.forge.lua` approval is per Neovim session, keyed by file path.
- Windows paths are not a supported configuration target. Core filesystem
  helpers are mostly portable, but package management and shell-free terminal
  behavior are tested on Linux only.
- Forge does not manage LSP clients, formatters, or debuggers. It reports
  whether their executables exist and leaves configuration to you.

---

## Documentation and license

- Vim help: `:help forge.nvim` (source: `doc/forge.txt`)
- Contributing: `CONTRIBUTING.md`
- Changelog: `CHANGELOG.md`
- License: MIT (`LICENSE`)
# scaffold.nvim
# scaffold.nvim
