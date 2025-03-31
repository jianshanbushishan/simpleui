local M = {}

function M.setup()
	local theme = "default"
	vim.o.statusline = "%!v:lua.require('nvchad.stl." .. theme .. "')()"
	require("nvchad.stl.utils").autocmds()
	-- require "nvchad.tabufline.lazyload"
end

return M
