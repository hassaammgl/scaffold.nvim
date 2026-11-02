# Contributing to Forge.nvim

Thanks for helping improve Forge. This project intentionally stays small:
native Neovim APIs, no required plugins, no daemon, and no surprising side
effects.

## Development environment

- Neovim 0.11+ (0.12.x recommended)
- Lua is provided by Neovim; no separate Lua or LuaJIT installation is required
- Linux for the primary development target
- Optional real toolchains for integration checks: `gcc`/`g++`, `make`,
  `cmake`, `node`, `npm`, `python3`, and `bun`

Clone the repository and add it to `runtimepath`:

```lua
vim.opt.rtp:prepend("/path/to/forge.nvim")
require("forge").setup()
```

Run a command from a clean interactive Neovim:

```vim
:Forge
:ForgeDoctor
```

## Running the tests

The whole suite is zero-dependency and runs headless:

```sh
nvim --headless --clean -u NONE -l tests/run.lua
```

Filter by test name substring:

```sh
FORGE_TEST_FILTER=registry nvim --headless --clean -u NONE -l tests/run.lua
FORGE_TEST_FILTER="template" nvim --headless --clean -u NONE -l tests/run.lua
```

Do not report a change as tested unless `nvim ... -l tests/run.lua` actually
ran and passed. If a test is skipped because a tool is missing, say so.

### Real-toolchain smoke test

`tests/integration.lua` creates projects in a temporary directory and runs the
generated C++ (CMake and Make), JavaScript, Python, and Bun tests with the
toolchains present on your machine. It is not part of the default suite because
it depends on installed compilers and runtimes.

```sh
nvim --headless --clean -u NONE -l tests/integration.lua
```

Missing tools cause an explicit failure; install them or skip this check.

### Headless UI smoke test

`tests/ui_smoke.lua` forces the floating-window path, opens the dashboard and
major screens, and walks the wizard through its preview and confirmation
callback with deterministic `vim.ui` stubs:

```sh
nvim --headless --clean -u NONE -l tests/ui_smoke.lua
```

This is a wiring test, not a replacement for the safety specs. It must finish
with `Forge.nvim UI smoke test passed`.

## Layout

```
plugin/forge.lua              startup: register commands only
lua/forge/init.lua            public API and setup
lua/forge/config.lua          option defaults and merging
lua/forge/constants.lua       schema version, limits, patterns
lua/forge/utils.lua           notifications, formatting, small helpers
lua/forge/core/               registry, project, detection, fs, process, ...
lua/forge/ui/                 dashboard, wizard, pickers, floating windows
lua/forge/languages/          language definitions and extension registry
lua/forge/runtimes/           tool detection, versions, install plans
lua/forge/toolchains/         per-language tool profiles
lua/forge/templates/          renderer, template registry, built-in templates
lua/forge/managers/           build/test/run/clean/dependencies/environment
lua/forge/health/             :checkhealth provider
tests/                        headless specs and integration smoke test
doc/forge.txt                 Vim help
```

Design rules:

- Keep modules acyclic. Prefer passing data over requiring a sibling that
  requires you back.
- Load UI and templates lazily; startup must stay cheap.
- Commands and APIs are argv arrays. Never introduce a shell string.
- Validate at every filesystem and process boundary.
- Registry writes are atomic and schema-versioned.
- Never delete project files. Unregistering is metadata-only.
- Do not add required third-party plugins, daemons, watchers, or polling.

## Adding a language

1. Create `lua/forge/languages/<id>.lua` and call
   `require("forge.languages.registry").register("<id>", definition)`.
2. Add the module to `BUILTINS` in `lua/forge/languages/init.lua`.
3. Include `name`, `extensions`, `runtimes`, `build_systems`,
   `package_managers`, `templates`, and `markers` as appropriate.
4. Add templates under `lua/forge/templates/<id>/init.lua` and include the
   module in `BUILTIN_MODULES` in `lua/forge/templates/registry.lua`.
5. Add tool definitions to `lua/forge/runtimes/detector.lua` if new executables
   are involved. Add package mappings to `runtimes/installer.lua` only for
   pacman/apt packages you can verify.
6. Add a spec covering detection, creation, and command resolution.

Users can also register languages and templates at runtime through
`require("forge").register_language` and `register_template`; no core changes
are needed for custom extensions.

## Adding a template

A template is declared in Lua, validated before use, and copied before it is
registered. Required fields: `id`, `name`, `language`, and at least one file.
Use `{{variable}}` placeholders. File values may be strings or functions of the
render context; functions can return `nil` to skip a file.

Run the template tests before opening a pull request. They validate every
built-in template and check rendering, path safety, overwrite behavior,
unresolved variables, and command resolution.

## Style

- 2-space indentation, no tabs.
- `local` by default; expose only the module table.
- Prefer early returns for validation errors.
- Errors are `nil, message` for normal failure paths. Throw only for
  programmer errors.
- Use `vim.notify` through `lua/forge/utils.lua` so notifications respect the
  plugin's message conventions.
- Keep user-facing messages specific and actionable.
- Do not add a dependency for something Neovim already provides.

## Commit and PR checklist

- [ ] New behavior has a test in `tests/`.
- [ ] `nvim --headless --clean -u NONE -l tests/run.lua` passes.
- [ ] Docs updated: `README.md`, `doc/forge.txt`, and `CHANGELOG.md` when
      relevant.
- [ ] No new required third-party plugin, daemon, watcher, or automatic
      installation.
- [ ] No shell interpolation; argv arrays only.
- [ ] Existing project files are never overwritten or deleted.
- [ ] User configuration is not modified automatically.

Keep pull requests focused. Describe what changed, why, and exactly how you
verified it.

## Releases

1. Update `CHANGELOG.md` and the version in `lua/forge/init.lua`.
2. Run the full test suite and, where toolchains are available, the integration
   smoke test.
3. Check `:checkhealth forge` in a clean configuration.
4. Tag the release and summarize security-relevant changes.

## License

Contributions are accepted under the MIT license in `LICENSE`.
