local M = {}

function M.send_to_claude(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    vim.notify('[claude-fzf] 未选择项目', vim.log.levels.INFO)
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
    vim.notify('[claude-fzf] 未选择项目', vim.log.levels.INFO)
    return
  end
  
  local utils = require('claude-fzf.utils')
  local dirs = utils.filter_directories(selected)
  
  if #dirs == 0 then
    vim.notify('[claude-fzf] 未选择目录', vim.log.levels.INFO)
    return
  end
  
  local expanded_files = {}
  for _, dir in ipairs(dirs) do
    local files = utils.get_directory_files(dir, opts.max_depth or 2)
    vim.list_extend(expanded_files, files)
  end
  
  if #expanded_files == 0 then
    vim.notify('[claude-fzf] 目录中未找到文件', vim.log.levels.INFO)
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_selections(expanded_files, opts)
end

function M.send_grep_results(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    vim.notify('[claude-fzf] 未选择搜索结果', vim.log.levels.INFO)
    return
  end
  
  local claudecode = require('claude-fzf.integrations.claudecode')
  return claudecode.send_grep_results(selected, opts)
end

function M.send_buffers(selected, opts)
  opts = opts or {}
  
  if not selected or #selected == 0 then
    vim.notify('[claude-fzf] 未选择缓冲区', vim.log.levels.INFO)
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
    vim.notify('[claude-fzf] toggle_all 动作不可用', vim.log.levels.WARN)
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
    vim.notify(
      string.format('[claude-fzf] 预览: %s\n%s', file, preview_content),
      vim.log.levels.INFO
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
  
  if show_progress then
    notification = vim.notify(
      string.format("正在发送到 Claude: 0/%d", total),
      vim.log.levels.INFO,
      { replace = true }
    )
  end
  
  local function process_batch(batch_start, batch_end)
    for i = batch_start, math.min(batch_end, total) do
      local success = processor(items[i])
      if success then
        completed = completed + 1
      end
      
      if show_progress then
        vim.notify(
          string.format("正在发送到 Claude: %d/%d", completed, total),
          vim.log.levels.INFO,
          { replace = notification }
        )
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
      vim.notify(
        string.format("完成: %d/%d 个文件成功发送到 Claude", completed, total),
        completed == total and vim.log.levels.INFO or vim.log.levels.WARN
      )
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
        vim.notify('[claude-fzf] 未选择项目', vim.log.levels.INFO)
        return
      end
    end
    
    if opts.single_selection and #selected > 1 then
      vim.notify('[claude-fzf] 此动作只支持单选', vim.log.levels.WARN)
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