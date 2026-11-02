-- Filesystem helpers built on vim.uv (libuv) and vim.fs.
-- No function in this module ever deletes a project directory.

local M = {}

local uv = vim.uv or vim.loop

function M.exists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  return uv.fs_stat(path) ~= nil
end

function M.lexists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  return uv.fs_lstat(path) ~= nil
end

function M.stat(path)
  return uv.fs_stat(path)
end

function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

function M.is_file(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

function M.is_readable(path)
  local fd, err = uv.fs_open(path, "r", 438)
  if not fd then
    return false, err
  end
  uv.fs_close(fd)
  return true
end

-- Expand "~", environment variables, and relative paths.
function M.expand(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  local expanded = vim.fn.expand(path)
  if not expanded:match("^/") and not expanded:match("^%a:[/\\]") then
    local cwd = uv.cwd() or vim.fn.getcwd()
    expanded = vim.fs.joinpath(cwd, expanded)
  end
  return vim.fs.normalize(expanded)
end

function M.normalize(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  return vim.fs.normalize(path)
end

function M.join(...)
  return vim.fs.joinpath(...)
end

function M.dirname(path)
  return vim.fs.dirname(path)
end

function M.basename(path)
  return vim.fs.basename(path)
end

function M.realpath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return uv.fs_realpath(path)
end

function M.mkdirp(path)
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  if M.is_dir(path) then
    return true
  end
  local ok, result = pcall(vim.fn.mkdir, path, "p")
  if not ok then
    return nil, tostring(result)
  end
  if result ~= 1 and not M.is_dir(path) then
    return nil, "could not create directory: " .. path
  end
  return true
end

function M.read(path)
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  local fd, err = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, tostring(err)
  end
  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil, "could not stat file"
  end
  local data = ""
  if stat.size > 0 then
    local ok, chunk = pcall(uv.fs_read, fd, stat.size, 0)
    if ok and chunk then
      data = chunk
    else
      uv.fs_close(fd)
      return nil, "could not read file"
    end
  end
  uv.fs_close(fd)
  return data
end

-- Write a file. Refuses to overwrite unless opts.overwrite is true.
function M.write(path, data, opts)
  opts = opts or {}
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  if type(data) ~= "string" then
    return nil, "file content must be a string"
  end
  if not opts.overwrite and M.exists(path) then
    return nil, "refusing to overwrite existing file: " .. path
  end

  local parent = M.dirname(path)
  if parent and not M.is_dir(parent) then
    if opts.create_dirs == false then
      return nil, "parent directory does not exist: " .. parent
    end
    local ok, err = M.mkdirp(parent)
    if not ok then
      return nil, err
    end
  end

  local fd, err = uv.fs_open(path, "w", 420)
  if not fd then
    return nil, tostring(err)
  end
  local ok, write_err = pcall(uv.fs_write, fd, data, 0)
  uv.fs_close(fd)
  if not ok then
    return nil, tostring(write_err)
  end
  return true
end

-- Write via a temporary file in the same directory, fsync, then rename.
-- The rename is atomic on POSIX filesystems.
function M.atomic_write(path, data)
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  if type(data) ~= "string" then
    return nil, "file content must be a string"
  end

  local parent = M.dirname(path)
  if parent and not M.is_dir(parent) then
    local ok, err = M.mkdirp(parent)
    if not ok then
      return nil, err
    end
  end

  local tmp = string.format("%s.tmp-%d-%d", path, uv.os_getpid(), math.random(100000, 999999))
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then
    return nil, tostring(err)
  end
  local ok, write_err = pcall(uv.fs_write, fd, data, 0)
  if ok then
    pcall(uv.fs_fsync, fd)
  end
  uv.fs_close(fd)
  if not ok then
    pcall(uv.fs_unlink, tmp)
    return nil, tostring(write_err)
  end

  local renamed, rename_err = uv.fs_rename(tmp, path)
  if not renamed then
    pcall(uv.fs_unlink, tmp)
    return nil, tostring(rename_err)
  end
  return true
end

function M.list(dir)
  local names = {}
  if not M.is_dir(dir) then
    return names
  end
  local handle = uv.fs_scandir(dir)
  while handle do
    local name = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function M.list_details(dir)
  local entries = {}
  if not M.is_dir(dir) then
    return entries
  end
  local handle = uv.fs_scandir(dir)
  while handle do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    entries[#entries + 1] = { name = name, type = kind }
  end
  table.sort(entries, function(a, b)
    return a.name < b.name
  end)
  return entries
end

function M.is_empty_dir(path)
  if not M.is_dir(path) then
    return false
  end
  return #M.list(path) == 0
end

function M.same_path(left, right)
  if type(left) ~= "string" or type(right) ~= "string" then
    return false
  end
  local lreal = M.realpath(left)
  local rreal = M.realpath(right)
  if lreal and rreal then
    return lreal == rreal
  end
  return M.normalize(M.expand(left)) == M.normalize(M.expand(right))
end

-- True when `child` is `parent` or lives underneath it.
function M.is_subpath(child, parent)
  if type(child) ~= "string" or type(parent) ~= "string" then
    return false
  end
  local normalized_child = M.normalize(M.expand(child))
  local normalized_parent = M.normalize(M.expand(parent))
  if normalized_child == normalized_parent then
    return true
  end
  if normalized_parent == "/" then
    return normalized_child:sub(1, 1) == "/"
  end
  return normalized_child:sub(1, #normalized_parent + 1) == normalized_parent .. "/"
end

-- Remove a single file. Only used for Scaffold-owned temporary files and
-- corrupt registry backups. Directories and project paths are refused.
function M.remove_file(path)
  if type(path) ~= "string" or path == "" then
    return nil, "invalid path"
  end
  if M.is_dir(path) then
    return nil, "refusing to remove directory: " .. path
  end
  local ok, err = uv.fs_unlink(path)
  if not ok then
    return nil, tostring(err)
  end
  return true
end

function M.copy_file(source, destination, opts)
  opts = opts or {}
  if not M.is_file(source) then
    return nil, "source file does not exist: " .. source
  end
  if not opts.overwrite and M.exists(destination) then
    return nil, "refusing to overwrite existing file: " .. destination
  end
  local data, err = M.read(source)
  if not data then
    return nil, err
  end
  return M.write(destination, data, { overwrite = true })
end

return M
