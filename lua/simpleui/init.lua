local M = {}

local function setup_keymaps(bufferline, keymaps)
  if not keymaps.enabled then
    return
  end

  local map = vim.keymap.set
  local opts = { silent = keymaps.silent }

  if keymaps.prev then
    map("n", keymaps.prev, bufferline.prev, vim.tbl_extend("force", opts, { desc = "SimpleUI previous buffer" }))
  end
  if keymaps.next then
    map("n", keymaps.next, bufferline.next, vim.tbl_extend("force", opts, { desc = "SimpleUI next buffer" }))
  end
  if keymaps.close then
    map("n", keymaps.close, bufferline.close_buffer, vim.tbl_extend("force", opts, { desc = "SimpleUI close buffer" }))
  end
  if keymaps.close_all_but_current then
    map("n", keymaps.close_all_but_current, function()
      bufferline.close_all_bufs(false)
    end, vim.tbl_extend("force", opts, { desc = "SimpleUI close other buffers" }))
  end
end

function M.setup(opts)
  local config = require("simpleui.config")
  local settings = config.setup(opts)
  local bufferline = require("simpleui.bufferline")
  local statusline = require("simpleui.statusline")

  vim.opt.statusline = "%!v:lua.require('simpleui.statusline').setup()"
  vim.opt.tabline = "%!v:lua.require('simpleui.bufferline').setup()"
  vim.opt.showtabline = settings.bufferline.showtabline

  statusline.start()
  bufferline.start()
  setup_keymaps(bufferline, settings.bufferline.keymaps)

  if settings.gitstatus.enabled and vim.tbl_contains(settings.statusline.modules, "git") then
    require("simpleui.gitstatus").start(settings.gitstatus)
  end
end

return M
