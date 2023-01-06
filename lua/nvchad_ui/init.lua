local M = {}

M.setup = function(config)
  M.tabufline = config.tabufline
  M.statusline = config.statusline
  M.cmp = config.cmp
  M.tree_side = config.tree_side

  vim.opt.statusline = "%!v:lua.require('nvchad_ui.statusline."
    .. config.statusline.theme
    .. "').run()"

  -- lazyload tabufline
  require("nvchad_ui.tabufline.lazyload")
end

return M
