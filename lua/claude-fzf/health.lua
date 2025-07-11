local M = {}

local health = vim.health

function M.check()
  health.start("claude-fzf.nvim")
  
  M.check_neovim_version()
  M.check_dependencies()
  M.check_configuration()
  M.check_integrations()
end

function M.check_neovim_version()
  if vim.fn.has('nvim-0.9') == 1 then
    health.ok("Neovim version: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
  else
    health.error("Requires Neovim 0.9 or higher")
  end
end

function M.check_dependencies()
  local fzf_integration = require('claude-fzf.integrations.fzf')
  local claude_integration = require('claude-fzf.integrations.claudecode')
  
  local fzf_ok, fzf_msg = fzf_integration.check_health()
  if fzf_ok then
    health.ok("fzf-lua: " .. fzf_msg)
  else
    health.error("fzf-lua: " .. fzf_msg)
    health.info("Please install: https://github.com/ibhagwan/fzf-lua")
  end
  
  local claude_ok, claude_msg = claude_integration.check_health()
  if claude_ok then
    health.ok("claudecode.nvim: " .. claude_msg)
  else
    health.error("claudecode.nvim: " .. claude_msg)
    health.info("Please install: https://github.com/coder/claudecode.nvim")
  end
end

function M.check_configuration()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  if current_config then
    health.ok("Configuration loaded")
    
    if current_config.batch_size > 0 then
      health.ok("Batch size: " .. current_config.batch_size)
    else
      health.warn("Invalid batch size, should be greater than 0")
    end
    
    if current_config.claude_opts.context_lines >= 0 then
      health.ok("Context lines: " .. current_config.claude_opts.context_lines) 
    else
      health.warn("Invalid context lines, should be greater than or equal to 0")
    end
    
    if current_config.keymaps then
      local keymaps = current_config.keymaps
      health.info("Keybindings:")
      health.info("  Files: " .. (keymaps.files or "not set"))
      health.info("  Search: " .. (keymaps.grep or "not set"))
      health.info("  Buffers: " .. (keymaps.buffers or "not set"))
      health.info("  Git files: " .. (keymaps.git_files or "not set"))
    end
    
    -- Check notification configuration
    if current_config.notifications then
      local notif = current_config.notifications
      health.info("Notification configuration:")
      health.info("  Enabled: " .. (notif.enabled and "yes" or "no"))
      health.info("  Show progress: " .. (notif.show_progress and "yes" or "no"))
      health.info("  Show success: " .. (notif.show_success and "yes" or "no"))
      health.info("  Show errors: " .. (notif.show_errors and "yes" or "no"))
      health.info("  Use snacks.nvim: " .. (notif.use_snacks and "yes" or "no"))
      health.info("  Timeout: " .. (notif.timeout or "default") .. " ms")
      
      -- Check snacks.nvim availability
      if notif.use_snacks then
        local snacks_ok, snacks = pcall(require, 'snacks')
        if snacks_ok and snacks.notify then
          health.ok("snacks.nvim notification system available")
        else
          health.warn("snacks.nvim not available, will use native vim.notify")
        end
      end
    end
  else
    health.error("Configuration not loaded, please run require('claude-fzf').setup()")
  end
end

function M.check_integrations()
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok then
    if fzf.files then
      health.ok("fzf-lua.files available")
    else
      health.error("fzf-lua.files not available")
    end
    
    if fzf.live_grep then
      health.ok("fzf-lua.live_grep available")
    else
      health.error("fzf-lua.live_grep not available")
    end
    
    if fzf.buffers then
      health.ok("fzf-lua.buffers available")
    else
      health.warn("fzf-lua.buffers not available")
    end
    
    if fzf.git_files then
      health.ok("fzf-lua.git_files available")
    else
      health.warn("fzf-lua.git_files not available")
    end
  end
  
  local claude_ok, claudecode = pcall(require, 'claudecode')
  if claude_ok then
    if claudecode.send_at_mention then
      health.ok("claudecode.send_at_mention available")
    else
      health.error("claudecode.send_at_mention not available, please update claudecode.nvim")  
    end
    
    local term_ok, term = pcall(require, "claudecode.terminal")
    if term_ok and term.open then
      health.ok("claudecode.terminal.open available")
    else
      health.warn("claudecode.terminal.open not available, auto-open terminal feature will be disabled")
    end
  end
end

function M.check_git()
  local utils = require('claude-fzf.utils')
  
  if utils.is_git_repo() then
    local git_root = utils.get_git_root()
    health.ok("Git repository: " .. git_root)
  else
    health.info("Current directory is not a Git repository, Git-related features will not be available")
  end
end

function M.check_treesitter()
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if ok then
    health.ok("Tree-sitter available")
    
    local current_buf = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[current_buf].filetype
    
    if filetype and filetype ~= "" then
      if parsers.has_parser(filetype) then
        health.ok("Tree-sitter parser for current filetype '" .. filetype .. "' available")
      else
        health.info("Tree-sitter parser for current filetype '" .. filetype .. "' not available, smart context extraction will be disabled")
      end
    else
      health.info("Current buffer has no filetype")
    end
  else
    health.info("Tree-sitter not available, smart context extraction will be disabled")
  end
end

function M.check_performance()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  if current_config.batch_size > 20 then
    health.warn("Large batch size (" .. current_config.batch_size .. "), may affect performance")
  end
  
  if current_config.fzf_opts.height and type(current_config.fzf_opts.height) == "number" and current_config.fzf_opts.height > 0.9 then
    health.info("FZF window height is large, may affect visual experience")
  end
end

function M.show_info()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  print("claude-fzf.nvim configuration info:")
  print("  Version: 1.0.0")
  print("  Batch size: " .. (current_config.batch_size or "not set"))
  print("  Show progress: " .. tostring(current_config.show_progress))
  print("  Auto-open terminal: " .. tostring(current_config.auto_open_terminal))
  print("  Smart context: " .. tostring(current_config.auto_context))
  print("  Context lines: " .. (current_config.claude_opts.context_lines or "not set"))
end

return M