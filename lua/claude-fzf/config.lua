local M = {}
local notify = require('claude-fzf.notify')

M.defaults = {
  batch_size = 5,
  show_progress = true,
  auto_open_terminal = true,
  auto_context = true,
  
  -- Notification settings
  notifications = {
    enabled = true,              -- Enable notifications
    show_progress = true,        -- Show progress notifications
    show_success = true,         -- Show success notifications
    show_errors = true,          -- Show error notifications
    use_snacks = true,           -- Prefer snacks.nvim if available
    timeout = 3000,              -- Notification timeout (ms)
  },
  
  -- Logging settings
  logging = {
    level = "INFO",              -- TRACE, DEBUG, INFO, WARN, ERROR
    file_logging = true,         -- Enable file logging
    console_logging = true,      -- Enable console logging
    show_caller = true,          -- Show caller information
    timestamp = true,            -- Show timestamps
  },
  
  keymaps = {
    -- files = "<C-f>",
    -- grep = "<leader>cg", 
    -- buffers = "<leader>cb",
    -- git_files = "<leader>cgf",
    -- directory_files = "<leader>cd",
  },
  
  fzf_opts = {
    preview = {
      border = 'sharp',
      title = 'Preview',
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
  
  -- Directory search configuration
  directory_search = {
    directories = {
      -- Add your custom directories here
      -- Example:
      -- screenshots = {
      --   path = vim.fn.expand("~/Desktop"),
      --   extensions = { "png", "jpg", "jpeg" },
      --   description = "Screenshots"
      -- }
    },
    default_extensions = {},  -- Empty means all files
  },

  picker_opts = {
    files = {
      prompt = 'Add to Claude> ',
      header = 'Select files/directories to add to Claude context. Tab to multi-select, Enter to confirm.',
    },
    grep = {
      prompt = 'Claude Grep> ',
      header = 'Search and select results to add to Claude. Tab to multi-select, Enter to confirm.',
    },
    buffers = {
      prompt = 'Claude Buffers> ',
      header = 'Select buffers to add to Claude. Tab to multi-select, Enter to confirm.',
    },
    git_files = {
      prompt = 'Claude Git Files> ',
      header = 'Select Git files to add to Claude. Tab to multi-select, Enter to confirm.',
    },
    directory_files = {
      prompt = 'Claude Directory> ',
      header = 'Select files from directory to add to Claude. Tab to multi-select, Enter to confirm.',
    }
  }
}

M._config = {}

function M.setup(opts)
  M._config = vim.tbl_deep_extend('force', M.defaults, opts or {})
  
  -- Initialize logging system
  local logger = require('claude-fzf.logger')
  local log_config = M._config.logging
  
  -- Convert string level to number
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
      directory_search = { M._config.directory_search, 'table' },
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
