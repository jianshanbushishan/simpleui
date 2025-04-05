local M = {}

function M.setup()
  local modules = require("simpleui.statusline").modules
  if vim.tbl_contains(modules, "git") then
    local git_updater = require("simpleui.gitstatus")
    git_updater.start()
  end

  vim.opt.statusline = "%!v:lua.require('simpleui.statusline').setup()"
  vim.opt.tabline = "%!v:lua.require('simpleui.bufferline').setup()"
  vim.opt.showtabline = 2

  vim.keymap.set("n", "<left>", function()
    require("simpleui.bufferline").prev()
  end)
  vim.keymap.set("n", "<right>", function()
    require("simpleui.bufferline").next()
  end)
  vim.keymap.set("n", "<del>", function()
    require("simpleui.bufferline").close_buffer()
  end)
  vim.keymap.set("n", "<s-del>", function()
    require("simpleui.bufferline").closeAllBufs(false)
  end)
end

return M
