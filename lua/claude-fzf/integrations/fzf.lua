local M = {}
local notify = require('claude-fzf.notify')
local logger = require('claude-fzf.logger')

local fzf_lua = nil
local function get_fzf()
  if not fzf_lua then
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
    
    if not selected or #selected == 0 then
      notify.info('No items selected')
      return
    end
    
    local claudecode = require('claude-fzf.integrations.claudecode')
    
    local result
    if action_type == 'files' then
      result = claudecode.send_selections(selected, opts)
    elseif action_type == 'grep' then
      result = claudecode.send_grep_results(selected, opts)
    elseif action_type == 'buffers' then
      result = claudecode.send_buffer_selections(selected, opts)
    else
      logger.error("Unknown action type: %s", action_type)
      notify.error('Unknown action type: ' .. action_type)
      return false
    end
    
    return result
  end
end

-- Create clipboard copy action
function M.create_clipboard_action(action_type, opts)
  opts = opts or {}
  
  return function(selected, o)
    logger.debug("[CLIPBOARD_ACTION] Action triggered: %s", action_type)
    logger.debug("[CLIPBOARD_ACTION] Selected items count: %d", selected and #selected or 0)
    
    if not selected or #selected == 0 then
      notify.info('No items selected')
      return
    end
    
    local claudecode = require('claude-fzf.integrations.claudecode')
    
    local result
    if action_type == 'files' then
      result = claudecode.copy_selections_to_clipboard(selected, opts)
    elseif action_type == 'grep' then
      result = claudecode.copy_grep_results_to_clipboard(selected, opts)
    elseif action_type == 'buffers' then
      result = claudecode.copy_buffer_selections_to_clipboard(selected, opts)
    else
      logger.error("Unknown clipboard action type: %s", action_type)
      notify.error('Unknown clipboard action type: ' .. action_type)
      return false
    end
    
    return result
  end
end

function M.files(opts)
  logger.info("Starting files picker")
  
  local ok, result = logger.safe_call(function()
    local config = require('claude-fzf.config')
    opts = config.get_picker_opts('files', opts)
    
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
        ['ctrl-l'] = M.create_clipboard_action('files'),
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
          if fzf.actions and fzf.actions.toggle_all then
            fzf.actions.toggle_all(selected, o)
          else
            return selected
          end
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
      ['ctrl-l'] = M.create_clipboard_action('grep'),
      ['alt-a'] = function(selected, o)
        if fzf.actions and fzf.actions.toggle_all then
          fzf.actions.toggle_all(selected, o)
        else
          return selected
        end
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
      ['ctrl-l'] = M.create_clipboard_action('buffers'),
      ['alt-a'] = function(selected, o)
        if fzf.actions and fzf.actions.toggle_all then
          fzf.actions.toggle_all(selected, o)
        else
          return selected
        end
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
        -- Use Ctrl-l for copy to align with other pickers
        ['ctrl-l'] = M.create_clipboard_action('files'),
        -- Keep Ctrl-c as an additional alias for backward compatibility
        ['ctrl-c'] = M.create_clipboard_action('files'),
        ['alt-a'] = function(selected, o)
          if fzf.actions and fzf.actions.toggle_all then
            fzf.actions.toggle_all(selected, o)
          else
            return selected
        end
      end,
    }
  })
end

