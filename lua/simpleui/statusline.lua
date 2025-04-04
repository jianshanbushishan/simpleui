local M = {}

local separatorsAll = {
  default = { left = "", right = "" },
  round = { left = "", right = "" },
  block = { left = "█", right = "█" },
  arrow = { left = "", right = "" },
}

local separators = separatorsAll["default"]
local sep_l = separators["left"]
local sep_r = separators["right"]

local orders = {
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
  local path = vim.api.nvim_buf_get_name(stbufnr())
  local name = (path == "" and "Empty") or path:match("([^/\\]+)[/\\]*$")

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
  local lspInfo = ""
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.attached_buffers[stbufnr()] then
      lspInfo = (vim.o.columns > 100 and "   LSP ~ " .. client.name .. " ") or "   LSP "
      break
    end
  end

  return "%#St_Lsp#" .. lspInfo
end

function M.cwd()
  local icon = "%#St_cwd_icon#" .. "󰉋 "
  local name = vim.uv.cwd()
  name = "%#St_cwd_text#" .. " " .. (name:match("([^/\\]+)[/\\]*$") or name) .. " "
  return (vim.o.columns > 85 and ("%#St_cwd_sep#" .. sep_l .. icon .. name)) or ""
end

M.cursor = "%#St_pos_sep#" .. sep_l .. "%#St_pos_icon# %#St_pos_text# %l/%v "
M["%="] = "%="

function M.setup()
  local result = {}

  for _, item in ipairs(orders) do
    local val = M[item]
    if type(val) == "string" then
      table.insert(result, val)
    else
      table.insert(result, val())
    end
  end

  return table.concat(result)
end

return M
