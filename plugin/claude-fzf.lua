if vim.g.loaded_claude_fzf then
  return
end

vim.g.loaded_claude_fzf = true

if vim.fn.has('nvim-0.9') == 0 then
  vim.notify('[claude-fzf] Requires Neovim 0.9 or higher', vim.log.levels.ERROR)
  return
end

local function check_dependencies()
  local fzf_ok = pcall(require, 'fzf-lua')
  local claudecode_ok = pcall(require, 'claudecode')
  
  if not fzf_ok then
    vim.notify('[claude-fzf] Dependency missing: fzf-lua not installed', vim.log.levels.ERROR)
    return false
  end
  
  if not claudecode_ok then
    vim.notify('[claude-fzf] Dependency missing: claudecode.nvim not installed', vim.log.levels.ERROR)
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
      vim.notify('[claude-fzf] Configuration parameter parsing failed', vim.log.levels.ERROR)
      return
    end
  end
  
  require('claude-fzf').setup(config)
  vim.notify('[claude-fzf] Plugin setup completed', vim.log.levels.INFO)
end, {
  desc = 'Setup claude-fzf plugin',
  nargs = '?'
})

vim.api.nvim_create_user_command('ClaudeFzfHealth', function()
  require('claude-fzf.health').check()
end, {
  desc = 'Check claude-fzf plugin health status'
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