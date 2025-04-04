local M = {}

local uv = vim.uv

local timer = nil
local interval_ms = 500 -- 更新频率
local git_status_cache = nil
local is_updating = false -- 防止并发更新

-- 异步获取 Git 状态 (现在假设我们已经在 Git 仓库中)
local function async_get_git_status_counts()
  -- 注意：is_updating 应该在调用此函数前已经被设为 true

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
        -- print("Git status command failed. Code:", code, "Signal:", signal, "Stderr:", stderr_output)
        -- Git status 失败不一定意味着要清除状态，可能只是临时错误
        -- 但如果希望失败时清除，可以取消下面这行的注释
        -- if git_status_cache ~= nil then vim.g.git_status_counts = nil; git_status_cache = nil end
        return
      end

      local output_str = table.concat(stdout_chunks)
      local output_lines = vim.split(output_str, "\n", { trimempty = true })
      local counts = { modified = 0, added = 0, deleted = 0 }
      for _, line in ipairs(output_lines) do
        local code = line:sub(1, 2)
        local index_status = line:sub(1, 1)
        local work_tree_status = line:sub(2, 2)
        if code == "??" or index_status == "A" then
          counts.added = counts.added + 1
        elseif work_tree_status == "M" then
          counts.modified = counts.modified + 1
        elseif work_tree_status == "D" or index_status == "D" then
          counts.deleted = counts.deleted + 1
        end
      end

      if not vim.deep_equal(counts, git_status_cache) then
        git_status_cache = counts
        vim.g.git_status_counts = counts
      end
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

-- 异步检查是否在 Git 仓库中
local function async_check_is_git_repo()
  if is_updating then
    return
  end -- 防止并发
  is_updating = true -- 在检查开始时就标记

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
      -- 无论结果如何，先关闭检查进程的管道和句柄
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

      -- 检查结果
      if code == 0 and signal == 0 and stdout_output:match("^true") then
        -- 是 Git 仓库，则启动异步 Git Status
        -- 注意：is_updating 标志保持为 true，传递给下一个异步函数
        async_get_git_status_counts()
      else
        -- 不是 Git 仓库，或者检查命令失败
        -- 清理状态并重置 is_updating 标志
        if git_status_cache ~= nil then
          vim.g.git_status_counts = nil
          git_status_cache = nil
        end
        is_updating = false -- 在这里重置标记
      end
    end) -- end vim.schedule
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

  -- 开始读取 stdout
  local read_ok_check, read_err_check = pcall(stdout_pipe.read_start, stdout_pipe, function(err, data)
    if err then
      -- print("Error reading stdout (check):", err)
      stdout_pipe:read_stop()
      return
    end
    if data then
      stdout_output = stdout_output .. data -- 收集输出
    else
      -- EOF
      stdout_pipe:read_stop()
    end
  end)
  if not read_ok_check then
    vim.notify("Failed to start reading stdout for check: " .. tostring(read_err_check), vim.log.levels.ERROR)
    handle:kill()
    is_updating = false -- 出错时重置标记
    return
  end

  -- 不需要显式读取 stderr，但需要启动读取以消耗数据并允许管道关闭
  stderr_pipe:read_start(function(err, data)
    if err or not data then
      stderr_pipe:read_stop()
    end
  end)
end

-- 定时器回调函数 (现在触发异步检查)
local function trigger_update()
  -- 检查和更新逻辑现在完全在 async_check_is_git_repo 开始
  async_check_is_git_repo()
end

-- 启动定时器 (使用 vim.uv)
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
  -- 初始调用
  trigger_update()
  -- print("Fully async Git status updater (vim.uv) started.")
end

-- 停止定时器 (使用 vim.uv)
function M.stop()
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
    timer = nil
    vim.schedule(function()
      vim.g.git_status_counts = nil
      git_status_cache = nil
      is_updating = false -- 确保停止时重置
    end)
    -- print("Fully async Git status updater (vim.uv) stopped.")
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
vim.g.git_status_counts = nil

return M
