# Changelog

All notable changes to Forge.nvim are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-03

Initial MVP.

### Added

- Native dashboard (`:Forge`) with keyboard navigation and a `vim.ui.select`
  fallback for small terminals.
- Project creation wizard (`:ForgeCreate`) with language, template, runtime,
  package manager/build system, name, parent directory, template options,
  preview, explicit confirmation, optional `git init`, registration, and
  optional opening.
- Project registry (`stdpath("data")/forge/projects.json`) with registration,
  duplicate prevention, unregistration (files kept), rename, metadata updates,
  recent projects, search, missing-path detection/pruning, schema versioning and
  migration, atomic writes, and corrupt-file backups.
- Declarative template engine with `{{variable}}` rendering, function-valued
  files, option defaults, path validation, previews, no-overwrite behavior,
  and command resolution.
- Fourteen built-in templates across C, C++, JavaScript, TypeScript, Bun,
  Python, and Java:
  `c-cmake`, `c-make`, `cpp-cmake`, `cpp-make`, `js-vanilla`, `js-express`,
  `ts-node`, `ts-bun`, `bun-ts`, `python-cli`, `python-fastapi`, `java-maven`,
  `java-gradle`, `java-plain`.
- Language registry with built-in definitions and a runtime extension API.
- Runtime detection for compilers, build tools, language runtimes, package
  managers, Python tooling, Java tooling, and Git, with semantic-version
  extraction, in-memory TTL caching, and manual refresh.
- Toolchain profiles for C/C++, Node/TypeScript, Bun, Python, and Java.
- Installation planning for pacman and apt with exact-command previews,
  explicit confirmation, sudo only in the user-approved terminal command, and
  no AUR helper usage.
- Build, test, run, and clean managers with deterministic command resolution
  (explicit argv, project config, registry, template, heuristics), argv-only
  execution, explicit cwd, terminal buffers, cancellation, and first-run
  confirmation for project-provided commands.
- Declarative `.forge.json` project configuration loaded automatically, and
  executable `.forge.lua` with per-session approval and a restricted Lua
  environment.
- Project detection by markers with confidence scores, multiple candidates,
  monorepo awareness, Git-root discovery, and bounded source-extension hints.
- `:ForgeOpen`, `:ForgeRecent`, `:ForgeDetect`, `:ForgeBuild`, `:ForgeTest`,
  `:ForgeRun`, `:ForgeClean`, `:ForgeTools`, `:ForgeDoctor`, `:ForgeInstall`,
  `:ForgeTemplates`, `:ForgeRemove`, and `:ForgeCancel`.
- Native screens for runtimes, toolchains, templates, projects, settings,
  dependencies, jobs, project details, detection, installation, and doctor.
- Runtime and toolchain inspection that never starts language servers.
- `:checkhealth forge` reporting version, registry health, schema, missing
  paths, projects directory, template/language counts, package manager, and
  common tool availability.
- Public Lua API for projects, registry operations, detection, command
  execution, language/template registration, tool refresh/installation,
  cancellation, dashboard access, and events.
- Dependency-free headless test suite (76 tests) plus optional real-toolchain
  integration and headless UI smoke tests.

### Fixed during MVP development

- Function-valued template files now render `{{variables}}` in their returned
  content instead of writing unresolved placeholders.
- Availability-only runtime checks no longer populate the version cache with a
  version-less entry.
- Render contexts expose both `selected_*` and short aliases such as
  `runtime`, `build_system`, and `package_manager`, so template command
  functions resolve correctly.
- Fresh CMake projects configure before building instead of failing because
  `build/` does not exist yet.
- Clean commands always prompt, even when the resolved command was cached or
  recorded in the registry.
- Child processes inherit the user environment (notably `PATH` and `HOME`).
- Detection scans common `src/` directories for C/C++ source hints without
  walking an entire project tree.

### Security

- argv arrays only; no shell interpolation.
- Project names, destinations, template paths, and commands are validated.
- Path traversal and absolute template paths are rejected.
- Creation never overwrites existing files.
- Unregistering never deletes project files.
- `.forge.lua` is never loaded silently.
- No automatic installation, sudo, AUR helpers, language-server startup,
  daemon, watcher, or periodic polling.
