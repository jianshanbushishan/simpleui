local M = {}

local uv = vim.uv

local timer = nil
local interval_ms = 1000
local git_status_cache = nil
local is_updating = false

local function aysnc_get_git_branch_name()
  local branch_cmd = "git"
  -- Using symbolic-ref. Fails on detached HEAD, but output is usually empty then.
  local branch_args = { "symbolic-ref", "--short", "HEAD" }
  local branch_stdout_pipe = uv.new_pipe(false)
  local branch_stderr_pipe = uv.new_pipe(false)
  if not branch_stdout_pipe or not branch_stderr_pipe then
    vim.notify("Failed to create pipes for git branch", vim.log.levels.ERROR)
    return
  end
  local branch_output = ""
  local branch_handle

  local function on_exit_branch(code, signal)
    if code == 0 and signal == 0 then
      local info = vim.g.git_status_info
      info.branch = vim.trim(branch_output)
      vim.g.git_status_info = info
    else
      vim.g.git_status_info.branch = nil -- Indicate no branch name found / detached HEAD
    end
  end

  branch_handle = uv.spawn(
    branch_cmd,
    { args = branch_args, stdio = { nil, branch_stdout_pipe, branch_stderr_pipe } },
    on_exit_branch
  )
  if not branch_handle then
    vim.notify("Failed to spawn git branch process", vim.log.levels.ERROR)
    if branch_stdout_pipe and not branch_stdout_pipe:is_closing() then
      branch_stdout_pipe:close()
    end
    if branch_stderr_pipe and not branch_stderr_pipe:is_closing() then
      branch_stderr_pipe:close()
    end
  else
    branch_stdout_pipe:read_start(function(err, data)
      if err or not data then
        branch_stdout_pipe:read_stop()
        return
      end
      branch_output = branch_output .. data
    end)
    branch_stderr_pipe:read_start(function(err, data) -- Consume stderr
      if err or not data then
        branch_stderr_pipe:read_stop()
        return
      end
    end)
  end
end

local function async_get_git_status_counts()
  local command = "git"
  local args = { "status", "--porcelain=v1", "--no-renames" }
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false)
  if not stdout_pipe or not stderr_pipe then
    vim.notify("Failed to create pipes for git status", vim.log.levels.ERROR)
    is_updating = false -- 出错时重置标记
    return
  end

  local stdout_chunks = {}
  local stderr_output = ""
  local handle

  local function on_exit_status(code, signal)
    vim.schedule(function()
      if stdout_pipe and not stdout_pipe:is_closing() then
        stdout_pipe:read_stop()
        stdout_pipe:close()
      end
      if stderr_pipe and not stderr_pipe:is_closing() then
        stderr_pipe:read_stop()
        stderr_pipe:close()
      end
      if handle and not handle:is_closing() then
        handle:close()
      end

      -- 整个流程完成，重置标记
      is_updating = false

      if code ~= 0 or signal ~= 0 then
        return
      end

      local output_str = table.concat(stdout_chunks)
      local output_lines = vim.split(output_str, "\n", { trimempty = true })
      local counts = { modified = 0, added = 0, deleted = 0 }
      for _, line in ipairs(output_lines) do
        local result = line:sub(1, 2)
        local index_status = line:sub(1, 1)
        local work_tree_status = line:sub(2, 2)
        if result == "??" or index_status == "A" then
          counts.added = counts.added + 1
        elseif work_tree_status == "M" then
          counts.modified = counts.modified + 1
        elseif work_tree_status == "D" or index_status == "D" then
          counts.deleted = counts.deleted + 1
        end
      end

      vim.g.git_status_info = counts
      aysnc_get_git_branch_name()
    end) -- end vim.schedule
  end

  handle = uv.spawn(command, {
    args = args,
    stdio = { nil, stdout_pipe, stderr_pipe },
  }, on_exit_status)

  if not handle then
    vim.notify("Failed to spawn git status process", vim.log.levels.ERROR)
    is_updating = false -- 出错时重置标记
    if stdout_pipe and not stdout_pipe:is_closing() then
      stdout_pipe:close()
    end
    if stderr_pipe and not stderr_pipe:is_closing() then
      stderr_pipe:close()
    end
    return
  end

  local read_ok_stdout, read_err_stdout = pcall(stdout_pipe.read_start, stdout_pipe, function(err, data)
    if err then
      stdout_pipe:read_stop()
      return
    end
    if data then
      table.insert(stdout_chunks, data)
    else
      stdout_pipe:read_stop()
    end
  end)
  if not read_ok_stdout then
    vim.notify("Failed to start reading stdout for status: " .. tostring(read_err_stdout), vim.log.levels.ERROR)
    handle:kill()
    is_updating = false -- 出错时重置标记
    return
  end

  stderr_pipe:read_start(function(err, data)
    if err then
      stderr_pipe:read_stop()
      return
    end
    if data then
      stderr_output = stderr_output .. data
    else
      stderr_pipe:read_stop()
    end
  end)
