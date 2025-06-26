local M = {}
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
      error('[claude-fzf] fzf-lua 未找到，请先安装 fzf-lua')
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
      vim.notify('[claude-fzf] 未选择项目', vim.log.levels.INFO)
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
      vim.notify('[claude-fzf] 未知动作类型: ' .. action_type, vim.log.levels.ERROR)
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
      prompt = opts.prompt or 'Claude 文件> ',
      multiselect = true,
      fzf_opts = {
        ['--header'] = opts.header or '选择文件/目录添加到 Claude 上下文。Tab 多选。',
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
            vim.notify('[claude-fzf] 未选择目录', vim.log.levels.INFO)
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
      ['--header'] = opts.header or '搜索并选择结果添加到 Claude。Tab 多选。',
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
    prompt = opts.prompt or 'Claude 缓冲区> ',
    multiselect = true,
    fzf_opts = {
      ['--header'] = opts.header or '选择缓冲区添加到 Claude。Tab 多选。',
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
    prompt = opts.prompt or 'Claude Git 文件> ',
    multiselect = true,
    fzf_opts = {
      ['--header'] = opts.header or '选择 Git 文件添加到 Claude。Tab 多选。',
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
    return false, 'fzf-lua 未安装'
  end
  
  local fzf = get_fzf()
  if not fzf.files then
    return false, 'fzf-lua 版本过旧，缺少必要功能'
  end
  
  return true, 'fzf-lua 可用'
end

return M