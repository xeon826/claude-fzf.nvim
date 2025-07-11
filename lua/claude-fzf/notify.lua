--- Notification service module - Supports snacks.nvim integration and configurable notifications
local M = {}

-- Notification types
M.types = {
  SUCCESS = 'success',
  ERROR = 'error',
  WARNING = 'warning',
  INFO = 'info',
  PROGRESS = 'progress'
}

-- Get configuration
local function get_config()
  local config = require('claude-fzf.config').get()
  return config.notifications or {}
end

-- Check snacks.nvim availability
local function has_snacks()
  local ok, snacks = pcall(require, 'snacks')
  return ok and snacks.notify ~= nil
end

-- Get notification level
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

-- Format message
local function format_message(message, title)
  if title then
    return string.format('%s %s', title, message)
  end
  return message
end

-- Send notification using snacks.nvim
local function notify_with_snacks(message, type, opts)
  local snacks = require('snacks')
  local snacks_opts = {
    title = opts.title,
    timeout = opts.timeout,
    id = opts.id,
  }
  
  -- Select appropriate snacks method based on type
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

-- Send notification using native vim.notify
local function notify_with_vim(message, type, opts)
  local formatted_msg = format_message(message, opts.title)
  local vim_level = get_vim_level(type)
  local vim_opts = {}
  
  if opts.replace and opts.id then
    vim_opts.replace = opts.replace
  end
  
  vim.notify(formatted_msg, vim_level, vim_opts)
end

-- Core notification function
function M.notify(message, type, opts)
  opts = opts or {}
  local config = get_config()
  
  -- Check if notifications are enabled
  if not config.enabled then
    return
  end
  
  -- Check if notification should be shown based on type
  if type == M.types.PROGRESS and not config.show_progress then
    return
  elseif type == M.types.SUCCESS and not config.show_success then
    return
  elseif type == M.types.ERROR and not config.show_errors then
    return
  end
  
  -- Set default options
  opts.title = opts.title or '[claude-fzf]'
  opts.timeout = opts.timeout or config.timeout or 3000
  
  -- Select notification backend
  if config.use_snacks and has_snacks() then
    notify_with_snacks(message, type, opts)
  else
    notify_with_vim(message, type, opts)
  end
end

-- Convenience methods
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

-- Progress notification (with replacement functionality)
function M.show_progress(current, total, message, id)
  local progress_msg = string.format('%s: %d/%d', message, current, total) 
  M.progress(progress_msg, {
    id = id or 'claude_fzf_progress',
    replace = current > 1,
  })
end

-- Final result notification
function M.show_final_result(success_count, total, item_type, opts)
  opts = opts or {}
  local message = string.format('Completed: %d/%d %s successfully sent to Claude', success_count, total, item_type)
  
  if success_count == total then
    M.success(message, opts)
  else
    M.warning(message, opts)
  end
end

-- Check notification system status
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