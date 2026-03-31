local M = {}

local api = vim.api
local fn = vim.fn
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local cur_buf = api.nvim_get_current_buf
local set_buf = api.nvim_set_current_buf
local buf_name = api.nvim_buf_get_name
local get_hl = api.nvim_get_hl
local get_opt = api.nvim_get_option_value
local autocmd = api.nvim_create_autocmd
local set_hl = api.nvim_set_hl

local highlight_cache = {}

local function is_listed_buffer(bufnr)
  return api.nvim_buf_is_valid(bufnr) and get_opt("buflisted", { buf = bufnr })
end

local function visible_buffers()
  return vim.tbl_filter(is_listed_buffer, api.nvim_list_bufs())
end

local function sync_buffers()
  vim.t.bufs = vim.tbl_filter(is_listed_buffer, vim.t.bufs or visible_buffers())
  return vim.t.bufs
end

local function filename(path)
  return path:match("([^/\\]+)[/\\]*$")
end

local function ensure_highlight(group1, group2, is_curbuf)
  local hl_name = group1 .. group2
  local cache_key = table.concat({ hl_name, tostring(is_curbuf) }, ":")
  if highlight_cache[cache_key] then
    return string.format("%%#%s#", hl_name)
  end

  local ok_base, base_hl = pcall(get_hl, 0, { name = "Tb" .. group2 })
  if not ok_base then
    return ""
  end

  local ok_group, group_hl = pcall(get_hl, 0, { name = group1 })
  local fg = ok_group and group_hl.fg or base_hl.fg
  set_hl(0, hl_name, { fg = is_curbuf and fg or base_hl.fg, bg = base_hl.bg })
  highlight_cache[cache_key] = true
  return string.format("%%#%s#", hl_name)
end

local function reset_highlights()
  highlight_cache = {}
end

local function remove_initial_empty_buffer(bufs)
  if bufs[1] == nil then
    return
  end

  if #buf_name(bufs[1]) == 0 and not get_opt("modified", { buf = bufs[1] }) then
    table.remove(bufs, 1)
  end
end

local function track_buffer(args)
  local bufs = vim.t.bufs
  local is_curbuf = cur_buf() == args.buf

  if bufs == nil then
    bufs = cur_buf() == args.buf and {} or { args.buf }
  elseif
    not vim.tbl_contains(bufs, args.buf)
    and (args.event == "BufEnter" or not is_curbuf or is_listed_buffer(args.buf))
    and is_listed_buffer(args.buf)
  then
    table.insert(bufs, args.buf)
  end

  if args.event == "BufAdd" then
    remove_initial_empty_buffer(bufs)
  end

  vim.t.bufs = bufs
end

local function untrack_buffer(args)
  local bufs = vim.t.bufs
  if bufs == nil then
    return
  end

  for index, bufnr in ipairs(bufs) do
    if bufnr == args.buf then
      table.remove(bufs, index)
      vim.t.bufs = bufs
      break
    end
  end
end

local function get_buffer_style(bufnr)
  local is_current = cur_buf() == bufnr
  return {
    is_current = is_current,
    separator = is_current and "▌" or "|",
    line_highlight = is_current and "BufOn" or "BufOff",
    separator_highlight = is_current and "BufSepOn" or "BufSepOff",
    modified_highlight = is_current and "BufOnModified" or "BufOffModified",
  }
end

local function get_buffer_icon(name, line_highlight, is_current)
  local icon = "󰈚"
  local icon_highlight = ensure_highlight("DevIconDefault", line_highlight, is_current)

  if has_devicons and name ~= "No Name" then
    local devicon, devicon_hl = devicons.get_icon(name)
    if devicon then
      icon = devicon
      icon_highlight = ensure_highlight(devicon_hl, line_highlight, is_current)
    end
  end

  return icon, icon_highlight
end

function M.highlight_txt(str, hl)
  return "%#Tb" .. hl .. "#" .. (str or "")
end

function M.format_buf(bufnr, idx)
  local style = get_buffer_style(bufnr)
  local name = filename(buf_name(bufnr)) or "No Name"
  local icon, icon_hl = get_buffer_icon(name, style.line_highlight, style.is_current)
  local label = string.format(" %d. %s", idx, name)
  local modified = get_opt("modified", { buf = bufnr })
  local status = modified and M.highlight_txt(" ", style.modified_highlight) or ""
  local text = string.format(
    "%%%d@v:lua.__simpleui_bufferline_click@%s%s %s%s%s %%T",
    bufnr,
    M.highlight_txt(style.separator, style.separator_highlight),
    M.highlight_txt(label, style.line_highlight),
    status,
    icon_hl,
    icon
  )
  local width = fn.strdisplaywidth(style.separator .. label .. (modified and "  " or " ") .. icon .. " ")

  return width, text
