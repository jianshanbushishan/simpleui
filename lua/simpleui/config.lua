local M = {}

local defaults = {
  statusline = {
    modules = {
      "mode",
      "file",
      "git",
      "%=",
      "%=",
      "diagnostics",
      "lsp",
      "cwd",
      "cursor",
    },
    min_width = {
      lsp = 100,
      cwd = 85,
    },
    lsp_progress = {
      enabled = true,
      max_length = 40,
      bar_width = 10,
    },
  },
  bufferline = {
    showtabline = 2,
    keymaps = {
      enabled = true,
      silent = true,
      prev = "<left>",
      next = "<right>",
      close = "<del>",
      close_all_but_current = "<s-del>",
    },
  },
  gitstatus = {
    enabled = true,
    refresh_events = { "BufWritePost", "DirChanged" },
    session_load_delay = 100,
  },
}

local state = vim.deepcopy(defaults)

function M.setup(opts)
  state = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return state
end

function M.get()
  return state
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
