local M = {}

local config = require("simpleui.config")
local uv = vim.uv or vim.loop
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local separators = {
  left = "",
  right = "",
}

local sep_l = separators.left
local sep_r = separators.right

local modes = {
  ["n"] = { "NORMAL", "Normal" },
  ["no"] = { "NORMAL (no)", "Normal" },
  ["nov"] = { "NORMAL (nov)", "Normal" },
  ["noV"] = { "NORMAL (noV)", "Normal" },
  ["noCTRL-V"] = { "NORMAL", "Normal" },
  ["niI"] = { "NORMAL i", "Normal" },
  ["niR"] = { "NORMAL r", "Normal" },
  ["niV"] = { "NORMAL v", "Normal" },
  ["nt"] = { "NTERMINAL", "NTerminal" },
  ["ntT"] = { "NTERMINAL (ntT)", "NTerminal" },

  ["v"] = { "VISUAL", "Visual" },
  ["vs"] = { "V-CHAR (Ctrl O)", "Visual" },
  ["V"] = { "V-LINE", "Visual" },
  ["Vs"] = { "V-LINE", "Visual" },
  [""] = { "V-BLOCK", "Visual" },

  ["i"] = { "INSERT", "Insert" },
  ["ic"] = { "INSERT (completion)", "Insert" },
  ["ix"] = { "INSERT completion", "Insert" },

  ["t"] = { "TERMINAL", "Terminal" },

  ["R"] = { "REPLACE", "Replace" },
  ["Rc"] = { "REPLACE (Rc)", "Replace" },
  ["Rx"] = { "REPLACEa (Rx)", "Replace" },
  ["Rv"] = { "V-REPLACE", "Replace" },
  ["Rvc"] = { "V-REPLACE (Rvc)", "Replace" },
  ["Rvx"] = { "V-REPLACE (Rvx)", "Replace" },

  ["s"] = { "SELECT", "Select" },
  ["S"] = { "S-LINE", "Select" },
  [""] = { "S-BLOCK", "Select" },
  ["c"] = { "COMMAND", "Command" },
  ["cv"] = { "COMMAND", "Command" },
  ["ce"] = { "COMMAND", "Command" },
  ["cr"] = { "COMMAND", "Command" },
  ["r"] = { "PROMPT", "Confirm" },
  ["rm"] = { "MORE", "Confirm" },
  ["r?"] = { "CONFIRM", "Confirm" },
  ["x"] = { "CONFIRM", "Confirm" },
  ["!"] = { "SHELL", "Terminal" },
}

local function basename(path)
  return path:match("([^/\\]+)[/\\]*$")
end

local function settings()
  return config.get().statusline
end

local function stwinid()
  return vim.g.statusline_winid or 0
end

local function stbufnr()
  return vim.api.nvim_win_get_buf(stwinid())
end

local function is_activewin()
  return vim.api.nvim_get_current_win() == vim.g.statusline_winid
end

local function get_diagnostic_info(level, format)
  local count = #vim.diagnostic.get(stbufnr(), { severity = level })
  if count < 1 then
    return ""
  end

  return string.format(format, count)
end

local function get_attached_lsp_name(bufnr)
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
  if ok and #clients > 0 then
    return clients[1].name
  end

  if vim.lsp.get_active_clients == nil then
    return ""
  end

  for _, client in ipairs(vim.lsp.get_active_clients()) do
    if client.attached_buffers and client.attached_buffers[bufnr] then
      return client.name
    end
  end

  return ""
end

local function get_git_info(kind, format)
  local status = vim.g.git_status_info
  if status == nil or status[kind] == nil or status[kind] < 1 then
    return ""
  end

  return string.format("%s%d", format, status[kind])
end

function M.diagnostics()
  if not rawget(vim, "lsp") then
    return ""
  end

  local err = get_diagnostic_info(vim.diagnostic.severity.ERROR, "%%#St_lspError# %d ")
  local warn = get_diagnostic_info(vim.diagnostic.severity.WARN, "%%#St_lspWarning# %d ")
  local hints = get_diagnostic_info(vim.diagnostic.severity.HINT, "%%#St_lspHints#󰛩 %d ")
  local info = get_diagnostic_info(vim.diagnostic.severity.INFO, "%%#St_lspInfo#󰋼 %d ")

  return string.format(" %s%s%s%s", err, warn, hints, info)
end

function M.mode()
  if not is_activewin() then
    return ""
  end

  local mode = modes[vim.api.nvim_get_mode().mode] or { "UNKNOWN", "Normal" }
  local current_mode = "%#St_" .. mode[2] .. "Mode#  " .. mode[1]
  local mode_sep = "%#St_" .. mode[2] .. "ModeSep#" .. sep_r
  return current_mode .. mode_sep .. "%#ST_EmptySpace#" .. sep_r
end

local function get_buffer_label(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })

  if buftype ~= "" and buftype ~= "nofile" then
    return buftype
  end

  if string.find(path, "data/scratch/", 1, true) ~= nil then
    return "Scratch"
  end

  return (path == "" and "Empty") or basename(path)
end

local function get_file_icon(name)
  if not has_devicons or name == "Empty" then
    return "󰈚"
  end

  return devicons.get_icon(name) or "󰈚"
end

function M.file()
  local bufnr = stbufnr()
  local name = get_buffer_label(bufnr)
  local icon = get_file_icon(name)

  return string.format("%%#St_file# %s %s %%#St_file_sep#%s", icon, name, sep_r)
end

function M.git()
  local status = vim.g.git_status_info
  if status == nil or status.branch == nil then
    return ""
  end

  local added = get_git_info("added", "  ")
  local modified = get_git_info("modified", "   ")
  local removed = get_git_info("deleted", "  ")

  return string.format("%%#St_gitIcons# %s %s%s%s", status.branch, added, modified, removed)
end

function M.lsp()
  local lsp_prefix = "  LSP ~"
  local lsp_default = "%#St_Lsp#   LSP "
  if vim.o.columns < settings().min_width.lsp or not rawget(vim, "lsp") then
    return lsp_default
  end

  local name = get_attached_lsp_name(stbufnr())
  if name == "" then
    return lsp_default
  end

  return string.format("%%#St_Lsp# %s %s ", lsp_prefix, name)
end

function M.cwd()
  if vim.o.columns < settings().min_width.cwd or uv == nil or uv.cwd == nil then
    return ""
  end

  local name = uv.cwd()
  if name == nil then
    return ""
  end

  name = basename(name) or name
  return string.format("%%#St_cwd_sep#%s%%#St_cwd_icon# 󰉋 %s %s", sep_l, name, sep_l)
end

function M.cursor()
  local current_line = vim.api.nvim_win_get_cursor(stwinid())[1]
  local total_lines = math.max(vim.api.nvim_buf_line_count(stbufnr()), 1)
  local percentage = (current_line * 100.0) / total_lines
  return string.format("%%#St_pos_sep#%s%%#St_pos_icon#  %.1f  %s", sep_l, percentage, sep_l)
end

M["%="] = "%="

local renderers = {
  mode = M.mode,
  file = M.file,
  git = M.git,
  diagnostics = M.diagnostics,
  lsp = M.lsp,
  cwd = M.cwd,
  cursor = M.cursor,
  ["%="] = function()
    return "%="
  end,
}

function M.setup()
  local result = {}

  for _, module in ipairs(settings().modules) do
    local renderer = renderers[module]
    if renderer ~= nil then
      table.insert(result, renderer())
    end
  end

  return table.concat(result)
end

return M
