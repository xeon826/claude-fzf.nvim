--- 通知服务模块 - 支持 snacks.nvim 集成和可配置通知
local M = {}

-- 通知类型
M.types = {
  SUCCESS = 'success',
  ERROR = 'error',
  WARNING = 'warning',
  INFO = 'info',
  PROGRESS = 'progress'
}

-- 获取配置
local function get_config()
  local config = require('claude-fzf.config').get()
  return config.notifications or {}
end

-- 检查 snacks.nvim 可用性
local function has_snacks()
  local ok, snacks = pcall(require, 'snacks')
  return ok and snacks.notify ~= nil
end

-- 获取通知级别
local function get_vim_level(type)
  local levels = {
    [M.types.ERROR] = vim.log.levels.ERROR,
    [M.types.WARNING] = vim.log.levels.WARN,
    [M.types.INFO] = vim.log.levels.INFO,
    [M.types.SUCCESS] = vim.log.levels.INFO,
    [M.types.PROGRESS] = vim.log.levels.INFO,
  }
  return levels[type] or vim.log.levels.INFO
end

-- 格式化消息
local function format_message(message, title)
  if title then
    return string.format('%s %s', title, message)
  end
  return message
end

-- 使用 snacks.nvim 发送通知
local function notify_with_snacks(message, type, opts)
  local snacks = require('snacks')
  local snacks_opts = {
    title = opts.title,
    timeout = opts.timeout,
    id = opts.id,
  }
  
  -- 根据类型选择相应的 snacks 方法
  if type == M.types.ERROR then
    snacks.notify.error(message, snacks_opts)
  elseif type == M.types.WARNING then
    snacks.notify.warn(message, snacks_opts)
  elseif type == M.types.SUCCESS then
    snacks.notify.info(message, snacks_opts)
  else
    snacks.notify(message, snacks_opts)
  end
end

-- 使用原生 vim.notify 发送通知
local function notify_with_vim(message, type, opts)
  local formatted_msg = format_message(message, opts.title)
  local vim_level = get_vim_level(type)
  local vim_opts = {}
  
  if opts.replace and opts.id then
    vim_opts.replace = opts.replace
  end
  
  vim.notify(formatted_msg, vim_level, vim_opts)
end

-- 核心通知函数
function M.notify(message, type, opts)
  opts = opts or {}
  local config = get_config()
  
  -- 检查是否启用通知
  if not config.enabled then
    return
  end
  
  -- 根据类型检查是否应该显示
  if type == M.types.PROGRESS and not config.show_progress then
    return
  elseif type == M.types.SUCCESS and not config.show_success then
    return
  elseif type == M.types.ERROR and not config.show_errors then
    return
  end
  
  -- 设置默认选项
  opts.title = opts.title or '[claude-fzf]'
  opts.timeout = opts.timeout or config.timeout or 3000
  
  -- 选择通知后端
  if config.use_snacks and has_snacks() then
    notify_with_snacks(message, type, opts)
  else
    notify_with_vim(message, type, opts)
  end
end

-- 便捷方法
function M.success(message, opts)
  M.notify(message, M.types.SUCCESS, opts)
end

function M.error(message, opts)
  M.notify(message, M.types.ERROR, opts)
end

function M.warning(message, opts)
  M.notify(message, M.types.WARNING, opts)
end

function M.info(message, opts)
  M.notify(message, M.types.INFO, opts)
end

function M.progress(message, opts)
  M.notify(message, M.types.PROGRESS, opts)
end

-- 进度通知（带替换功能）
function M.show_progress(current, total, message, id)
  local progress_msg = string.format('%s: %d/%d', message, current, total) 
  M.progress(progress_msg, {
    id = id or 'claude_fzf_progress',
    replace = current > 1,
  })
end

-- 最终结果通知
function M.show_final_result(success_count, total, item_type, opts)
  opts = opts or {}
  local message = string.format('Completed: %d/%d %s successfully sent to Claude', success_count, total, item_type)
  
  if success_count == total then
    M.success(message, opts)
  else
    M.warning(message, opts)
  end
end

-- 检查通知系统状态
function M.check_status()
  local config = get_config()
  local status = {
    enabled = config.enabled,
    has_snacks = has_snacks(),
    use_snacks = config.use_snacks,
    show_progress = config.show_progress,
    show_success = config.show_success,
    show_errors = config.show_errors,
  }
  
  return status
end

return M