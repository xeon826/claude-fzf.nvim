local M = {}
local logger = require('claude-fzf.logger')

local ErrorTypes = {
  DEPENDENCY_MISSING = "dependency_missing",
  CONNECTION_FAILED = "connection_failed", 
  INVALID_SELECTION = "invalid_selection",
  CONTEXT_EXTRACTION_FAILED = "context_failed",
  FILE_NOT_FOUND = "file_not_found",
  PERMISSION_DENIED = "permission_denied",
}

function M.send_selections(selections, opts)
  opts = opts or {}
  logger.info("Sending %d selections to Claude", #selections)
  logger.debug("Selections: %s", vim.inspect(selections))
  logger.debug("Options: %s", vim.inspect(opts))
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    logger.error("Failed to load claudecode.nvim: %s", claudecode)
    M.handle_error(ErrorTypes.DEPENDENCY_MISSING, {
      dependency = 'claudecode.nvim',
      install_cmd = 'lazy.nvim: { "coder/claudecode.nvim" }'
    })
    return false, "claudecode.nvim 未找到"
  end
  
  logger.debug("claudecode.nvim loaded successfully")
  
  local config = require('claude-fzf.config')
  local claude_opts = config.get_claude_opts()
  
  local success_count = 0
  local total = #selections
  
  for i, selection in ipairs(selections) do
    logger.debug("Processing selection %d/%d: %s", i, total, selection)
    
    local file_info = M.parse_selection(selection)
    if file_info then
      logger.debug("Parsed file info: %s", vim.inspect(file_info))
      
      if config.should_show_progress() then
        M.show_progress(i, total, "发送到 Claude")
      end
      
      local success, err
      if opts.with_context and config.has_auto_context() then
        logger.debug("Extracting context for %s", file_info.path)
        local context = M.extract_context(file_info.path, file_info.start_line)
        if context then
          logger.debug("Context extracted: %s", vim.inspect(context))
          success, err = logger.safe_call(
            claudecode.send_at_mention,
            string.format("send_at_mention(%s:%d-%d)", file_info.path, context.start_line, context.end_line),
            file_info.path, 
            context.start_line, 
            context.end_line,
            claude_opts.source_tag or "claude-fzf-integration"
          )
        else
          logger.debug("No context extracted, sending whole file")
          success, err = logger.safe_call(
            claudecode.send_at_mention,
            string.format("send_at_mention(%s)", file_info.path),
            file_info.path, 
            file_info.start_line, 
            file_info.end_line,
            claude_opts.source_tag or "claude-fzf-integration"
          )
        end
      else
        logger.debug("Sending without context: %s", file_info.path)
        success, err = logger.safe_call(
          claudecode.send_at_mention,
          string.format("send_at_mention(%s)", file_info.path),
          file_info.path, 
          file_info.start_line, 
          file_info.end_line,
          claude_opts.source_tag or "claude-fzf-integration"
        )
      end
      
      if success then
        success_count = success_count + 1
        logger.debug("Successfully sent: %s", file_info.path)
      else
        logger.error("Failed to send %s: %s", file_info.path, err or "未知错误")
        vim.notify(
          string.format('[claude-fzf] 发送失败: %s - %s', 
            file_info.path, err or "未知错误"),
          vim.log.levels.WARN
        )
      end
    else
      logger.warn("[SEND_SELECTIONS] Invalid selection: '%s' (trimmed: '%s')", selection, vim.trim(selection))
      logger.debug("[SEND_SELECTIONS] Selection bytes: [%s]", 
        table.concat({string.byte(selection, 1, #selection)}, ", "))
      M.handle_error(ErrorTypes.INVALID_SELECTION, { selection = selection })
    end
  end
  
  M.show_final_result(success_count, total, "文件")
  
  if config.should_auto_open_terminal() and success_count > 0 then
    M.auto_open_terminal()
  end
  
  return success_count > 0
end

function M.send_grep_results(selections, opts)
  opts = opts or {}
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    M.handle_error(ErrorTypes.DEPENDENCY_MISSING, {
      dependency = 'claudecode.nvim',
      install_cmd = 'lazy.nvim: { "coder/claudecode.nvim" }'
    })
    return false, "claudecode.nvim 未找到"
  end
  
  local config = require('claude-fzf.config')
  local claude_opts = config.get_claude_opts()
  
  local success_count = 0
  local total = #selections
  local file_selections = {}
  
  for _, line in ipairs(selections) do
    local file, line_num, content = line:match("^([^:]+):(%d+):(.*)$")
    if file and line_num then
      table.insert(file_selections, {
        file = file,
        line = tonumber(line_num),
        content = content
      })
    end
  end
  
  total = #file_selections
  
  for i, selection in ipairs(file_selections) do
    if config.should_show_progress() then
      M.show_progress(i, total, "发送搜索结果到 Claude")
    end
    
    local context_lines = claude_opts.context_lines or 5
    local start_line = math.max(1, selection.line - context_lines)
    local end_line = selection.line + context_lines
    
    local success, err = claudecode.send_at_mention(
      selection.file, 
      start_line,
      end_line,
      claude_opts.source_tag or "claude-fzf-grep"
    )
    
    if success then
      success_count = success_count + 1
    else
      vim.notify(
        string.format('[claude-fzf] 发送失败: %s:%d - %s', 
          selection.file, selection.line, err or "未知错误"),
        vim.log.levels.WARN
      )
    end
  end
  
  M.show_final_result(success_count, total, "搜索结果")
  
  if config.should_auto_open_terminal() and success_count > 0 then
    M.auto_open_terminal()
  end
  
  return success_count > 0
end

function M.send_buffer_selections(selections, opts)
  opts = opts or {}
  logger.info("[BUFFER_SELECTIONS] Sending %d buffer selections to Claude", #selections)
  logger.debug("[BUFFER_SELECTIONS] Raw selections: %s", vim.inspect(selections))
  logger.debug("[BUFFER_SELECTIONS] Options: %s", vim.inspect(opts))
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    logger.error("[BUFFER_SELECTIONS] Failed to load claudecode.nvim: %s", claudecode)
    M.handle_error(ErrorTypes.DEPENDENCY_MISSING, {
      dependency = 'claudecode.nvim',
      install_cmd = 'lazy.nvim: { "coder/claudecode.nvim" }'
    })
    return false, "claudecode.nvim 未找到"
  end
  
  logger.debug("[BUFFER_SELECTIONS] claudecode.nvim loaded successfully")
  
  local config = require('claude-fzf.config')
  local claude_opts = config.get_claude_opts()
  
  local success_count = 0
  local total = #selections
  
  for i, selection in ipairs(selections) do
    logger.debug("[BUFFER_SELECTIONS] Processing selection %d/%d: '%s'", i, total, selection)
    
    local file_path = M.parse_buffer_selection(selection)
    if file_path then
      logger.debug("[BUFFER_SELECTIONS] Parsed file path: '%s'", file_path)
      
      if config.should_show_progress() then
        M.show_progress(i, total, "发送缓冲区到 Claude")
      end
      
      local success, err = logger.safe_call(
        claudecode.send_at_mention,
        string.format("send_at_mention(%s)", file_path),
        file_path, 
        nil, 
        nil,
        claude_opts.source_tag or "claude-fzf-buffers"
      )
      
      if success then
        success_count = success_count + 1
        logger.debug("[BUFFER_SELECTIONS] Successfully sent: %s", file_path)
      else
        logger.error("[BUFFER_SELECTIONS] Failed to send %s: %s", file_path, err or "未知错误")
        vim.notify(
          string.format('[claude-fzf] 发送失败: %s - %s', 
            file_path, err or "未知错误"),
          vim.log.levels.WARN
        )
      end
    else
      logger.warn("[BUFFER_SELECTIONS] Failed to parse buffer selection: '%s'", selection)
      M.handle_error(ErrorTypes.INVALID_SELECTION, { selection = selection })
    end
  end
  
  logger.debug("[BUFFER_SELECTIONS] Completed: %d/%d successful", success_count, total)
  M.show_final_result(success_count, total, "缓冲区")
  
  if config.should_auto_open_terminal() and success_count > 0 then
    logger.debug("[BUFFER_SELECTIONS] Auto-opening terminal")
    M.auto_open_terminal()
  end
  
  local result = success_count > 0
  logger.debug("[BUFFER_SELECTIONS] Final result: %s", result)
  return result
end

function M.extract_context(file_path, line)
  if not line then return nil end
  
  local bufnr = vim.fn.bufnr(file_path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(bufnr)
  end
  
  local parser = vim.treesitter.get_parser(bufnr, vim.bo[bufnr].filetype)
  if not parser then
    return nil
  end
  
  local tree = parser:parse()[1]
  local node = tree:root():descendant_for_range(line - 1, 0, line - 1, 0)
  
  while node do
    if vim.tbl_contains({'function', 'method', 'class', 'function_definition'}, node:type()) then
      local start_line, _, end_line, _ = node:range()
      return { 
        start_line = start_line + 1, 
        end_line = end_line + 1,
        node_type = node:type()
      }
    end
    node = node:parent()
  end
  
  return nil
end

function M.parse_selection(selection)
  logger.debug("[PARSE_SELECTION] Raw input: '%s' (type: %s, length: %d)", 
    selection or "nil", type(selection), selection and #selection or 0)
  
  if not selection or selection == "" then
    logger.debug("[PARSE_SELECTION] Empty or nil selection")
    return nil
  end
  
  -- Debug: Show raw bytes for debugging whitespace issues
  local byte_repr = {}
  for i = 1, #selection do
    table.insert(byte_repr, string.byte(selection, i))
  end
  logger.debug("[PARSE_SELECTION] Raw bytes: [%s]", table.concat(byte_repr, ", "))
  
  -- FIX: Remove file icons and Unicode spaces from fzf-lua output while preserving Chinese characters
  local file_path = selection
  
  -- Remove specific Unicode spaces that fzf adds (exact patterns only)
  file_path = file_path:gsub("\226\128\130", "")  -- U+2002 EN SPACE
  file_path = file_path:gsub("\226\128\131", "")  -- U+2003 EM SPACE  
  file_path = file_path:gsub("\226\128\137", "")  -- U+2009 THIN SPACE
  file_path = file_path:gsub("\226\128\138", "")  -- U+200A HAIR SPACE
  file_path = file_path:gsub("\226\128\139", "")  -- U+200B ZERO WIDTH SPACE
  
  -- Remove specific icon characters we've seen in logs (exact patterns only)
  file_path = file_path:gsub("\239\146\138", "")  -- Specific file icon from logs
  file_path = file_path:gsub("\238\156\130", "")  -- Another icon pattern
  
  -- Remove common file icons by specific known sequences (not dangerous ranges!)
  local common_icons = {
    "\238\156\128",  -- Common file icons
    "\238\156\129", 
    "\238\156\131", 
    "\238\156\132", 
    "\238\156\133", 
    "\238\156\134",
  }
  
  for _, icon in ipairs(common_icons) do
    file_path = file_path:gsub(icon, "")
  end
  
  -- Standard whitespace trimming
  file_path = vim.trim(file_path)
  
  logger.debug("[PARSE_SELECTION] After icon/Unicode cleanup: '%s' (length: %d)", file_path, #file_path)
  
  if file_path == "" then
    logger.debug("File path is empty after trimming")
    return nil
  end
  
  -- 尝试多种路径解析策略
  local paths_to_try = {}
  
  -- 1. 直接使用原路径
  table.insert(paths_to_try, file_path)
  
  -- 2. 展开路径（处理 ~ 等）
  local expanded_path = vim.fn.expand(file_path)
  if expanded_path ~= file_path then
    table.insert(paths_to_try, expanded_path)
  end
  
  -- 3. 如果是相对路径，尝试基于当前工作目录
  if not vim.startswith(file_path, '/') then
    local cwd = vim.loop.cwd()
    table.insert(paths_to_try, cwd .. '/' .. file_path)
  end
  
  -- 4. 如果是相对路径，尝试基于 HOME 目录
  if not vim.startswith(file_path, '/') then
    local home = vim.env.HOME or os.getenv('HOME')
    if home then
      table.insert(paths_to_try, home .. '/' .. file_path)
    end
  end
  
  -- 5. 尝试使用 vim.fn.findfile
  local found_file = vim.fn.findfile(file_path, '.;')
  if found_file ~= "" then
    table.insert(paths_to_try, vim.fn.fnamemodify(found_file, ':p'))
  end
  
  -- 尝试每个路径
  for i, path in ipairs(paths_to_try) do
    logger.debug("[PARSE_SELECTION] Trying path %d: '%s' (length: %d)", i, path, #path)
    
    -- Debug: Show path bytes
    local path_bytes = {}
    for j = 1, #path do
      table.insert(path_bytes, string.byte(path, j))
    end
    logger.debug("[PARSE_SELECTION] Path %d bytes: [%s]", i, table.concat(path_bytes, ", "))
    
    local stat = vim.loop.fs_stat(path)
    if stat then
      logger.debug("[PARSE_SELECTION] ✓ Successfully found file: '%s' (type: %s)", path, stat.type)
      return {
        path = path,
        start_line = nil,
        end_line = nil
      }
    else
      logger.debug("[PARSE_SELECTION] ✗ File not found: '%s'", path)
    end
  end
  
  logger.debug("[PARSE_SELECTION] ✗ File not found after trying %d paths for input '%s':", #paths_to_try, selection)
  logger.debug("[PARSE_SELECTION] Trimmed path: '%s'", file_path)
  logger.debug("[PARSE_SELECTION] Paths tried: %s", vim.inspect(paths_to_try))
  
  -- Validate that we have a clean file path
  if file_path == "" then
    logger.debug("[PARSE_SELECTION] File path empty after cleanup")
    return nil
  end
  
  -- Additional debugging: Show the cleaning process
  logger.debug("[PARSE_SELECTION] Cleaning result: '%s' -> '%s'", selection, file_path)
  
  M.handle_error(ErrorTypes.FILE_NOT_FOUND, { file_path = file_path })
  return nil
end

function M.parse_buffer_selection(selection)
  logger.debug("[PARSE_BUFFER] Raw input: '%s' (type: %s, length: %d)", 
    selection or "nil", type(selection), selection and #selection or 0)
    
  if not selection or selection == "" then
    logger.debug("[PARSE_BUFFER] Empty or nil buffer selection")
    return nil
  end
  
  -- Debug: Show raw bytes for debugging Unicode issues
  local byte_repr = {}
  for i = 1, math.min(#selection, 50) do
    table.insert(byte_repr, string.byte(selection, i))
  end
  logger.debug("[PARSE_BUFFER] Raw bytes: [%s]", table.concat(byte_repr, ", "))
  
  -- Remove file icons and Unicode spaces while preserving Chinese characters
  local cleaned = selection
  
  -- Remove specific Unicode spaces (exact patterns only)
  cleaned = cleaned:gsub("\226\128\130", "")  -- U+2002 EN SPACE
  cleaned = cleaned:gsub("\226\128\131", "")  -- U+2003 EM SPACE  
  cleaned = cleaned:gsub("\226\128\137", "")  -- U+2009 THIN SPACE
  cleaned = cleaned:gsub("\226\128\138", "")  -- U+200A HAIR SPACE
  cleaned = cleaned:gsub("\226\128\139", "")  -- U+200B ZERO WIDTH SPACE
  
  -- Remove specific icon characters (exact patterns only)
  cleaned = cleaned:gsub("\239\146\138", "")  -- Specific icon from logs
  cleaned = cleaned:gsub("\238\156\130", "")  -- Another specific icon
  
  -- Remove common file icons by specific known sequences (not ranges!)
  local common_icons = {
    "\238\156\128",  -- Specific icons
    "\238\156\129", 
    "\238\156\131", 
    "\238\156\132", 
    "\238\156\133", 
    "\238\156\134",
  }
  
  for _, icon in ipairs(common_icons) do
    cleaned = cleaned:gsub(icon, "")
  end
  
  -- Standard whitespace trimming
  cleaned = vim.trim(cleaned)
  
  logger.debug("[PARSE_BUFFER] After cleaning: '%s'", cleaned)
  
  -- Extract file path from buffer format: "[number] filepath:line" or "[number] filepath"
  -- Pattern matches: [digits] followed by optional whitespace, then capture the file path
  local file_path = cleaned:match("^%[%d+%]%s*(.+)$")
  
  if file_path then
    -- Remove line number if present (":number" at the end)
    file_path = file_path:gsub(":%d+$", "")
    file_path = vim.trim(file_path)
    logger.debug("[PARSE_BUFFER] Extracted file path: '%s'", file_path)
    
    -- Convert to absolute path
    if not vim.startswith(file_path, '/') then
      local cwd = vim.loop.cwd()
      file_path = cwd .. '/' .. file_path
      logger.debug("[PARSE_BUFFER] Converted to absolute path: '%s'", file_path)
    end
    
    return file_path
  else
    logger.warn("[PARSE_BUFFER] Failed to extract file path from: '%s'", cleaned)
    return nil
  end
end

function M.show_progress(current, total, message)
  vim.notify(
    string.format('%s: %d/%d', message, current, total),
    vim.log.levels.INFO,
    { replace = current > 1 }
  )
end

function M.show_final_result(success_count, total, item_type)
  local level = success_count == total and vim.log.levels.INFO or vim.log.levels.WARN
  vim.notify(
    string.format('完成: %d/%d 个%s成功发送到 Claude', success_count, total, item_type),
    level
  )
end

function M.auto_open_terminal()
  local term_ok, term = pcall(require, "claudecode.terminal")
  if term_ok and term.open then
    term.open()
  end
end

function M.handle_error(error_type, context)
  local handlers = {
    [ErrorTypes.DEPENDENCY_MISSING] = function(ctx)
      vim.notify(
        string.format('[claude-fzf] 缺少依赖: %s\n请安装: %s', 
          ctx.dependency, ctx.install_cmd),
        vim.log.levels.ERROR
      )
    end,
    
    [ErrorTypes.CONNECTION_FAILED] = function(ctx)
      vim.notify('[claude-fzf] Claude 连接失败，正在重试...', vim.log.levels.WARN)
    end,
    
    [ErrorTypes.INVALID_SELECTION] = function(ctx)
      vim.notify(
        string.format('[claude-fzf] 无效选择: %s', ctx.selection),
        vim.log.levels.WARN
      )
    end,
    
    [ErrorTypes.FILE_NOT_FOUND] = function(ctx)
      vim.notify(
        string.format('[claude-fzf] 文件未找到: %s', ctx.file_path),
        vim.log.levels.ERROR
      )
    end,
  }
  
  local handler = handlers[error_type]
  if handler then 
    handler(context) 
  else
    vim.notify(
      string.format('[claude-fzf] 未知错误类型: %s', error_type),
      vim.log.levels.ERROR
    )
  end
end

function M.is_available()
  local ok, _ = pcall(require, 'claudecode')
  return ok
end

function M.check_health()
  if not M.is_available() then
    return false, 'claudecode.nvim 未安装'
  end
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    return false, 'claudecode.nvim 加载失败'
  end
  
  if not claudecode.send_at_mention then
    return false, 'claudecode.nvim 版本过旧，缺少 send_at_mention 功能'
  end
  
  return true, 'claudecode.nvim 可用'
end

return M