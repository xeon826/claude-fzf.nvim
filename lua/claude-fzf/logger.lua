local M = {}

-- 日志级别
M.levels = {
  TRACE = 0,
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

-- 日志级别名称
M.level_names = {
  [0] = "TRACE",
  [1] = "DEBUG", 
  [2] = "INFO",
  [3] = "WARN",
  [4] = "ERROR",
}

-- 默认配置
M._config = {
  level = M.levels.INFO,
  file_logging = false,
  console_logging = true,
  log_file = vim.fn.stdpath("log") .. "/claude-fzf.log",
  max_file_size = 1024 * 1024, -- 1MB
  show_caller = true,
  timestamp = true,
}

function M.setup(opts)
  M._config = vim.tbl_deep_extend('force', M._config, opts or {})
  
  -- 确保日志目录存在
  if M._config.file_logging then
    local log_dir = vim.fn.fnamemodify(M._config.log_file, ':h')
    vim.fn.mkdir(log_dir, 'p')
  end
end

function M.get_caller_info()
  if not M._config.show_caller then
    return ""
  end
  
  local info = debug.getinfo(4, "Sl")
  if info then
    local file = vim.fn.fnamemodify(info.source:sub(2), ':t')
    return string.format("[%s:%d] ", file, info.currentline or 0)
  end
  return ""
end

function M.format_message(level, msg, ...)
  local timestamp = ""
  if M._config.timestamp then
    timestamp = os.date("[%Y-%m-%d %H:%M:%S] ")
  end
  
  local caller = M.get_caller_info()
  local level_name = M.level_names[level] or "UNKNOWN"
  local formatted_msg = string.format(msg, ...)
  
  return string.format("%s[claude-fzf] [%s] %s%s", 
    timestamp, level_name, caller, formatted_msg)
end

function M.should_log(level)
  return level >= M._config.level
end

function M.log_to_file(message)
  if not M._config.file_logging then
    return
  end
  
  -- 检查文件大小，如果太大则轮转
  local stat = vim.loop.fs_stat(M._config.log_file)
  if stat and stat.size > M._config.max_file_size then
    local backup_file = M._config.log_file .. ".old"
    vim.loop.fs_rename(M._config.log_file, backup_file)
  end
  
  local file = io.open(M._config.log_file, "a")
  if file then
    file:write(message .. "\n")
    file:close()
  end
end

function M.log_to_console(level, message)
  if not M._config.console_logging then
    return
  end
  
  local vim_level
  if level >= M.levels.ERROR then
    vim_level = vim.log.levels.ERROR
  elseif level >= M.levels.WARN then
    vim_level = vim.log.levels.WARN
  else
    vim_level = vim.log.levels.INFO
  end
  
  vim.notify(message, vim_level)
end

function M.write_log(level, msg, ...)
  if not M.should_log(level) then
    return
  end
  
  local message = M.format_message(level, msg, ...)
  
  M.log_to_file(message)
  M.log_to_console(level, message)
end

-- 便捷的日志函数
function M.trace(msg, ...)
  M.write_log(M.levels.TRACE, msg, ...)
end

function M.debug(msg, ...)
  M.write_log(M.levels.DEBUG, msg, ...)
end

function M.info(msg, ...)
  M.write_log(M.levels.INFO, msg, ...)
end

function M.warn(msg, ...)
  M.write_log(M.levels.WARN, msg, ...)
end

function M.error(msg, ...)
  M.write_log(M.levels.ERROR, msg, ...)
end

-- 包装函数调用以捕获错误
function M.safe_call(func, context, ...)
  local ok, result = pcall(func, ...)
  if not ok then
    M.error("Error in %s: %s", context, result)
    return false, result
  end
  M.debug("Successfully executed %s", context)
  return true, result
end

-- 性能计时
function M.time_call(func, context, ...)
  local start_time = vim.loop.hrtime()
  local ok, result = M.safe_call(func, context, ...)
  local end_time = vim.loop.hrtime()
  local duration = (end_time - start_time) / 1e6 -- 转换为毫秒
  
  if ok then
    M.debug("%s completed in %.2f ms", context, duration)
  else
    M.error("%s failed after %.2f ms", context, duration)
  end
  
  return ok, result
end

-- 设置日志级别
function M.set_level(level)
  M._config.level = level
  M.info("Log level set to %s", M.level_names[level])
end

-- 启用/禁用文件日志
function M.set_file_logging(enabled)
  M._config.file_logging = enabled
  M.info("File logging %s", enabled and "enabled" or "disabled")
end

-- 启用/禁用控制台日志
function M.set_console_logging(enabled)
  M._config.console_logging = enabled
  if enabled then
    M.info("Console logging enabled")
  end
end

-- 清理日志文件
function M.clear_log_file()
  if M._config.file_logging then
    local file = io.open(M._config.log_file, "w")
    if file then
      file:close()
      M.info("Log file cleared")
    end
  end
end

-- 获取日志文件路径
function M.get_log_file()
  return M._config.log_file
end

-- 显示日志统计
function M.show_stats()
  local stat = vim.loop.fs_stat(M._config.log_file)
  if stat then
    M.info("Log file: %s (%.2f KB)", M._config.log_file, stat.size / 1024)
  else
    M.info("Log file: %s (not exists)", M._config.log_file)
  end
  M.info("Current log level: %s", M.level_names[M._config.level])
  M.info("File logging: %s", M._config.file_logging and "enabled" or "disabled")
  M.info("Console logging: %s", M._config.console_logging and "enabled" or "disabled")
end

return M