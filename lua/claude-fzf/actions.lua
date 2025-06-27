local M = {}
local notify = require('claude-fzf.notify')

function M.send_to_claude(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    notify.info('No items selected')
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_selections(selected, opts)
end

function M.send_with_context(selected, opts)
  opts = opts or {}
  opts.with_context = true
  
  return M.send_to_claude(selected, opts)
end

function M.send_directory(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    notify.info('No items selected')
    return
  end
  
  local utils = require('claude-fzf.utils')
  local dirs = utils.filter_directories(selected)
  
  if #dirs == 0 then
    notify.info('No directories selected')
    return
  end
  
  local expanded_files = {}
  for _, dir in ipairs(dirs) do
    local files = utils.get_directory_files(dir, opts.max_depth or 2)
    vim.list_extend(expanded_files, files)
  end
  
  if #expanded_files == 0 then
    notify.info('No files found in directories')
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_selections(expanded_files, opts)
end

function M.send_grep_results(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    notify.info('No search results selected')
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_grep_results(selected, opts)
end

function M.send_buffers(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    notify.info('No buffers selected')
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_buffer_selections(selected, opts)
end

function M.toggle_all(selected, o)
  local fzf = require('fzf-lua')
  if fzf.actions and fzf.actions.toggle_all then
    return fzf.actions.toggle_all(selected, o)
  else
    notify.warning('toggle_all action not available')
  end
end

function M.preview_claude_context(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    return
  end
  
  local file = selected[1]
  if not file then return end
  
  local utils = require('claude-fzf.utils')
  local preview_content = utils.get_file_preview(file, opts.max_lines or 50)
  
  if preview_content then
    notify.info(
      string.format('Preview: %s\n%s', file, preview_content)
    )
  end
end

function M.batch_process_with_progress(items, processor, opts)
  opts = opts or {}
  local batch_size = opts.batch_size or 10
  local show_progress = opts.show_progress ~= false
  
  local total = #items
  local completed = 0
  local notification
  
  -- 只在开始时显示进度通知
  if show_progress then
    notify.progress("Processing items...", { id = 'batch_progress' })
  end
  
  local function process_batch(batch_start, batch_end)
    for i = batch_start, math.min(batch_end, total) do
      local success = processor(items[i])
      if success then
        completed = completed + 1
      end
    end
  end
  
  for i = 1, total, batch_size do
    vim.schedule(function()
      process_batch(i, i + batch_size - 1)
    end)
  end
  
  vim.schedule(function()
    if show_progress then
      if completed == total then
        notify.success(
          string.format("Completed: %d/%d files successfully sent to Claude", completed, total)
        )
      else
        notify.warning(
          string.format("Completed: %d/%d files successfully sent to Claude", completed, total)
        )
      end
    end
    
    if opts.callback then
      opts.callback(completed, total)
    end
  end)
  
  return completed
end

function M.create_custom_action(action_fn, opts)
  opts = opts or {}
  
  return function(selected, o)
    if not selected or #selected == 0 then
      if opts.allow_empty then
        return action_fn({}, o)
      else
        notify.info('No items selected')
        return
      end
    end
    
    if opts.single_selection and #selected > 1 then
      notify.warning('This action only supports single selection')
      return
    end
    
    return action_fn(selected, o)
  end
end

function M.with_confirmation(action_fn, message)
  message = message or "确认执行此操作？"
  
  return function(selected, o)
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)
    if choice == 1 then
      return action_fn(selected, o)
    end
  end
end

return M