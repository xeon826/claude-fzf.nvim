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
    health.ok("Neovim 版本: " .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch)
  else
    health.error("需要 Neovim 0.9 或更高版本")
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
    health.info("请安装: https://github.com/ibhagwan/fzf-lua")
  end
  
  local claude_ok, claude_msg = claude_integration.check_health()
  if claude_ok then
    health.ok("claudecode.nvim: " .. claude_msg)
  else
    health.error("claudecode.nvim: " .. claude_msg)
    health.info("请安装: https://github.com/coder/claudecode.nvim")
  end
end

function M.check_configuration()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  if current_config then
    health.ok("配置已加载")
    
    if current_config.batch_size > 0 then
      health.ok("批处理大小: " .. current_config.batch_size)
    else
      health.warn("批处理大小无效，应该大于 0")
    end
    
    if current_config.claude_opts.context_lines >= 0 then
      health.ok("上下文行数: " .. current_config.claude_opts.context_lines) 
    else
      health.warn("上下文行数无效，应该大于等于 0")
    end
    
    if current_config.keymaps then
      local keymaps = current_config.keymaps
      health.info("快捷键映射:")
      health.info("  文件: " .. (keymaps.files or "未设置"))
      health.info("  搜索: " .. (keymaps.grep or "未设置"))
      health.info("  缓冲区: " .. (keymaps.buffers or "未设置"))
      health.info("  Git 文件: " .. (keymaps.git_files or "未设置"))
    end
  else
    health.error("配置未加载，请运行 require('claude-fzf').setup()")
  end
end

function M.check_integrations()
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok then
    if fzf.files then
      health.ok("fzf-lua.files 可用")
    else
      health.error("fzf-lua.files 不可用")
    end
    
    if fzf.live_grep then
      health.ok("fzf-lua.live_grep 可用")
    else
      health.error("fzf-lua.live_grep 不可用")
    end
    
    if fzf.buffers then
      health.ok("fzf-lua.buffers 可用")
    else
      health.warn("fzf-lua.buffers 不可用")
    end
    
    if fzf.git_files then
      health.ok("fzf-lua.git_files 可用")
    else
      health.warn("fzf-lua.git_files 不可用")
    end
  end
  
  local claude_ok, claudecode = pcall(require, 'claudecode')
  if claude_ok then
    if claudecode.send_at_mention then
      health.ok("claudecode.send_at_mention 可用")
    else
      health.error("claudecode.send_at_mention 不可用，请更新 claudecode.nvim")  
    end
    
    local term_ok, term = pcall(require, "claudecode.terminal")
    if term_ok and term.open then
      health.ok("claudecode.terminal.open 可用")
    else
      health.warn("claudecode.terminal.open 不可用，自动打开终端功能将被禁用")
    end
  end
end

function M.check_git()
  local utils = require('claude-fzf.utils')
  
  if utils.is_git_repo() then
    local git_root = utils.get_git_root()
    health.ok("Git 仓库: " .. git_root)
  else
    health.info("当前目录不是 Git 仓库，Git 相关功能将不可用")
  end
end

function M.check_treesitter()
  local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
  if ok then
    health.ok("Tree-sitter 可用")
    
    local current_buf = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[current_buf].filetype
    
    if filetype and filetype ~= "" then
      if parsers.has_parser(filetype) then
        health.ok("当前文件类型 '" .. filetype .. "' 的 Tree-sitter 解析器可用")
      else
        health.info("当前文件类型 '" .. filetype .. "' 的 Tree-sitter 解析器不可用，智能上下文提取将被禁用")
      end
    else
      health.info("当前缓冲区没有文件类型")
    end
  else
    health.info("Tree-sitter 不可用，智能上下文提取将被禁用")
  end
end

function M.check_performance()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  if current_config.batch_size > 20 then
    health.warn("批处理大小较大 (" .. current_config.batch_size .. ")，可能影响性能")
  end
  
  if current_config.fzf_opts.height and type(current_config.fzf_opts.height) == "number" and current_config.fzf_opts.height > 0.9 then
    health.info("FZF 窗口高度较大，可能影响视觉体验")
  end
end

function M.show_info()
  local config = require('claude-fzf.config')
  local current_config = config.get()
  
  print("claude-fzf.nvim 配置信息:")
  print("  版本: 1.0.0")
  print("  批处理大小: " .. (current_config.batch_size or "未设置"))
  print("  显示进度: " .. tostring(current_config.show_progress))
  print("  自动打开终端: " .. tostring(current_config.auto_open_terminal))
  print("  智能上下文: " .. tostring(current_config.auto_context))
  print("  上下文行数: " .. (current_config.claude_opts.context_lines or "未设置"))
end

return M