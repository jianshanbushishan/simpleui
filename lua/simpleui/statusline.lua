local M = {}

local config = require("simpleui.config")
local api = vim.api
local uv = vim.uv or vim.loop
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local state = {
  lsp_progress = {},
}

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

local function get_attached_lsp_clients(bufnr)
  local ok, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
  if ok then
    return clients
  end

  if vim.lsp.buf_get_clients == nil then
    return {}
  end

  ok, clients = pcall(vim.lsp.buf_get_clients, bufnr)
  if not ok or clients == nil then
    return {}
  end

  local result = {}
  for _, client in pairs(clients) do
    if client ~= nil then
      table.insert(result, client)
    end
  end

  return result
end

local function get_attached_lsp_name(bufnr)
  local clients = get_attached_lsp_clients(bufnr)
  if clients[1] == nil then
    return ""
  end

  return clients[1].name
end

local function escape_statusline(text)
  return (text or ""):gsub("%%", "%%%%")
end

local function truncate_text(text, max_length)
  if text == "" or max_length == nil or max_length < 1 then
    return text
  end

  if vim.fn.strchars(text) <= max_length then
    return text
  end

  return vim.fn.strcharpart(text, 0, math.max(max_length - 3, 1)) .. "..."
end

local function get_progress_percentage(value)
  if type(value.percentage) ~= "number" then
    return nil
  end

  return math.max(0, math.min(100, math.floor(value.percentage + 0.5)))
end

local function get_progress_label(item)
  local value = item.value or {}
  local label = value.title or value.message or "LSP"
  label = vim.trim(label)
  return label ~= "" and label or "LSP"
end

local function build_progress_bar(percentage, width)
  width = math.max(width or 1, 1)
  local filled = math.floor((percentage * width) / 100 + 0.5)
  if percentage > 0 then
    filled = math.max(filled, 1)
  end
  filled = math.min(filled, width)

  return string.format("[%s%s]", string.rep("=", filled), string.rep("-", width - filled))
end

local function format_progress_text(item, progress_settings)
  local label = get_progress_label(item)
  local percentage = get_progress_percentage(item.value or {})
  if percentage == nil then
    return truncate_text(label, progress_settings.max_length)
  end

  local bar = build_progress_bar(percentage, progress_settings.bar_width)
  local suffix = string.format(" %s %d%%", bar, percentage)
  local max_label_length = progress_settings.max_length - vim.fn.strchars(suffix) - 1

  if max_label_length < 1 then
    return truncate_text(label .. suffix, progress_settings.max_length)
  end

  return string.format("%s%s", truncate_text(label, max_label_length), suffix)
end

local function latest_progress_for_client(client_id)
  local entries = state.lsp_progress[client_id]
  if entries == nil then
    return nil
  end

  local latest
  for _, item in pairs(entries) do
    if latest == nil or item.updated_at > latest.updated_at then
      latest = item
    end
  end

  return latest
end

local function get_attached_lsp_progress(bufnr)
  local progress_settings = settings().lsp_progress
  if progress_settings == nil or progress_settings.enabled == false then
    return ""
  end

  local latest
  for _, client in ipairs(get_attached_lsp_clients(bufnr)) do
    local item = latest_progress_for_client(client.id)
    if item ~= nil and (latest == nil or item.updated_at > latest.updated_at) then
      latest = item
    end
  end

  if latest == nil then
    return ""
  end

  return escape_statusline(format_progress_text(latest, progress_settings))
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

  local progress = get_attached_lsp_progress(stbufnr())
  if progress ~= "" then
    return string.format("%%#St_Lsp#   %s ", progress)
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

local function redraw_status()
  vim.cmd("redrawstatus")
end

local function clear_client_progress(client_id)
  if client_id == nil then
    return
  end

  state.lsp_progress[client_id] = nil
end

local function update_lsp_progress(event)
  local data = event.data or {}
  local params = data.params or {}
  local value = params.value
  local client_id = data.client_id
  local token = params.token
  if client_id == nil or token == nil or type(value) ~= "table" then
    return
  end

  local token_key = tostring(token)
  if value.kind == "end" then
    local entries = state.lsp_progress[client_id]
    if entries ~= nil then
      entries[token_key] = nil
      if next(entries) == nil then
        state.lsp_progress[client_id] = nil
      end
    end
    redraw_status()
    return
  end

  state.lsp_progress[client_id] = state.lsp_progress[client_id] or {}
  state.lsp_progress[client_id][token_key] = {
    updated_at = uv and uv.hrtime and uv.hrtime() or 0,
    value = value,
  }
  redraw_status()
end

function M.start()
  local group = api.nvim_create_augroup("SimpleUiStatusline", { clear = true })

  if vim.fn.exists("##LspProgress") == 1 then
    api.nvim_create_autocmd("LspProgress", {
      group = group,
      callback = update_lsp_progress,
    })
  end

  api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(event)
      local client_id = event.data and event.data.client_id or nil
      local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
      if client ~= nil and client.attached_buffers and next(client.attached_buffers) ~= nil then
        return
      end

      clear_client_progress(client_id)
      redraw_status()
    end,
  })
end

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
