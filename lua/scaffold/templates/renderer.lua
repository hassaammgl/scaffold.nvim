-- Declarative template renderer.
--
-- Templates are data. File contents may be strings with {{variables}} or
-- functions receiving the render context. Nothing here writes outside the
-- destination directory, and existing files are never overwritten unless the
-- caller explicitly opts in.

local fs = require("scaffold.core.filesystem")
local validator = require("scaffold.core.validator")
local utils = require("scaffold.utils")

local M = {}

local VARIABLE_PATTERN = "{{%s*([%w_%-%.]+)%s*}}"

-- Build the variable table handed to templates.
function M.context(template, values)
  values = values or {}
  local options = values.options or {}
  local slug = values.project_slug or utils.slugify(values.project_name or "project")

  local ctx = {
    project_name = values.project_name or slug,
    project_slug = slug,
    project_module = slug:gsub("[^%w_]", "_"),
    project_path = values.project_path or "",
    language = values.language or (template and template.language) or "",
    runtime = values.runtime or "",
    build_system = values.build_system or "",
    package_manager = values.package_manager or "",
    selected_language = values.language or (template and template.language) or "",
    selected_runtime = values.runtime or "",
    selected_build_system = values.build_system or "",
    selected_package_manager = values.package_manager or "",
    template_id = template and template.id or "",
    year = os.date("%Y"),
    date = os.date("%Y-%m-%d"),
    author = values.author or vim.env.USER or "",
  }

  for key, value in pairs(options) do
    ctx[key] = value
    if type(value) ~= "table" then
      ctx["selected_" .. key] = value
    end
  end
  return ctx
end

-- Fill defaults for template options and validate the supplied values.
function M.apply_defaults(template, provided)
  local values = vim.deepcopy(provided or {})
  for name, definition in pairs(template.options or {}) do
    if values[name] == nil then
      values[name] = definition.default
    end
    local value = values[name]
    local option_type = definition.type or "input"
    if option_type == "select" then
      if value == nil then
        return nil, ("option '%s' is required"):format(name)
      end
      if not utils.tbl_contains(definition.values or {}, value) then
        return nil, ("option '%s' must be one of: %s"):format(name, table.concat(definition.values or {}, ", "))
      end
    elseif option_type == "confirm" then
      if type(value) ~= "boolean" then
        return nil, ("option '%s' must be a boolean"):format(name)
      end
    elseif option_type == "input" then
      if value ~= nil and type(value) ~= "string" then
        return nil, ("option '%s' must be a string"):format(name)
      end
      if definition.required and (value == nil or value == "") then
        return nil, ("option '%s' is required"):format(name)
      end
    else
      return nil, ("option '%s' has unknown type '%s'"):format(name, tostring(option_type))
    end
  end
  return values
end

