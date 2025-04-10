local M = {}

local separators = {
  default = { left = "", right = "" },
}

local sep_l = separators["left"]
local sep_r = separators["right"]

M.modules = {
  "mode",
  "file",
  "git",
  "%=",
  "%=",
  "diagnostics",
  "lsp",
  "cwd",
  "cursor",
}

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

local function stbufnr()
  return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
end

local function is_activewin()
  return vim.api.nvim_get_current_win() == vim.g.statusline_winid
end

local function GetDiagnoosticInfo(level, format)
  local num = #vim.diagnostic.get(stbufnr(), { severity = level })
  if num < 1 then
    return ""
  end

  return string.format(format, num)
end

function M.diagnostics()
  if not rawget(vim, "lsp") then
    return ""
  end

  local err = GetDiagnoosticInfo(vim.diagnostic.severity.ERROR, "%%#St_lspError# %d ")
  local warn = GetDiagnoosticInfo(vim.diagnostic.severity.WARN, "%%#St_lspWarning# %d ")
  local hints = GetDiagnoosticInfo(vim.diagnostic.severity.HINT, "%%#St_lspHints#󰛩 %d ")
  local info = GetDiagnoosticInfo(vim.diagnostic.severity.INFO, "%%#St_lspInfo#󰋼 %d ")

  return string.format(" %s%s%s%s", err, warn, hints, info)
end

function M.mode()
  if not is_activewin() then
    return ""
  end

  local m = vim.api.nvim_get_mode().mode

  local current_mode = "%#St_" .. modes[m][2] .. "Mode#  " .. modes[m][1]
  local mode_sep1 = "%#St_" .. modes[m][2] .. "ModeSep#" .. sep_r
  return current_mode .. mode_sep1 .. "%#ST_EmptySpace#" .. sep_r
end

function M.file()
  local icon = "󰈚"
  local bufnr = stbufnr()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local type = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
  local name = "Empty"
  if type ~= "" and type ~= "nofile" then
    name = type
  else
    local start, _ = string.find(path, "data/scratch/")
    if start ~= nil then
      name = "Scratch"
    else
      name = (path == "" and "Empty") or path:match("([^/\\]+)[/\\]*$")
    end
  end

  if name ~= "Empty" then
    local devicons_present, devicons = pcall(require, "nvim-web-devicons")

    if devicons_present then
      local ft_icon = devicons.get_icon(name)
      icon = (ft_icon ~= nil and ft_icon) or icon
    end
  end

  return string.format("%%#St_file# %s %s %%#St_file_sep#%s", icon, name, sep_r)
end

local function GetGitInfo(type, format)
  local status = vim.g.git_status_info
  if status == nil then
    return ""
  end

  if status[type] == nil then
    return ""
  end

  if status[type] < 1 then
    return ""
  end

  return string.format("%s%d", format, status[type])
end

function M.git()
  if vim.g.git_status_info == nil or vim.g.git_status_info.branch == nil then
    return ""
  end

  local added = GetGitInfo("added", "  ")
  local modified = GetGitInfo("modified", "   ")
  local removed = GetGitInfo("deleted", "  ")
  local branch_name = vim.g.git_status_info.branch

  return string.format("%%#St_gitIcons# %s %s%s%s", branch_name, added, modified, removed)
end

function M.lsp()
  local lspPrefix = "  LSP ~"
  local lspDefault = "%#St_Lsp#   LSP "
  if vim.o.columns < 100 then
    return lspDefault
  end

  local name = ""
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.attached_buffers[stbufnr()] then
      name = client.name
      break
    end
  end

  if name == "" then
    return lspDefault
  end

  return string.format("%%#St_Lsp# %s %s ", lspPrefix, name)
end

function M.cwd()
  if vim.o.columns < 85 then
    return ""
  end

  local name = vim.uv.cwd()
  if name == nil then
    return ""
  end

  name = name:match("([^/\\]+)[/\\]*$") or name
  return string.format("%%#St_cwd_sep#%s%%#St_cwd_icon# 󰉋 %s %s", sep_l, name, sep_l)
end

function M.cursor()
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local total_lines = vim.api.nvim_buf_line_count(0)
  local percentage = (current_line * 100.0) / total_lines
  return string.format("%%#St_pos_sep#%s%%#St_pos_icon#  %.1f  %s", sep_l, percentage, sep_l)
end

M["%="] = "%="

function M.setup()
  local result = {}

  for _, module in ipairs(M.modules) do
    local val = M[module]
    if type(val) == "string" then
      table.insert(result, val)
    else
      table.insert(result, val())
    end
  end

  return table.concat(result)
end

return M
