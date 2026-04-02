local M = {}

local config = require("simpleui.config")
local api = vim.api
local uv = vim.uv or vim.loop
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local state = {
  lsp_progress = {},
  sep_cache = {},
}

local separators = {
  left = "",
  right = "",
}

local sep_l = separators.left
local sep_r = separators.right

local modes = {
  -- Normal
  ["n"] = { "NORMAL", "Normal" },
  ["no"] = { "O-PENDING", "Normal" },
  ["nov"] = { "O-PENDING", "Normal" },
  ["noV"] = { "O-PENDING", "Normal" },
  ["noCTRL-V"] = { "O-PENDING", "Normal" },
  ["niI"] = { "NORMAL", "Normal" },
  ["niR"] = { "NORMAL", "Normal" },
  ["niV"] = { "NORMAL", "Normal" },
  -- Visual
  ["v"] = { "VISUAL", "Visual" },
  ["V"] = { "V-LINE", "Visual" },
  [string.char(22)] = { "V-BLOCK", "Visual" },
  ["vs"] = { "VISUAL", "Visual" },
  ["Vs"] = { "V-LINE", "Visual" },
  -- Insert
  ["i"] = { "INSERT", "Insert" },
  ["ic"] = { "INSERT", "Insert" },
  ["ix"] = { "INSERT", "Insert" },
  -- Terminal
  ["t"] = { "TERMINAL", "Terminal" },
  ["nt"] = { "TERMINAL", "Terminal" },
  ["ntT"] = { "TERMINAL", "Terminal" },
  ["!"] = { "SHELL", "Terminal" },
  -- Replace
  ["R"] = { "REPLACE", "Replace" },
  ["Rc"] = { "REPLACE", "Replace" },
  ["Rx"] = { "REPLACE", "Replace" },
  ["Rv"] = { "V-REPLACE", "Replace" },
  ["Rvc"] = { "V-REPLACE", "Replace" },
  ["Rvx"] = { "V-REPLACE", "Replace" },
  -- Select
  ["s"] = { "SELECT", "Select" },
  ["S"] = { "S-LINE", "Select" },
  [string.char(19)] = { "S-BLOCK", "Select" },
  -- Command
  ["c"] = { "COMMAND", "Command" },
  ["cv"] = { "COMMAND", "Command" },
  ["ce"] = { "COMMAND", "Command" },
  ["cr"] = { "COMMAND", "Command" },
  -- Prompt / Confirm
  ["r"] = { "PROMPT", "Confirm" },
  ["rm"] = { "MORE", "Confirm" },
  ["r?"] = { "CONFIRM", "Confirm" },
  ["x"] = { "CONFIRM", "Confirm" },
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
  return api.nvim_win_get_buf(stwinid())
end

local function is_activewin()
  return api.nvim_get_current_win() == vim.g.statusline_winid
end

local function escape_statusline(text)
  return (text or ""):gsub("%%", "%%%%")
end

local function hl_exists(name)
  local ok, spec = pcall(api.nvim_get_hl, 0, { name = name, link = false })
  return ok and spec ~= nil and next(spec) ~= nil
end

local function hl(name, fallback)
  if name ~= nil and hl_exists(name) then
    return "%#" .. name .. "#"
  end

  if fallback ~= nil and hl_exists(fallback) then
    return "%#" .. fallback .. "#"
  end

  return "%#StatusLine#"
end

local function hl_name(name, fallback)
  if name ~= nil and hl_exists(name) then
    return name
  end

  if fallback ~= nil and hl_exists(fallback) then
    return fallback
  end

  return "StatusLine"
end

local function hl_bg(name, fallback)
  local resolved = hl_name(name, fallback)
  local ok, spec = pcall(api.nvim_get_hl, 0, { name = resolved, link = false })
  if not ok or spec == nil then
    return nil
  end

  return spec.bg
end

local function transition_sep(direction, from_group, to_group)
  local from_name = hl_name(from_group)
  local to_name = hl_name(to_group)
  local from_bg = hl_bg(from_name)
  local to_bg = hl_bg(to_name)
  if from_bg == nil or to_bg == nil then
    return hl("StatusLine")
  end

  local cache_key = table.concat({ direction, from_name, to_name }, ":")
  local group = state.sep_cache[cache_key]
  if group == nil then
    group = "SimpleUiSep_" .. direction .. "_" .. from_name .. "_" .. to_name
    if direction == "left" then
      api.nvim_set_hl(0, group, { fg = to_bg, bg = from_bg })
    else
      api.nvim_set_hl(0, group, { fg = from_bg, bg = to_bg })
    end
    state.sep_cache[cache_key] = group
  end

  return "%#" .. group .. "#"
end

local function segment(body_group, text)
  local resolved = hl_name(body_group)
  return {
    group = resolved,
    text = hl(resolved) .. text,
  }
end

local function get_diagnostic_count(level)
  return #vim.diagnostic.get(stbufnr(), { severity = level })
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

local function get_buffer_label(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  local buftype = api.nvim_get_option_value("buftype", { buf = bufnr })

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

local function format_file_size(bytes)
  if bytes == nil or bytes < 1 then
    return ""
  end

  local units = { "", "KB", "MB", "GB", "TB" }
  local i = 1
  local size = bytes
  while size >= 1024 and i < #units do
    size = size / 1024
    i = i + 1
  end

  if i == 1 then
    return string.format("%dB", size)
  end

  return string.format("%.1f%s", size, units[i])
end

local function statusline_bg_hl()
  return hl("StatusLine")
end

function M.diagnostics()
  if not rawget(vim, "lsp") then
    return nil
  end

  local parts = {}
  local err_count = get_diagnostic_count(vim.diagnostic.severity.ERROR)
  if err_count > 0 then
    table.insert(parts, hl("St_lspError") .. " " .. err_count .. " ")
  end

  local warn_count = get_diagnostic_count(vim.diagnostic.severity.WARN)
  if warn_count > 0 then
    table.insert(parts, hl("St_lspWarning") .. " " .. warn_count .. " ")
  end

  local hint_count = get_diagnostic_count(vim.diagnostic.severity.HINT)
  if hint_count > 0 then
    table.insert(parts, hl("St_LspHints", "St_lspHints") .. "󰛩 " .. hint_count .. " ")
  end

  local info_count = get_diagnostic_count(vim.diagnostic.severity.INFO)
  if info_count > 0 then
    table.insert(parts, hl("St_LspInfo", "St_lspInfo") .. "󰋼 " .. info_count .. " ")
  end

  if #parts == 0 then
    return nil
  end

  return segment("St_diagnostics", " " .. table.concat(parts))
end

function M.mode()
  if not is_activewin() then
    return nil
  end

  local mode = modes[api.nvim_get_mode().mode] or { "UNKNOWN", "Normal" }
  return segment("St_" .. mode[2] .. "Mode", "  " .. mode[1] .. " ")
end

function M.file()
  local name = escape_statusline(get_buffer_label(stbufnr()))
  local icon = get_file_icon(name)

  return segment("St_file", " " .. icon .. " " .. name .. " ")
end

function M.filesize()
  local file_size_settings = settings().file_size
  if file_size_settings == nil or file_size_settings.enabled == false then
    return nil
  end

  local path = api.nvim_buf_get_name(stbufnr())
  if path == "" then
    return nil
  end

  local stat = uv and uv.fs_stat(path)
  if stat == nil then
    return nil
  end

  local formatted = format_file_size(stat.size)
  if formatted == "" then
    return nil
  end

  return segment("St_filesize", "  " .. formatted .. " ")
end

function M.git()
  local status = vim.g.git_status_info
  if status == nil or status.branch == nil then
    return nil
  end

  local added = status.added and status.added > 0 and ("  " .. status.added) or ""
  local modified = status.modified and status.modified > 0 and ("  " .. status.modified) or ""
  local removed = status.deleted and status.deleted > 0 and ("  " .. status.deleted) or ""

  return segment("St_git", hl("St_gitIcons")
    .. "  "
    .. hl("St_git")
    .. escape_statusline(status.branch)
    .. added
    .. modified
    .. removed
    .. " ")
end

function M.lsp()
  if not rawget(vim, "lsp") then
    return nil
  end

  local name = get_attached_lsp_name(stbufnr())
  if name == "" then
    return nil
  end

  local lsp_name = escape_statusline(name)
  local label = string.format(" LSP(%s) ", lsp_name)

  if vim.o.columns >= settings().min_width.lsp then
    local progress = get_attached_lsp_progress(stbufnr())
    if progress ~= "" then
      label = "LSP " .. lsp_name .. " " .. progress
    end
  end

  return segment("St_Lsp", "  " .. hl("St_LspMsg") .. label .. " ")
end

function M.cwd()
  if vim.o.columns < settings().min_width.cwd or uv == nil or uv.cwd == nil then
    return nil
  end

  local name = uv.cwd()
  if name == nil then
    return nil
  end

  name = escape_statusline(basename(name) or name)
  return segment("St_cwd_text", hl("St_cwd_icon") .. " 󰉋 " .. hl("St_cwd_text") .. name .. " ")
end

function M.linecol()
  local pos = api.nvim_win_get_cursor(stwinid())
  return segment("St_linecol", string.format(" 󰍉 %d:%d ", pos[1], pos[2] + 1))
end

function M.cursor()
  local current_line = api.nvim_win_get_cursor(stwinid())[1]
  local total_lines = math.max(api.nvim_buf_line_count(stbufnr()), 1)
  local percentage = (current_line * 100.0) / total_lines
  return segment("St_cursor", string.format("  %.1f%%%% ", percentage))
end

local renderers = {
  mode = M.mode,
  file = M.file,
  filesize = M.filesize,
  git = M.git,
  diagnostics = M.diagnostics,
  lsp = M.lsp,
  cwd = M.cwd,
  linecol = M.linecol,
  cursor = M.cursor,
  ["%="] = function()
    return "%="
  end,
}

local function redraw_status()
  vim.cmd("redrawstatus")
end

local function split_regions()
  local regions = { {} }

  for _, module in ipairs(settings().modules) do
    if module == "%=" then
      table.insert(regions, {})
    else
      local renderer = renderers[module]
      if renderer ~= nil then
        local item = renderer()
        if item ~= nil then
          table.insert(regions[#regions], item)
        end
      end
    end
  end

  return regions
end

local function render_left_region(region)
  if #region == 0 then
    return ""
  end

  local chunks = { region[1].text }
  for index = 2, #region do
    table.insert(chunks, transition_sep("right", region[index - 1].group, region[index].group))
    table.insert(chunks, sep_r)
    table.insert(chunks, region[index].text)
  end

  table.insert(chunks, transition_sep("right", region[#region].group, "StatusLine"))
  table.insert(chunks, sep_r)
  return table.concat(chunks)
end

local function render_right_region(region)
  if #region == 0 then
    return ""
  end

  local chunks = {}
  for index, item in ipairs(region) do
    local prev_group = index == 1 and "StatusLine" or region[index - 1].group
    table.insert(chunks, transition_sep("left", prev_group, item.group))
    table.insert(chunks, sep_l)
    table.insert(chunks, item.text)
  end

  return table.concat(chunks)
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

  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      state.sep_cache = {}
      redraw_status()
    end,
  })
end

function M.setup()
  local regions = split_regions()
  local result = { statusline_bg_hl() }

  for index, region in ipairs(regions) do
    if index == 1 then
      table.insert(result, render_left_region(region))
    elseif index == #regions then
      table.insert(result, render_right_region(region))
    elseif #region > 0 then
      table.insert(result, render_left_region(region))
    end

    if index < #regions then
      table.insert(result, "%=")
    end
  end

  return table.concat(result)
end

return M
