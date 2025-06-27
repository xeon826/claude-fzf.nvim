local M = {}
local notify = require('claude-fzf.notify')
local logger = require('claude-fzf.logger')

local fzf_lua = nil
local function get_fzf()
  if not fzf_lua then
    logger.debug("Attempting to load fzf-lua")
    local ok, fzf = pcall(require, 'fzf-lua')
    if ok then 
      fzf_lua = fzf 
      logger.info("fzf-lua loaded successfully")
    else
      logger.error("Failed to load fzf-lua: %s", fzf)
      error('[claude-fzf] fzf-lua not found, please install fzf-lua first')
    end
  end
  return fzf_lua
end

function M.create_claude_action(action_type, opts)
  opts = opts or {}
  
  return function(selected, o)
    logger.debug("[CLAUDE_ACTION] Action triggered: %s", action_type)
    logger.debug("[CLAUDE_ACTION] Selected items count: %d", selected and #selected or 0)
    logger.debug("[CLAUDE_ACTION] Raw selected items: %s", vim.inspect(selected))
    logger.debug("[CLAUDE_ACTION] FZF options: %s", vim.inspect(o))
    
    if not selected or #selected == 0 then
      logger.debug("[CLAUDE_ACTION] No items selected, aborting")
      notify.info('No items selected')
      return
    end
    
    -- Debug each selected item
    for i, item in ipairs(selected) do
      logger.debug("[CLAUDE_ACTION] Item %d: '%s' (type: %s, length: %d)", 
        i, item, type(item), #item)
      local bytes = {}
      for j = 1, math.min(#item, 50) do  -- Only show first 50 bytes
        table.insert(bytes, string.byte(item, j))
      end
      logger.debug("[CLAUDE_ACTION] Item %d bytes: [%s]", i, table.concat(bytes, ", "))
    end
    
    local claudecode = require('claude-fzf.integrations.claudecode')
    
    logger.debug("[CLAUDE_ACTION] Dispatching to action type: %s", action_type)
    
    local result
    if action_type == 'files' then
      logger.debug("[CLAUDE_ACTION] Sending to claudecode.send_selections")
      result = claudecode.send_selections(selected, opts)
    elseif action_type == 'grep' then
      logger.debug("[CLAUDE_ACTION] Sending to claudecode.send_grep_results")
      result = claudecode.send_grep_results(selected, opts)
    elseif action_type == 'buffers' then
      logger.debug("[CLAUDE_ACTION] Sending to claudecode.send_buffer_selections")
      result = claudecode.send_buffer_selections(selected, opts)
    else
      logger.error("[CLAUDE_ACTION] Unknown action type: %s", action_type)
      notify.error('Unknown action type: ' .. action_type)
      return false
    end
    
    logger.debug("[CLAUDE_ACTION] Action completed with result: %s", result)
    return result
  end
end

function M.files(opts)
  logger.info("Starting files picker")
  logger.debug("Files picker options: %s", vim.inspect(opts))
  
  local ok, result = logger.safe_call(function()
    local config = require('claude-fzf.config')
    opts = config.get_picker_opts('files', opts)
    logger.debug("Processed picker options: %s", vim.inspect(opts))
    
    local fzf = get_fzf()
    
    return fzf.files({
      prompt = opts.prompt or 'Add to Claude> ',
      multiselect = true,
      fzf_opts = {
        ['--header'] = opts.header or 'Select files/directories to add to Claude context. Tab to multi-select, Enter to confirm.',
      },
      winopts = opts.winopts or {},
      preview = opts.preview or {},
      actions = {
        ['default'] = M.create_claude_action('files'),
        ['ctrl-y'] = M.create_claude_action('files', { with_context = true }),
        ['ctrl-d'] = function(selected)
          logger.debug("Directory action triggered with: %s", vim.inspect(selected))
          local utils = require('claude-fzf.utils')  
          local dirs = utils.filter_directories(selected)
          if #dirs > 0 then
            M.create_claude_action('files')(dirs)
          else
            logger.warn("No directories selected")
            notify.info('No directories selected')
          end
        end,
        ['alt-a'] = function(selected, o)
          logger.debug("Toggle all action triggered")
          fzf.actions.toggle_all(selected, o)
        end,
      }
    })
  end, "files picker")
  
  if not ok then
    logger.error("Files picker failed: %s", result)
    return false
  end
  
  return result
end

function M.live_grep(opts)
  local config = require('claude-fzf.config')
  opts = config.get_picker_opts('grep', opts)
  
  local fzf = get_fzf()
  
  return fzf.live_grep({
    prompt = opts.prompt or 'Claude Grep> ',
    multiselect = true,
    fzf_opts = {
      ['--header'] = opts.header or 'Search and select results to add to Claude. Tab to multi-select.',
    },
    winopts = opts.winopts or {},
    preview = opts.preview or {},
    actions = {
      ['default'] = M.create_claude_action('grep'),
      ['ctrl-y'] = M.create_claude_action('grep', { with_context = true }),
      ['alt-a'] = function(selected, o)
        fzf.actions.toggle_all(selected, o)
      end,
    }
  })
end

function M.buffers(opts)
  local config = require('claude-fzf.config')
  opts = config.get_picker_opts('buffers', opts)
  
  local fzf = get_fzf()
  
  return fzf.buffers({
    prompt = opts.prompt or 'Claude Buffers> ',
    multiselect = true,
    fzf_opts = {
      ['--header'] = opts.header or 'Select buffers to add to Claude. Tab to multi-select.',
    },
    winopts = opts.winopts or {},
    preview = opts.preview or {},
    actions = {
      ['default'] = M.create_claude_action('buffers'),
      ['ctrl-y'] = M.create_claude_action('buffers', { with_context = true }),
      ['alt-a'] = function(selected, o)
        fzf.actions.toggle_all(selected, o)
      end,
    }
  })
end

function M.git_files(opts)
  local config = require('claude-fzf.config')
  opts = config.get_picker_opts('git_files', opts)
  
  local fzf = get_fzf()
  
  return fzf.git_files({
    prompt = opts.prompt or 'Claude Git Files> ',
    multiselect = true,
    fzf_opts = {
      ['--header'] = opts.header or 'Select Git files to add to Claude. Tab to multi-select.',
    },
    winopts = opts.winopts or {},
    preview = opts.preview or {},
    actions = {
      ['default'] = M.create_claude_action('files'),
      ['ctrl-y'] = M.create_claude_action('files', { with_context = true }),
      ['alt-a'] = function(selected, o)
        fzf.actions.toggle_all(selected, o)
      end,
    }
  })
end

function M.is_available()
  local ok, _ = pcall(require, 'fzf-lua')
  return ok
end

function M.check_health()
  if not M.is_available() then
    return false, 'fzf-lua not installed'
  end
  
  local fzf = get_fzf()
  if not fzf.files then
    return false, 'fzf-lua version too old, missing required features'
  end
  
  return true, 'fzf-lua available'
end

return M