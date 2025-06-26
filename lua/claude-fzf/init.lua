local M = {}

M._config = {}

function M.setup(opts)
  local config = require('claude-fzf.config')
  M._config = config.setup(opts)
  
  vim.validate({
    fzf_lua = { pcall(require, 'fzf-lua'), 'boolean' },
    claudecode = { pcall(require, 'claudecode'), 'boolean' },
  })
  
  require('claude-fzf.commands').setup()
end

function M.files(opts)
  return require('claude-fzf.integrations.fzf').files(opts)
end

function M.grep_add(opts)
  return require('claude-fzf.integrations.fzf').live_grep(opts)
end

function M.buffers(opts)
  return require('claude-fzf.integrations.fzf').buffers(opts)
end

function M.git_files(opts)
  return require('claude-fzf.integrations.fzf').git_files(opts)
end

function M.get_config()
  return M._config
end

return M