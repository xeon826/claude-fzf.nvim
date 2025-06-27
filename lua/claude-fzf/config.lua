local M = {}
local notify = require('claude-fzf.notify')

M.defaults = {
  batch_size = 5,
  show_progress = true,
  auto_open_terminal = true,
  auto_context = true,
  
  -- 通知配置
  notifications = {
    enabled = true,              -- 是否启用通知
    show_progress = true,        -- 显示进度通知
    show_success = true,         -- 显示成功通知
    show_errors = true,          -- 显示错误通知
    use_snacks = true,           -- 优先使用 snacks.nvim (如果可用)
    timeout = 3000,              -- 通知超时时间 (毫秒)
  },
  
  -- 日志配置
  logging = {
    level = "INFO",              -- TRACE, DEBUG, INFO, WARN, ERROR
    file_logging = true,         -- 启用文件日志
    console_logging = true,      -- 启用控制台日志
    show_caller = true,          -- 显示调用位置
    timestamp = true,            -- 显示时间戳
  },
  
  keymaps = {
    files = "<leader>cf",
    grep = "<leader>cg", 
    buffers = "<leader>cb",
    git_files = "<leader>cgf",
  },
  
  fzf_opts = {
    preview = {
      border = 'sharp',
      title = '预览',
      wrap = 'wrap',
    },
    winopts = {
      height = 0.99,
      width = 0.99,
      backdrop = 60,
    }
  },
  
  claude_opts = {
    auto_open_terminal = true,
    context_lines = 5,
    source_tag = "claude-fzf",
  },
  
  picker_opts = {
    files = {
      prompt = '添加到 Claude> ',
      header = '选择文件/目录添加到 Claude 上下文。Tab 多选，Enter 确认。',
    },
    grep = {
      prompt = 'Claude Grep> ',
      header = '搜索并选择结果添加到 Claude。Tab 多选，Enter 确认。',
    },
    buffers = {
      prompt = 'Claude 缓冲区> ',
      header = '选择缓冲区添加到 Claude。Tab 多选，Enter 确认。',
    },
    git_files = {
      prompt = 'Claude Git 文件> ',
      header = '选择 Git 文件添加到 Claude。Tab 多选，Enter 确认。',
    }
  }
}

M._config = {}

function M.setup(opts)
  M._config = vim.tbl_deep_extend('force', M.defaults, opts or {})
  
  -- 初始化日志系统
  local logger = require('claude-fzf.logger')
  local log_config = M._config.logging
  
  -- 转换字符串级别为数字
  local log_level = logger.levels[log_config.level:upper()] or logger.levels.INFO
  
  logger.setup({
    level = log_level,
    file_logging = log_config.file_logging,
    console_logging = log_config.console_logging,
    show_caller = log_config.show_caller,
    timestamp = log_config.timestamp,
  })
  
  logger.info("claude-fzf.nvim successfully initialized - ready for file operations")
  logger.debug("Active keymaps: files=%s, grep=%s, buffers=%s, git_files=%s", 
    M._config.keymaps.files, M._config.keymaps.grep, M._config.keymaps.buffers, M._config.keymaps.git_files)
  logger.debug("Full config: %s", vim.inspect(M._config))
  
  M.validate_config()
  
  return M._config
end

function M.validate_config()
  local logger = require('claude-fzf.logger')
  logger.debug("[CONFIG] Validating configuration")
  
  local ok, err = pcall(function()
    vim.validate({
      batch_size = { M._config.batch_size, 'number' },
      show_progress = { M._config.show_progress, 'boolean' },
      auto_open_terminal = { M._config.auto_open_terminal, 'boolean' },
      auto_context = { M._config.auto_context, 'boolean' },
      keymaps = { M._config.keymaps, 'table' },
      fzf_opts = { M._config.fzf_opts, 'table' },
      claude_opts = { M._config.claude_opts, 'table' },
      picker_opts = { M._config.picker_opts, 'table' },
    })
  end)
  
  if not ok then
    logger.error("[CONFIG] Configuration validation failed: %s", err)
    error("[claude-fzf] Invalid configuration: " .. err)
  end
  
  logger.debug("[CONFIG] Basic validation passed")
  
  if M._config.batch_size < 1 then
    logger.warn("[CONFIG] Invalid batch_size: %d, resetting to 1", M._config.batch_size)
    M._config.batch_size = 1
    notify.warning('batch_size must be greater than 0, reset to 1')
  end
  
  if M._config.claude_opts.context_lines < 0 then
    logger.warn("[CONFIG] Invalid context_lines: %d, resetting to 0", M._config.claude_opts.context_lines)
    M._config.claude_opts.context_lines = 0
    notify.warning('context_lines must be greater than or equal to 0, reset to 0')
  end
  
  logger.debug("[CONFIG] Configuration validation completed successfully")
end

function M.get()
  return M._config
end

function M.get_picker_opts(picker_name, opts)
  opts = opts or {}
  local picker_config = M._config.picker_opts[picker_name] or {}
  local fzf_config = M._config.fzf_opts
  
  return vim.tbl_deep_extend('force', fzf_config, picker_config, opts)
end

function M.get_claude_opts()
  return M._config.claude_opts
end

function M.get_keymaps()
  if not M._config or not M._config.keymaps then
    return M.defaults.keymaps
  end
  return M._config.keymaps
end

function M.should_show_progress()
  return M._config.show_progress
end

function M.get_batch_size()
  return M._config.batch_size
end

function M.should_auto_open_terminal()
  return M._config.auto_open_terminal
end

function M.has_auto_context()
  return M._config.auto_context
end

return M