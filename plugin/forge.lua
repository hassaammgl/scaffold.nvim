-- Forge.nvim entry point.
--
-- Only user commands are registered here. All work is done lazily so that
-- starting Neovim never pays for loading the dashboard, templates, or tools.

if vim.g.loaded_forge then
  return
end
vim.g.loaded_forge = 1

require("forge.commands").register()
