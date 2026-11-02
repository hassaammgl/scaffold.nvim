# External templates

This directory is a placeholder for external, trusted template modules. Forge
does not load anything from here automatically. Point the plugin at your own
directory:

```lua
require("forge").setup({
  templates_dir = "~/Projects/forge-templates",
})
```

Each `.lua` file in that directory must return either one template table or a
table with a `templates` array:

```lua
-- ~/Projects/forge-templates/rust.lua
return {
  templates = {
    {
      id = "rust-binary",
      name = "Rust binary",
      language = "rust",
      version = 1,
      description = "A small Rust binary.",
      files = {
        ["Cargo.toml"] = table.concat({
          "[package]",
          'name = "{{project_slug}}"',
          'version = "0.1.0"',
          'edition = "2021"',
          "",
        }, "\n"),
        ["src/main.rs"] = 'fn main() { println!("Hello from {{project_name}}"); }\n',
        [".gitignore"] = "/target/\n",
      },
      commands = {
        build = { "cargo", "build" },
        test = { "cargo", "test" },
        run = { "cargo", "run" },
        clean = { "cargo", "clean" },
      },
    },
  },
}
```

The language must be registered before the template can be loaded:

```lua
require("forge").register_language("rust", {
  name = "Rust",
  extensions = { "rs" },
  runtimes = { "rustc", "cargo" },
  build_systems = { "cargo" },
  templates = { "rust-binary" },
  markers = { "Cargo.toml" },
})
```

File contents can also be functions of the render context, and returning `nil`
skips that file:

```lua
files = {
  ["README.md"] = function(ctx)
    return "# " .. ctx.project_name .. "\n"
  end,
  ["optional.txt"] = function(ctx)
    return nil -- skip
  end,
}
```

Template paths are validated before writing: absolute paths, `..`, backslashes,
empty segments, and NUL bytes are rejected. Existing files are not overwritten.

These modules execute in a restricted environment (no `io`, `os`, `package`,
`require`, or `vim`), but they are trusted local code, not a hard security
sandbox. Only load template directories you control and review.
