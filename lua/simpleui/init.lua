local M = {}

function M.setup()
  vim.o.statusline = "%!v:lua.require('simpleui.stl.default').setup()"
  -- require("simpleui.stl.utils").autocmds()
  -- require "tabufline.lazyload"
end

return M
