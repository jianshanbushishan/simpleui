local utils = require("nvchad.stl.utils")

local separators = utils.separators["default"]

local sep_l = separators["left"]
local sep_r = separators["right"]

local M = {}

function M.mode()
	if not utils.is_activewin() then
		return ""
	end

	local modes = utils.modes

	local m = vim.api.nvim_get_mode().mode

	local current_mode = "%#St_" .. modes[m][2] .. "Mode#  " .. modes[m][1]
	local mode_sep1 = "%#St_" .. modes[m][2] .. "ModeSep#" .. sep_r
	return current_mode .. mode_sep1 .. "%#ST_EmptySpace#" .. sep_r
end

function M.file()
	local x = utils.file()
	local name = " " .. x[2] .. " "
	return "%#St_file# " .. x[1] .. name .. "%#St_file_sep#" .. sep_r
end

function M.git()
	return "%#St_gitIcons#" .. utils.git()
end

function M.lsp_msg()
	return "%#St_LspMsg#" .. utils.lsp_msg()
end

M.diagnostics = utils.diagnostics

function M.lsp()
	return "%#St_Lsp#" .. utils.lsp()
end

function M.cwd()
	local icon = "%#St_cwd_icon#" .. "󰉋 "
	local name = vim.uv.cwd()
	name = "%#St_cwd_text#" .. " " .. (name:match("([^/\\]+)[/\\]*$") or name) .. " "
	return (vim.o.columns > 85 and ("%#St_cwd_sep#" .. sep_l .. icon .. name)) or ""
end

M.cursor = "%#St_pos_sep#" .. sep_l .. "%#St_pos_icon# %#St_pos_text# %l/%v "
M["%="] = "%="

return function()
	return utils.generate("default", M)
end
