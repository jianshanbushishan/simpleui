local M = {}

local uv = vim.uv or vim.loop
local state = {
  is_updating = false,
}

local function safe_read_stop(pipe)
  if pipe == nil or pipe:is_closing() then
    return
  end

  pcall(pipe.read_stop, pipe)
end

local function safe_close(handle)
  if handle ~= nil and not handle:is_closing() then
    handle:close()
  end
end

local function spawn_git(args, on_exit)
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false)
  if stdout_pipe == nil or stderr_pipe == nil then
    safe_close(stdout_pipe)
    safe_close(stderr_pipe)
    return false
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local handle

  handle = uv.spawn("git", {
    args = args,
    stdio = { nil, stdout_pipe, stderr_pipe },
  }, function(code, signal)
    vim.schedule(function()
      safe_read_stop(stdout_pipe)
      safe_read_stop(stderr_pipe)
      safe_close(stdout_pipe)
      safe_close(stderr_pipe)
      safe_close(handle)
      on_exit(code, signal, table.concat(stdout_chunks), table.concat(stderr_chunks))
    end)
  end)

  if handle == nil then
    safe_close(stdout_pipe)
    safe_close(stderr_pipe)
    return false
  end

  stdout_pipe:read_start(function(err, data)
    if err ~= nil then
      safe_read_stop(stdout_pipe)
      return
    end
    if data ~= nil then
      table.insert(stdout_chunks, data)
    end
  end)

  stderr_pipe:read_start(function(err, data)
    if err ~= nil then
      safe_read_stop(stderr_pipe)
      return
    end
    if data ~= nil then
      table.insert(stderr_chunks, data)
    end
  end)

  return true
end

local function redraw_status()
  vim.cmd("redrawstatus")
end

local function parse_status_counts(output)
  local counts = { modified = 0, added = 0, deleted = 0 }
  local lines = vim.split(output, "\n", { trimempty = true })

  for _, line in ipairs(lines) do
    local index_status = line:sub(1, 1)
    local worktree_status = line:sub(2, 2)
    local result = line:sub(1, 2)

    if result == "??" or index_status == "A" or worktree_status == "A" then
      counts.added = counts.added + 1
    end
    if index_status == "M" or worktree_status == "M" then
      counts.modified = counts.modified + 1
    end
    if index_status == "D" or worktree_status == "D" then
      counts.deleted = counts.deleted + 1
    end
  end

  return counts
end

local function finish_update(info)
  vim.g.git_status_info = info
  state.is_updating = false
  redraw_status()
end

local function async_get_git_branch_name(counts)
  local ok = spawn_git({ "symbolic-ref", "--short", "HEAD" }, function(code, signal, stdout)
    if code == 0 and signal == 0 then
      counts.branch = vim.trim(stdout)
    end

    finish_update(counts)
  end)

  if not ok then
    finish_update(counts)
  end
end

local function async_get_git_status_counts()
  local ok = spawn_git({ "status", "--porcelain=v1", "--no-renames" }, function(code, signal, stdout)
    if code ~= 0 or signal ~= 0 then
      finish_update(vim.g.git_status_info)
      return
    end

    async_get_git_branch_name(parse_status_counts(stdout))
  end)

  if not ok then
    finish_update(vim.g.git_status_info)
  end
end

local function async_check_is_git_repo()
  if state.is_updating then
    return
  end

  state.is_updating = true
  local ok = spawn_git({ "rev-parse", "--is-inside-work-tree" }, function(code, signal, stdout)
    if code == 0 and signal == 0 and vim.trim(stdout) == "true" then
      async_get_git_status_counts()
      return
    end

    finish_update(nil)
  end)

  if not ok then
    finish_update(vim.g.git_status_info)
  end
end

local function trigger_update()
  async_check_is_git_repo()
end

function M.refresh()
  trigger_update()
end

function M.start(opts)
  local settings = opts or {
    refresh_events = { "BufWritePost", "DirChanged" },
    session_load_delay = 100,
  }
  local group = vim.api.nvim_create_augroup("SimpleUiGitStatus", { clear = true })

  vim.api.nvim_create_autocmd(settings.refresh_events, {
    pattern = "*",
    group = group,
    callback = trigger_update,
  })

  vim.api.nvim_create_autocmd("SessionLoadPost", {
    pattern = "*",
    group = group,
    callback = function()
      local timer = uv.new_timer()
      if timer == nil then
        trigger_update()
        return
      end

      timer:start(settings.session_load_delay, 0, function()
        timer:stop()
        safe_close(timer)
        vim.schedule(trigger_update)
      end)
    end,
  })

  trigger_update()
end

vim.g.git_status_info = nil

return M