end

local function async_check_is_git_repo()
  if is_updating then
    return
  end
  is_updating = true

  local command = "git"
  local args = { "rev-parse", "--is-inside-work-tree" }
  local stdout_pipe = uv.new_pipe(false)
  local stderr_pipe = uv.new_pipe(false) -- 忽略 stderr 输出，但需要管道
  if not stdout_pipe or not stderr_pipe then
    vim.notify("Failed to create pipes for git check", vim.log.levels.ERROR)
    is_updating = false -- 出错时重置标记
    return
  end

  local stdout_output = ""
  local handle

  local function on_exit_check(code, signal)
    vim.schedule(function()
      if stdout_pipe and not stdout_pipe:is_closing() then
        stdout_pipe:read_stop()
        stdout_pipe:close()
      end
      if stderr_pipe and not stderr_pipe:is_closing() then
        stderr_pipe:read_stop()
        stderr_pipe:close()
      end
      if handle and not handle:is_closing() then
        handle:close()
      end

      if code == 0 and signal == 0 and stdout_output:match("^true") then
        async_get_git_status_counts()
      else
        if git_status_cache ~= nil then
          vim.g.git_status_info = nil
          git_status_cache = nil
        end
        is_updating = false
      end
    end)
  end

  handle = uv.spawn(command, {
    args = args,
    stdio = { nil, stdout_pipe, stderr_pipe },
  }, on_exit_check)

  if not handle then
    vim.notify("Failed to spawn git check process", vim.log.levels.ERROR)
    is_updating = false -- 出错时重置标记
    if stdout_pipe and not stdout_pipe:is_closing() then
      stdout_pipe:close()
    end
    if stderr_pipe and not stderr_pipe:is_closing() then
      stderr_pipe:close()
    end
    return
  end

  local read_ok_check, read_err_check = pcall(stdout_pipe.read_start, stdout_pipe, function(err, data)
    if err then
      stdout_pipe:read_stop()
      return
    end
    if data then
      stdout_output = stdout_output .. data -- 收集输出
    else
      stdout_pipe:read_stop()
    end
  end)
  if not read_ok_check then
    vim.notify("Failed to start reading stdout for check: " .. tostring(read_err_check), vim.log.levels.ERROR)
    handle:kill()
    is_updating = false -- 出错时重置标记
    return
  end

  stderr_pipe:read_start(function(err, data)
    if err or not data then
      stderr_pipe:read_stop()
    end
  end)
end

local function trigger_update()
  async_check_is_git_repo()
end

function M.start()
  if timer and not timer:is_closing() then
    timer:stop()
  end

  timer = uv.new_timer()
  if not timer then
    vim.notify("Failed to create uv timer", vim.log.levels.ERROR)
    return
  end

  local start_ok, start_err = pcall(timer.start, timer, 0, interval_ms, vim.schedule_wrap(trigger_update))
  if not start_ok then
    vim.notify("Failed to start uv timer: " .. tostring(start_err), vim.log.levels.ERROR)
    timer:close()
    timer = nil
    return
  end

  trigger_update()
end

function M.stop()
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
    timer = nil
    vim.schedule(function()
      vim.g.git_status_info = nil
      git_status_cache = nil
      is_updating = false -- 确保停止时重置
    end)
  end
end

-- Neovim 退出时自动停止定时器
vim.api.nvim_create_autocmd("VimLeavePre", {
  pattern = "*",
  callback = function()
    M.stop()
  end,
})

-- 初始化全局变量
vim.g.git_status_info = nil

return M
