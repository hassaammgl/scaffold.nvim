-- Python with uv: managed virtualenv, lockfile, ruff + pytest.
-- `kind = "cli"` builds a console script; `kind = "fastapi"` builds an app.

local function pyproject(ctx)
  local deps
  local extra
  if ctx.kind == "fastapi" then
    deps = 'dependencies = [\n    "fastapi[standard]>=0.115",\n]'
    extra = table.concat({
      "",
      "[tool.pytest.ini_options]",
      'testpaths = ["tests"]',
      'pythonpath = ["src"]',
    }, "\n")
  else
    deps = 'dependencies = []'
    extra = table.concat({
      "",
      "[project.scripts]",
      ('%s = "%s.cli:main"'):format(ctx.project_slug, ctx.project_module),
      "",
      "[tool.pytest.ini_options]",
      'testpaths = ["tests"]',
      'pythonpath = ["src"]',
    }, "\n")
  end

  return table.concat({
    "[project]",
    ('name = "%s"'):format(ctx.project_slug),
    'version = "0.1.0"',
    ('description = "%s"'):format(ctx.project_name),
    'readme = "README.md"',
    'requires-python = ">=3.11"',
    deps,
    "",
    "[build-system]",
    'requires = ["hatchling"]',
    'build-backend = "hatchling.build"',
    "",
    "[tool.hatch.build.targets.wheel]",
    ('packages = ["src/%s"]'):format(ctx.project_module),
    "",
    "[dependency-groups]",
    'dev = ["pytest>=8.0", "ruff>=0.6"]',
    "",
    "[tool.ruff]",
    "line-length = 100",
    'target-version = "py311"',
    "",
    "[tool.ruff.lint]",
    'select = ["E", "F", "I", "UP", "B"]',
    extra,
    "",
    "[tool.pyright]",
    'venvPath = "."',
    'venv = ".venv"',
    "",
  }, "\n")
end

local function cli_module(ctx)
  return table.concat({
    "from __future__ import annotations",
    "",
    "import argparse",
    "",
    "",
    "def build_parser() -> argparse.ArgumentParser:",
    ('    parser = argparse.ArgumentParser(prog="%s")'):format(ctx.project_slug),
    '    parser.add_argument("name", nargs="?", default="world")',
    "    return parser",
    "",
    "",
    "def main(argv: list[str] | None = None) -> int:",
    "    args = build_parser().parse_args(argv)",
    '    print(f"Hello, {args.name}!")',
    "    return 0",
    "",
    "",
    'if __name__ == "__main__":',
    "    raise SystemExit(main())",
    "",
  }, "\n")
end

local function app_module(ctx)
  return table.concat({
    "from __future__ import annotations",
    "",
    "from fastapi import FastAPI",
    "",
    ('app = FastAPI(title="%s")'):format(ctx.project_name),
    "",
    "",
    '@app.get("/health")',
    "def health() -> dict[str, str]:",
    '    return {"status": "ok"}',
    "",
  }, "\n")
end

local function cli_test(ctx)
  return table.concat({
    ("from %s.cli import main"):format(ctx.project_module),
    "",
    "",
    "def test_main_greets(capsys) -> None:",
    '    assert main(["scaffold"]) == 0',
    '    assert "Hello, scaffold!" in capsys.readouterr().out',
    "",
  }, "\n")
end

local function app_test(ctx)
  return table.concat({
    "from fastapi.testclient import TestClient",
    "",
    ("from %s.app import app"):format(ctx.project_module),
    "",
    "client = TestClient(app)",
    "",
    "",
    "def test_health() -> None:",
    '    response = client.get("/health")',
    "    assert response.status_code == 200",
    '    assert response.json() == {"status": "ok"}',
    "",
  }, "\n")
end

local function readme(ctx)
  if ctx.kind == "fastapi" then
    return table.concat({
      "# {{project_name}}",
      "",
      "FastAPI project managed with uv.",
      "",
      "```sh",
      "uv sync                 # creates .venv and installs dependencies + dev tools",
      "uv run python -m {{project_module}}   # http://127.0.0.1:8000/docs",
      "uv run pytest -q",
      "uv run ruff check .",
      "```",
      "",
      "Activate the environment manually if you prefer:",
      "",
      "```sh",
      "uv venv && source .venv/bin/activate",
      "```",
      "",
    }, "\n")
  end
  return table.concat({
    "# {{project_name}}",
    "",
    "Python CLI managed with uv.",
    "",
    "```sh",
    "uv sync                 # creates .venv and installs dependencies + dev tools",
    "uv run {{project_slug}} hello",
    "uv run pytest -q",
    "uv run ruff check .",
    "```",
    "",
    "Activate the environment manually if you prefer:",
    "",
    "```sh",
    "uv venv && source .venv/bin/activate",
    "```",
    "",
  }, "\n")
end

local function gitignore()
  return table.concat({
    ".venv/",
    "__pycache__/",
    "*.py[cod]",
    "*.egg-info/",
    "dist/",
    "build/",
    ".pytest_cache/",
    ".ruff_cache/",
    ".mypy_cache/",
    "",
  }, "\n")
end

return {
  templates = {
    {
      id = "python-uv",
      name = "Python Project (uv)",
      language = "python",
      version = 1,
      description = "Python project managed by uv: virtualenv, lockfile, ruff, pytest.",
      build_systems = {},
      runtime_options = { "python3" },
      default_runtime = "python3",
      package_managers = {},
      requires = { "uv" },
      options = {
        kind = {
          type = "select",
          label = "Project kind",
          values = { "cli", "fastapi" },
          default = "cli",
        },
      },
      files = {
        ["pyproject.toml"] = pyproject,
        ["src/{{project_module}}/__init__.py"] = '__version__ = "0.1.0"\n',
        ["src/{{project_module}}/cli.py"] = function(ctx)
          if ctx.kind ~= "cli" then
            return nil
          end
          return cli_module(ctx)
        end,
        ["src/{{project_module}}/__main__.py"] = function(ctx)
          if ctx.kind == "fastapi" then
            return table.concat({
              "import uvicorn",
              "",
              "",
              'if __name__ == "__main__":',
              ('    uvicorn.run("%s.app:app", host="127.0.0.1", port=8000, reload=True)'):format(ctx.project_module),
              "",
            }, "\n")
          end
          return table.concat({
            ("from %s.cli import main"):format(ctx.project_module),
            "",
            "raise SystemExit(main())",
            "",
          }, "\n")
        end,
        ["src/{{project_module}}/app.py"] = function(ctx)
          if ctx.kind ~= "fastapi" then
            return nil
          end
          return app_module(ctx)
        end,
        ["tests/test_cli.py"] = function(ctx)
          if ctx.kind ~= "cli" then
            return nil
          end
          return cli_test(ctx)
        end,
        ["tests/test_app.py"] = function(ctx)
          if ctx.kind ~= "fastapi" then
            return nil
          end
          return app_test(ctx)
        end,
        [".gitignore"] = gitignore,
        ["README.md"] = readme,
      },
      commands = {
        build = { "uv", "sync" },
        test = { "uv", "run", "pytest", "-q" },
        run = function(ctx)
          return { "uv", "run", "python", "-m", ctx.project_module }
        end,
      },
      install_commands = {
        { label = "Create the virtualenv and install dependencies (uv sync)", argv = { "uv", "sync" } },
      },
    },
  },
}