function M.directory_files(opts)
  logger.info("Starting directory files picker")
  
  local ok, result = logger.safe_call(function()
    local config = require('claude-fzf.config')
    local full_config = config.get()
    
    -- Show directory selection first if no directory specified
    if not opts or not opts.directory then
      return M._show_directory_selector(opts)
    end
    
    -- Get directory configuration
    local dir_config = full_config.directory_search.directories[opts.directory]
    if not dir_config then
      logger.error("Unknown directory configuration: %s", opts.directory)
      notify.error('Unknown directory: ' .. opts.directory)
      return false
    end
    
    -- Check if directory exists
    if vim.fn.isdirectory(dir_config.path) == 0 then
      logger.warn("Directory does not exist: %s", dir_config.path)
      notify.warning('Directory does not exist: ' .. dir_config.path)
      return false
    end
    
    -- Build file search command with extension filtering
    local search_cmd = M._build_directory_search_cmd(dir_config)
    
    opts = config.get_picker_opts('directory_files', opts)
    local fzf = get_fzf()
    
    return fzf.files({
      prompt = string.format('%s (%s)> ', opts.prompt or 'Claude Directory', dir_config.description),
      multiselect = true,
      raw_cmd = table.concat(search_cmd, ' '),
      fzf_opts = {
        ['--header'] = opts.header or 'Select files from directory to add to Claude. Tab to multi-select.',
      },
      winopts = opts.winopts or {},
      preview = opts.preview or {},
      actions = {
        ['default'] = M.create_claude_action('files'),
        ['ctrl-y'] = M.create_claude_action('files', { with_context = true }),
        ['ctrl-l'] = M.create_clipboard_action('files'),
        ['alt-a'] = function(selected, o)
          -- toggle_all is handled by fzf keybinding, this is just a placeholder
          return selected
        end,
      }
    })
  end, "directory files picker")
  
  if not ok then
    logger.error("Directory files picker failed: %s", result)
    return false
  end
  
  return result
end

function M._show_directory_selector(opts)
  local config = require('claude-fzf.config')
  local full_config = config.get()
  local directories = full_config.directory_search.directories
  
  -- Build directory list for selection
  local dir_list = {}
  for key, dir_config in pairs(directories) do
    local status = vim.fn.isdirectory(dir_config.path) == 1 and "✓" or "✗"
    local ext_info = #dir_config.extensions > 0 
      and string.format(" [%s]", table.concat(dir_config.extensions, ","))
      or " [all files]"
    table.insert(dir_list, string.format("%s %s - %s%s", status, key, dir_config.description, ext_info))
  end
  
  if #dir_list == 0 then
    notify.info([[No directories configured for directory search.
Add directories in your config:
require('claude-fzf').setup({
  directory_search = {
    directories = {
      screenshots = {
        path = vim.fn.expand("~/Desktop"),
        extensions = { "png", "jpg", "jpeg" },
        description = "Screenshots"
      }
    }
  }
})]])
    return false
  end
  
  local fzf = get_fzf()
  opts = config.get_picker_opts('directory_files', opts)
  
  return fzf.fzf_exec(dir_list, {
    prompt = 'Select Directory> ',
    fzf_opts = {
      ['--header'] = 'Choose a directory to search files from',
    },
    winopts = opts.winopts or {},
    actions = {
      ['default'] = function(selected)
        if not selected or #selected == 0 then
          return
        end
        
        -- Extract directory key from selection
        local selection = selected[1]
        -- Parse format: "✓ key - description [extensions]"
        local parts = vim.split(selection, ' ')
        local dir_key = parts[2] -- Second part is the key (after status indicator)
        
        if not dir_key or dir_key == '' then
          logger.error("Failed to parse directory selection: %s", selection)
          notify.error('Failed to parse directory selection')
          return
        end
        
        -- Check if directory exists before proceeding
        local dir_config = directories[dir_key]
        if vim.fn.isdirectory(dir_config.path) == 0 then
          notify.error('Directory does not exist: ' .. dir_config.path)
          return
        end
        
        -- Launch directory files picker for selected directory
        M.directory_files(vim.tbl_extend('force', opts or {}, { directory = dir_key }))
      end,
    }
  })
end

function M._build_directory_search_cmd(dir_config)
  local path = dir_config.path
  local extensions = dir_config.extensions or {}
  
  -- Use fd for better performance and Unicode support
  local cmd = { 'fd', '--type', 'f', '--hidden', '--follow' }
  
  -- Add extension filters if specified
  if #extensions > 0 then
    for _, ext in ipairs(extensions) do
      table.insert(cmd, '-e')
      table.insert(cmd, ext)
    end
  end
  
  -- Add search path
  table.insert(cmd, '.')
  table.insert(cmd, path)
  
  return cmd
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
  
  -- Check for other required functions
  local required_functions = {'files', 'live_grep', 'buffers', 'git_files', 'fzf_exec'}
  for _, func_name in ipairs(required_functions) do
    if not fzf[func_name] then
      logger.error("fzf.%s not available", func_name)
      return false, string.format('fzf-lua missing function: %s', func_name)
    end
  end
  
  return true, 'fzf-lua available'
end

return M
