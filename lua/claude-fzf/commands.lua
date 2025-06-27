local M = {}
local notify = require('claude-fzf.notify')

local function parse_args(args)
  if not args or args == "" then
    return {}
  end
  
  local ok, result = pcall(vim.json.decode, args)
  if ok then
    return result
  else
    notify.warning('Parameter parsing failed, using default configuration')
    return {}
  end
end

function M.setup()
  vim.api.nvim_create_user_command('ClaudeFzfFiles', function(opts)
    require('claude-fzf.integrations.fzf').files(parse_args(opts.args))
  end, { 
    desc = '使用 fzf 选择文件发送到 Claude',
    nargs = '?'
  })
  
  vim.api.nvim_create_user_command('ClaudeFzfGrep', function(opts)
    require('claude-fzf.integrations.fzf').live_grep(parse_args(opts.args))
  end, { 
    desc = '使用 fzf grep 搜索并发送到 Claude',
    nargs = '?'
  })
  
  vim.api.nvim_create_user_command('ClaudeFzfBuffers', function(opts)
    require('claude-fzf.integrations.fzf').buffers(parse_args(opts.args))
  end, { 
    desc = '使用 fzf 选择缓冲区发送到 Claude',
    nargs = '?'
  })
  
  vim.api.nvim_create_user_command('ClaudeFzfGitFiles', function(opts)
    require('claude-fzf.integrations.fzf').git_files(parse_args(opts.args))
  end, { 
    desc = '使用 fzf 选择 Git 文件发送到 Claude',
    nargs = '?'
  })
  
  vim.api.nvim_create_user_command('ClaudeFzf', function(opts)
    local args = opts.args or ""
    if args == "" or args == "files" then
      require('claude-fzf.integrations.fzf').files()
    elseif args == "grep" then
      require('claude-fzf.integrations.fzf').live_grep()
    elseif args == "buffers" then
      require('claude-fzf.integrations.fzf').buffers()
    elseif args == "git" then
      require('claude-fzf.integrations.fzf').git_files()
    else
      notify.error('Unknown subcommand: ' .. args)
      notify.info('Available subcommands: files, grep, buffers, git')
    end
  end, { 
    desc = 'Claude FZF - 多功能选择器',
    nargs = '?',
    complete = function()
      return {'files', 'grep', 'buffers', 'git'}
    end
  })
  
  local config = require('claude-fzf.config')
  local keymaps = config.get_keymaps()
  
  if keymaps and keymaps.files and keymaps.files ~= "" then
    vim.keymap.set('n', keymaps.files, '<cmd>ClaudeFzfFiles<cr>', { desc = 'Claude: Add Files' })
  end
  
  if keymaps and keymaps.grep and keymaps.grep ~= "" then
    vim.keymap.set('n', keymaps.grep, '<cmd>ClaudeFzfGrep<cr>', { desc = 'Claude: Search and Add' })
  end
  
  if keymaps and keymaps.buffers and keymaps.buffers ~= "" then
    vim.keymap.set('n', keymaps.buffers, '<cmd>ClaudeFzfBuffers<cr>', { desc = 'Claude: Add Buffers' })
  end
  
  if keymaps and keymaps.git_files and keymaps.git_files ~= "" then
    vim.keymap.set('n', keymaps.git_files, '<cmd>ClaudeFzfGitFiles<cr>', { desc = 'Claude: Add Git Files' })
  end
  
  -- 调试命令
  vim.api.nvim_create_user_command('ClaudeFzfDebug', function(opts)
    local logger = require('claude-fzf.logger')
    local args = opts.args or ""
    
    if args == "on" or args == "enable" then
      logger.set_level(logger.levels.DEBUG)
      logger.info("Debug logging enabled")
    elseif args == "off" or args == "disable" then
      logger.set_level(logger.levels.INFO)
      logger.info("Debug logging disabled")
    elseif args == "trace" then
      logger.set_level(logger.levels.TRACE)
      logger.info("Trace logging enabled")
    elseif args == "stats" then
      logger.show_stats()
    elseif args == "clear" then
      logger.clear_log_file()
    elseif args == "log" then
      local log_file = logger.get_log_file()
      vim.cmd('edit ' .. log_file)
    elseif args == "reload" then
      -- 强制重新加载所有模块
      for k,v in pairs(package.loaded) do
        if k:match('^claude%-fzf') then
          package.loaded[k] = nil
          logger.info("Cleared module: %s", k)
        end
      end
      
      -- 重新设置插件
      require('claude-fzf').setup({
        logging = {
          level = 'DEBUG',
          file_logging = true,
          console_logging = true,
        }
      })
      
      logger.info("All modules reloaded successfully")
    elseif args == "test" then
      -- 测试路径解析
      local claudecode = require('claude-fzf.integrations.claudecode')
      local test_files = {' CLAUDE.md', ' Cargo.lock', ' README.md'}
      
      for _, selection in ipairs(test_files) do
        local result = claudecode.parse_selection(selection)
        if result then
          logger.info("Parse test SUCCESS: '%s' -> '%s'", selection, result.path)
        else
          logger.warn("Parse test FAILED: '%s'", selection)
        end
      end
    else
      notify.info([[Debug commands:
  :ClaudeFzfDebug on/enable  - Enable debug logging
  :ClaudeFzfDebug off/disable - Disable debug logging  
  :ClaudeFzfDebug trace      - Enable trace logging
  :ClaudeFzfDebug stats      - Show log statistics
  :ClaudeFzfDebug clear      - Clear log file
  :ClaudeFzfDebug log        - Open log file
  :ClaudeFzfDebug reload     - Reload all modules
  :ClaudeFzfDebug test       - Test path parsing]])
    end
  end, {
    desc = 'Claude FZF 调试工具',
    nargs = '?',
    complete = function()
      return {'on', 'off', 'enable', 'disable', 'trace', 'stats', 'clear', 'log', 'reload', 'test'}
    end
  })
end

return M