-- Scaffold.nvim entry point.
--
-- Only user commands are registered here. All work is done lazily so that
-- starting Neovim never pays for loading the dashboard, templates, or tools.

if vim.g.loaded_scaffold then
  return
end
vim.g.loaded_scaffold = 1

require("scaffold.commands").register()
