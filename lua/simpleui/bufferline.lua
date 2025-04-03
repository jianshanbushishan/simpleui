local M = {}

local cur_buf = vim.api.nvim_get_current_buf
local set_buf = vim.api.nvim_set_current_buf
local buf_name = vim.api.nvim_buf_get_name
local get_hl = vim.api.nvim_get_hl
local get_opt = vim.api.nvim_get_option_value
local autocmd = vim.api.nvim_create_autocmd

vim.t.bufs = vim.t.bufs
  or vim.tbl_filter(function(buf)
    return vim.fn.buflisted(buf) == 1
  end, vim.api.nvim_list_bufs())

autocmd({ "BufAdd", "BufEnter" }, {
  callback = function(args)
    local bufs = vim.t.bufs
    local is_curbuf = cur_buf() == args.buf

    if bufs == nil then
      bufs = cur_buf() == args.buf and {} or { args.buf }
    else
      -- check for duplicates
      if
        not vim.tbl_contains(bufs, args.buf)
        and (args.event == "BufEnter" or not is_curbuf or get_opt("buflisted", { buf = args.buf }))
        and vim.api.nvim_buf_is_valid(args.buf)
        and get_opt("buflisted", { buf = args.buf })
      then
        table.insert(bufs, args.buf)
      end
    end

    -- remove unnamed buffer which isnt current buf & modified
    if args.event == "BufAdd" then
      if #vim.api.nvim_buf_get_name(bufs[1]) == 0 and not get_opt("modified", { buf = bufs[1] }) then
        table.remove(bufs, 1)
      end
    end

    vim.t.bufs = bufs
  end,
})

autocmd("BufDelete", {
  callback = function(args)
    local bufs = vim.t.bufs
    if bufs == nil then
      return
    end
    for i, bufnr in ipairs(bufs) do
      if bufnr == args.buf then
        table.remove(bufs, i)
        vim.t.bufs = bufs
        break
      end
    end
  end,
})

local function filename(str)
  return str:match("([^/\\]+)[/\\]*$")
end

local function new_hl(group1, group2)
  local fg = get_hl(0, { name = group1 }).fg
  local bg = get_hl(0, { name = "Tb" .. group2 }).bg
  vim.api.nvim_set_hl(0, group1 .. group2, { fg = fg, bg = bg })
  return "%#" .. group1 .. group2 .. "#"
end

function M.highlight_txt(str, hl)
  str = str or ""
  local a = "%#Tb" .. hl .. "#" .. str
  return a
end

function M.format_buf(buf_nr, idx)
  local len = 0
  local icon = "󰈚"
  local is_curbuf = cur_buf() == buf_nr
  local tbHlName = ""
  local icon_hl = new_hl("DevIconDefault", tbHlName)
  local status = ""
  local status_hl = ""
  local sep = ""
  local sep_hl = ""

  if is_curbuf then
    sep = "▌"
    status_hl = "BufOnModified"
    tbHlName = "BufOn"
    sep_hl = "BufSepOn"
  else
    sep = "|"
    status_hl = "BufOffModified"
    tbHlName = "BufOff"
    sep_hl = "BufSepOff"
  end

  local name = filename(buf_name(buf_nr))
  name = name or "No Name"

  if name ~= "No Name" then
    local devicon, devicon_hl = require("nvim-web-devicons").get_icon(name)

    if devicon then
      icon = devicon
      icon_hl = new_hl(devicon_hl, tbHlName)
    end
  end

  len = len + #sep
  sep = M.highlight_txt(sep, sep_hl)
  name = string.format(" %d. %s", idx, name)
  len = len + #name
  name = M.highlight_txt(name, tbHlName)
  local mod = get_opt("mod", { buf = buf_nr })
  if mod then
    status = M.highlight_txt(" ", status_hl)
    len = len + 2
  end

  local str = string.format("%s%s %s%s%s ", sep, name, status, icon_hl, icon)
  return len + 4, str
end

local function buf_index(bufnr)
  for i, value in ipairs(vim.t.bufs) do
    if value == bufnr then
      return i
    end
  end
end

function M.next()
  local bufs = vim.t.bufs
  local curbufIndex = buf_index(cur_buf())

  if not curbufIndex then
    set_buf(vim.t.bufs[1])
    return
  end

  set_buf((curbufIndex == #bufs and bufs[1]) or bufs[curbufIndex + 1])
end

function M.prev()
  local bufs = vim.t.bufs
  local curbufIndex = buf_index(cur_buf())

  if not curbufIndex then
    set_buf(vim.t.bufs[1])
    return
  end

  set_buf((curbufIndex == 1 and bufs[#bufs]) or bufs[curbufIndex - 1])
end

function M.close_buffer(bufnr)
  bufnr = bufnr or cur_buf()

  if vim.bo[bufnr].buftype == "terminal" then
    vim.cmd(vim.bo.buflisted and "set nobl | enew" or "hide")
  else
    local curBufIndex = buf_index(bufnr)
    local bufhidden = vim.bo.bufhidden

    -- force close floating wins or nonbuflisted
    if vim.api.nvim_win_get_config(0).zindex then
      vim.cmd("bw")
      return

      -- handle listed bufs
    elseif curBufIndex and #vim.t.bufs > 1 then
      local newBufIndex = curBufIndex == #vim.t.bufs and -1 or 1
      vim.cmd("b" .. vim.t.bufs[curBufIndex + newBufIndex])

      -- handle unlisted
    elseif not vim.bo.buflisted then
      local tmpbufnr = vim.t.bufs[1]
      vim.api.nvim_set_current_win(vim.fn.bufwinid(bufnr))
      vim.api.nvim_set_current_buf(tmpbufnr)
      vim.cmd("bw" .. bufnr)
      return
    else
      vim.cmd("enew")
    end

    if not (bufhidden == "delete") then
      vim.cmd("confirm bd" .. bufnr)
    end
  end

  vim.cmd("redrawtabline")
end

function M.close_all_bufs(include_cur_buf)
  local bufs = vim.t.bufs

  if include_cur_buf ~= nil and not include_cur_buf then
    table.remove(bufs, buf_index(cur_buf()))
  end

  for _, buf in ipairs(bufs) do
    M.close_buffer(buf)
  end
end

local function get_len(tbl)
  local sum = 0
  for _, val in ipairs(tbl) do
    sum = sum + val
  end
  return sum
end

function M.setup()
  local buffers = {}
  local lens = {}
  local has_current = false

  vim.t.bufs = vim.tbl_filter(vim.api.nvim_buf_is_valid, vim.t.bufs)
  vim.t.bufs = vim.tbl_filter(function(bufnr)
    return get_opt("buftype", { buf = bufnr }) == ""
  end, vim.t.bufs)

  for idx, nr in ipairs(vim.t.bufs) do
    if get_len(lens) > vim.o.columns then
      if has_current then
        break
      end

      table.remove(buffers, 1)
    end

    has_current = cur_buf() == nr or has_current
    local len, str = M.format_buf(nr, idx)
    table.insert(buffers, str)
    table.insert(lens, len)
  end

  return table.concat(buffers) .. M.highlight_txt("%=", "Fill")
end

return M
