if vim.g.loaded_claude_fzf then
  return
end

vim.g.loaded_claude_fzf = true

if vim.fn.has('nvim-0.9') == 0 then
  vim.notify('[claude-fzf] 需要 Neovim 0.9 或更高版本', vim.log.levels.ERROR)
  return
end

local function check_dependencies()
  local fzf_ok = pcall(require, 'fzf-lua')
  local claudecode_ok = pcall(require, 'claudecode')
  
  if not fzf_ok then
    vim.notify('[claude-fzf] 依赖缺失: fzf-lua 未安装', vim.log.levels.ERROR)
    return false
  end
  
  if not claudecode_ok then
    vim.notify('[claude-fzf] 依赖缺失: claudecode.nvim 未安装', vim.log.levels.ERROR)
    return false
  end
  
  return true
end

vim.api.nvim_create_user_command('ClaudeFzfSetup', function(opts)
  if not check_dependencies() then
    return
  end
  
  local config = {}
  if opts.args and opts.args ~= "" then
    local ok, parsed = pcall(vim.json.decode, opts.args)
    if ok then
      config = parsed
    else
      vim.notify('[claude-fzf] 配置参数解析失败', vim.log.levels.ERROR)
      return
    end
  end
  
  require('claude-fzf').setup(config)
  vim.notify('[claude-fzf] 插件已设置完成', vim.log.levels.INFO)
end, {
  desc = '设置 claude-fzf 插件',
  nargs = '?'
})

vim.api.nvim_create_user_command('ClaudeFzfHealth', function()
  require('claude-fzf.health').check()
end, {
  desc = '检查 claude-fzf 插件健康状态'
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'LazyVimStarted',
  callback = function()
    vim.schedule(function()
      if vim.g.claude_fzf_auto_setup then
        require('claude-fzf').setup(vim.g.claude_fzf_config or {})
      end
    end)
  end,
})