end

function M.click_handler(bufnr, _, button)
  if button ~= "l" and button ~= "m" and button ~= "r" then
    return
  end

  if api.nvim_buf_is_valid(bufnr) and is_listed_buffer(bufnr) then
    set_buf(bufnr)
  end
end

local function buf_index(bufnr)
  for i, value in ipairs(vim.t.bufs or {}) do
    if value == bufnr then
      return i
    end
  end
end

function M.next()
  local bufs = sync_buffers()
  if #bufs == 0 then
    return
  end

  local curbuf_index = buf_index(cur_buf())
  if not curbuf_index then
    set_buf(bufs[1])
    return
  end

  set_buf((curbuf_index == #bufs and bufs[1]) or bufs[curbuf_index + 1])
end

function M.prev()
  local bufs = sync_buffers()
  if #bufs == 0 then
    return
  end

  local curbuf_index = buf_index(cur_buf())
  if not curbuf_index then
    set_buf(bufs[1])
    return
  end

  set_buf((curbuf_index == 1 and bufs[#bufs]) or bufs[curbuf_index - 1])
end

function M.close_buffer(bufnr)
  bufnr = bufnr or cur_buf()

  if vim.bo[bufnr].buftype == "terminal" then
    vim.cmd(vim.bo[bufnr].buflisted and "set nobl | enew" or "hide")
  else
    local curbuf_index = buf_index(bufnr)
    local bufhidden = vim.bo[bufnr].bufhidden

    if api.nvim_win_get_config(0).zindex then
      vim.cmd("bw")
      return
    elseif curbuf_index and #(vim.t.bufs or {}) > 1 then
      local new_index = curbuf_index == #vim.t.bufs and -1 or 1
      vim.cmd("b" .. vim.t.bufs[curbuf_index + new_index])
    elseif not vim.bo[bufnr].buflisted then
      local tmpbufnr = (vim.t.bufs or {})[1]
      if tmpbufnr ~= nil then
        api.nvim_set_current_win(fn.bufwinid(bufnr))
        api.nvim_set_current_buf(tmpbufnr)
      end
      vim.cmd("bw" .. bufnr)
      return
    else
      vim.cmd("enew")
    end

    if bufhidden ~= "delete" then
      vim.cmd("confirm bd" .. bufnr)
    end
  end

  vim.cmd("redrawtabline")
end

function M.close_all_bufs(include_cur_buf)
  local bufs = vim.deepcopy(sync_buffers())

  if include_cur_buf == false then
    local current_index = buf_index(cur_buf())
    if current_index then
      table.remove(bufs, current_index)
    end
  end

  for _, bufnr in ipairs(bufs) do
    if api.nvim_buf_is_valid(bufnr) then
      M.close_buffer(bufnr)
    end
  end
end

M.closeAllBufs = M.close_all_bufs

function M.start()
  vim.t.bufs = vim.t.bufs or visible_buffers()
  _G.__simpleui_bufferline_click = M.click_handler

  local group = api.nvim_create_augroup("SimpleUiBufferline", { clear = true })
  autocmd({ "BufAdd", "BufEnter" }, {
    group = group,
    callback = track_buffer,
  })
  autocmd("BufDelete", {
    group = group,
    callback = untrack_buffer,
  })
  autocmd("ColorScheme", {
    group = group,
    callback = reset_highlights,
  })
end

local function listed_normal_buffers()
  return vim.tbl_filter(function(bufnr)
    return get_opt("buftype", { buf = bufnr }) == ""
  end, sync_buffers())
end

function M.setup()
  local buffers = {}
  local lengths = {}
  local total_len = 0
  local has_current = false

  vim.t.bufs = listed_normal_buffers()

  for idx, bufnr in ipairs(vim.t.bufs) do
    local len, str = M.format_buf(bufnr, idx)
    table.insert(buffers, str)
    table.insert(lengths, len)
    total_len = total_len + len
    has_current = cur_buf() == bufnr or has_current

    while total_len > vim.o.columns and #buffers > 0 do
      if has_current then
        break
      end

      total_len = total_len - table.remove(lengths, 1)
      table.remove(buffers, 1)
    end
  end

  return table.concat(buffers) .. M.highlight_txt("%=", "Fill")
end

return M