-- Returns rendered string and a list of unresolved variable names.
function M.render_string(input, ctx)
  local unresolved = {}
  local seen = {}
  local rendered = input:gsub(VARIABLE_PATTERN, function(key)
    local value = ctx[key]
    if value == nil then
      if not seen[key] then
        seen[key] = true
        unresolved[#unresolved + 1] = key
      end
      return "{{" .. key .. "}}"
    end
    if type(value) == "table" then
      if not seen[key] then
        seen[key] = true
        unresolved[#unresolved + 1] = key
      end
      return "{{" .. key .. "}}"
    end
    return tostring(value)
  end)
  return rendered, unresolved
end

-- Resolve a template command definition into an argv array.
-- Returns argv, cwd, err.
function M.resolve_command(value, ctx)
  local resolved = value
  local cwd = nil
  if type(value) == "function" then
    local ok, result = pcall(value, ctx)
    if not ok then
      return nil, nil, "template command failed: " .. tostring(result)
    end
    resolved = result
  end
  if resolved == nil then
    return nil, nil, nil
  end
  if type(resolved) == "table" and not utils.is_list(resolved) and resolved.argv ~= nil then
    cwd = resolved.cwd
    resolved = resolved.argv
  end
  if type(resolved) ~= "table" then
    return nil, nil, "template command must be an argv array or a function returning one"
  end
  local ok, err = validator.command(resolved)
  if not ok then
    return nil, nil, err
  end
  local argv = {}
  for index, token in ipairs(resolved) do
    local rendered, unresolved = M.render_string(token, ctx)
    if #unresolved > 0 then
      return nil, nil, "unresolved command variable(s): " .. table.concat(unresolved, ", ")
    end
    argv[index] = rendered
  end
  if cwd then
    local rendered_cwd, unresolved = M.render_string(cwd, ctx)
    if #unresolved > 0 then
      return nil, nil, "unresolved cwd variable(s): " .. table.concat(unresolved, ", ")
    end
    cwd = rendered_cwd
  end
  return argv, cwd, nil
end

-- Produce a plan describing every file that would be written.
function M.plan(template, ctx, destination)
  local errors = {}
  local operations = {}

  local dest_ok, dest = validator.absolute_path(destination)
  if not dest_ok then
    return { template = template, context = ctx, destination = destination, operations = {}, errors = { dest } }
  end

  local raw_files = template.files or {}
  local paths = utils.sorted_keys(raw_files)

  for _, raw_path in ipairs(paths) do
    local rendered_path, unresolved = M.render_string(raw_path, ctx)
    if #unresolved > 0 then
      errors[#errors + 1] = ("file '%s' has unresolved variable(s): %s"):format(raw_path, table.concat(unresolved, ", "))
    else
      local path_ok, path_err = validator.relative_path(rendered_path)
      if not path_ok then
        errors[#errors + 1] = ("invalid template path: %s"):format(path_err)
      else
        local target = fs.join(dest, rendered_path)
        if not fs.is_subpath(target, dest) then
          errors[#errors + 1] = ("template path escapes project directory: %s"):format(rendered_path)
        else
          local raw_content = raw_files[raw_path]
          local content, content_err, skip = nil, nil, false

          if type(raw_content) == "function" then
            local ok, result = pcall(raw_content, ctx)
            if not ok then
              content_err = "template file function failed: " .. tostring(result)
            elseif result == nil then
              skip = true
            elseif type(result) ~= "string" then
              content_err = "template file function must return a string or nil"
            else
              local rendered_content, missing = M.render_string(result, ctx)
              if #missing > 0 then
                content_err = "unresolved variable(s): " .. table.concat(missing, ", ")
              else
                content = rendered_content
              end
            end
          elseif type(raw_content) == "string" then
            local rendered, missing = M.render_string(raw_content, ctx)
            if #missing > 0 then
              content_err = "unresolved variable(s): " .. table.concat(missing, ", ")
            else
              content = rendered
            end
          else
            content_err = "file content must be a string or function"
          end

          if content_err then
            errors[#errors + 1] = ("%s: %s"):format(rendered_path, content_err)
          elseif not skip then
            operations[#operations + 1] = {
              path = rendered_path,
              target = target,
              content = content,
              exists = fs.exists(target),
            }
          end
        end
      end
    end
  end

  return {
    template = template,
    context = ctx,
    destination = dest,
    operations = operations,
    errors = errors,
  }
end

function M.apply(plan, opts)
  opts = opts or {}
  if not plan or not plan.destination then
    return nil, "invalid plan"
  end
  if plan.errors and #plan.errors > 0 then
    return nil, "template plan has errors: " .. table.concat(plan.errors, "; ")
  end

  local mkdir_ok, mkdir_err = fs.mkdirp(plan.destination)
  if not mkdir_ok then
    return nil, mkdir_err
  end

  local created, skipped = {}, {}
  for _, operation in ipairs(plan.operations) do
    if operation.exists and not opts.overwrite then
      skipped[#skipped + 1] = operation.path
    else
      local ok, err = fs.write(operation.target, operation.content, {
        overwrite = opts.overwrite == true,
        create_dirs = true,
      })
      if not ok then
        return nil, ("could not write %s: %s"):format(operation.path, tostring(err)), {
          created = created,
          skipped = skipped,
        }
      end
      created[#created + 1] = operation.path
    end
  end

  return { created = created, skipped = skipped, destination = plan.destination }
end

function M.preview_lines(plan)
  local lines = {}
  lines[#lines + 1] = "Template: " .. ((plan.template and plan.template.name) or "unknown")
  lines[#lines + 1] = "Destination: " .. tostring(plan.destination)
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("Files (%d):"):format(#plan.operations)
  for _, operation in ipairs(plan.operations) do
    lines[#lines + 1] = ("  %s %s"):format(operation.exists and "=" or "+", operation.path)
  end

  if plan.template and plan.template.commands then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Commands:"
    for _, kind in ipairs({ "build", "test", "run", "clean" }) do
      if plan.template.commands[kind] then
        local argv = M.resolve_command(plan.template.commands[kind], plan.context)
        if argv then
          lines[#lines + 1] = ("  %-8s %s"):format(kind, utils.display_argv(argv))
        end
      end
    end
  end

  if plan.template and plan.template.install_commands then
    local install = plan.template.install_commands
    if type(install) == "function" then
      local ok, result = pcall(install, plan.context)
      if ok then
        install = result
      else
        install = nil
      end
    end
    if type(install) == "table" and #install > 0 then
      lines[#lines + 1] = ""
      lines[#lines + 1] = "After creation (run manually):"
      for _, entry in ipairs(install) do
        local argv = type(entry) == "table" and (entry.argv or entry) or entry
        if type(argv) == "table" then
          lines[#lines + 1] = "  " .. utils.display_argv(argv)
        end
      end
    end
  end

  if plan.errors and #plan.errors > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Errors:"
    for _, err in ipairs(plan.errors) do
      lines[#lines + 1] = "  " .. err
    end
  end

  return lines
end

return M
