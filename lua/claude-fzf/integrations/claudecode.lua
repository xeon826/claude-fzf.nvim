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
    -- Clean Unicode icons from grep results first
    local cleaned_line = M.parse_selection(line) or line
    
    -- Handle both formats: "file:line:content" and "file:line:column:content"
    local file, line_num, col_or_content, content = cleaned_line:match("^([^:]+):(%d+):(%d*):?(.*)$")
    
    if file and line_num then
      -- If col_or_content is a number, then content is the 4th capture, otherwise it's the 3rd
      local actual_content
      if content and content ~= "" then
        -- Format: file:line:column:content
        actual_content = content
      else
        -- Format: file:line:content (col_or_content is actually content)
        actual_content = col_or_content or ""
      end
      
      table.insert(file_selections, {
        file = file,
        line = tonumber(line_num),
        content = actual_content
      })
    else
      logger.warn("[GREP_PARSE] Failed to parse grep line: '%s'", line)
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
      
      -- Check if file exists
      local file_exists = vim.loop.fs_stat(file_path) ~= nil
      if not file_exists then
        logger.warn("[BUFFER_SELECTIONS] File does not exist: '%s'", file_path)
        M.handle_error(ErrorTypes.FILE_NOT_FOUND, { file_path = file_path })
      else
        logger.debug("[BUFFER_SELECTIONS] File exists: '%s'", file_path)
      end
      
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
  file_path = file_path:gsub("\238\152\139", "")  -- Icon from logs [238, 152, 139]
  file_path = file_path:gsub("\238\152\149", "")  -- Icon from logs [238, 152, 149] 
  file_path = file_path:gsub("\238\152\134", "")  -- Icon from logs [238, 152, 134]
  
  -- Remove common file icons by specific known sequences (not dangerous ranges!)
  -- These are Nerd Font file type icons commonly used by nvim-web-devicons, starship, zsh, etc.
  -- Unicode range U+E000-U+F8FF (Private Use Area) encoded as UTF-8
  local common_icons = {
    -- File type icons (\238\156\xxx range - U+E700-U+E7FF)
    "\238\156\128", "\238\156\129", "\238\156\130", "\238\156\131", "\238\156\132", "\238\156\133", "\238\156\134", "\238\156\135",
    "\238\156\136", "\238\156\137", "\238\156\138", "\238\156\139", "\238\156\140", "\238\156\141", "\238\156\142", "\238\156\143",
    "\238\156\144", "\238\156\145", "\238\156\146", "\238\156\147", "\238\156\148", "\238\156\149", "\238\156\150", "\238\156\151",
    "\238\156\152", "\238\156\153", "\238\156\154", "\238\156\155", "\238\156\156", "\238\156\157", "\238\156\158", "\238\156\159",
    "\238\156\160", "\238\156\161", "\238\156\162", "\238\156\163", "\238\156\164", "\238\156\165", "\238\156\166", "\238\156\167",
    "\238\156\168", "\238\156\169", "\238\156\170", "\238\156\171", "\238\156\172", "\238\156\173", "\238\156\174", "\238\156\175",
    "\238\156\176", "\238\156\177", "\238\156\178", "\238\156\179", "\238\156\180", "\238\156\181", "\238\156\182", "\238\156\183",
    "\238\156\184", "\238\156\185", "\238\156\186", "\238\156\187", "\238\156\188", "\238\156\189", "\238\156\190", "\238\156\191",
    
    -- More file icons (\238\152\xxx range - U+E600-U+E6FF)  
    "\238\152\128", "\238\152\129", "\238\152\130", "\238\152\131", "\238\152\132", "\238\152\133", "\238\152\134", "\238\152\135",
    "\238\152\136", "\238\152\137", "\238\152\138", "\238\152\139", "\238\152\140", "\238\152\141", "\238\152\142", "\238\152\143",
    "\238\152\144", "\238\152\145", "\238\152\146", "\238\152\147", "\238\152\148", "\238\152\149", "\238\152\150", "\238\152\151",
    "\238\152\152", "\238\152\153", "\238\152\154", "\238\152\155", "\238\152\156", "\238\152\157", "\238\152\158", "\238\152\159",
    "\238\152\160", "\238\152\161", "\238\152\162", "\238\152\163", "\238\152\164", "\238\152\165", "\238\152\166", "\238\152\167",
    "\238\152\168", "\238\152\169", "\238\152\170", "\238\152\171", "\238\152\172", "\238\152\173", "\238\152\174", "\238\152\175",
    "\238\152\176", "\238\152\177", "\238\152\178", "\238\152\179", "\238\152\180", "\238\152\181", "\238\152\182", "\238\152\183",
    "\238\152\184", "\238\152\185", "\238\152\186", "\238\152\187", "\238\152\188", "\238\152\189", "\238\152\190", "\238\152\191",
    
    -- DevIcons range (\238\153\xxx range - U+E800-U+E8FF)
    "\238\153\128", "\238\153\129", "\238\153\130", "\238\153\131", "\238\153\132", "\238\153\133", "\238\153\134", "\238\153\135",
    "\238\153\136", "\238\153\137", "\238\153\138", "\238\153\139", "\238\153\140", "\238\153\141", "\238\153\142", "\238\153\143",
    "\238\153\144", "\238\153\145", "\238\153\146", "\238\153\147", "\238\153\148", "\238\153\149", "\238\153\150", "\238\153\151",
    "\238\153\152", "\238\153\153", "\238\153\154", "\238\153\155", "\238\153\156", "\238\153\157", "\238\153\158", "\238\153\159",
    
    -- Font Awesome icons (\239\xxx\xxx range - U+F000-U+F8FF)
    "\239\128\128", "\239\128\129", "\239\128\130", "\239\128\131", "\239\128\132", "\239\128\133", "\239\128\134", "\239\128\135",
    "\239\129\128", "\239\129\129", "\239\129\130", "\239\129\131", "\239\129\132", "\239\129\133", "\239\129\134", "\239\129\135",
    "\239\130\128", "\239\130\129", "\239\130\130", "\239\130\131", "\239\130\132", "\239\130\133", "\239\130\134", "\239\130\135",
    "\239\131\128", "\239\131\129", "\239\131\130", "\239\131\131", "\239\131\132", "\239\131\133", "\239\131\134", "\239\131\135",
    
    -- Material Design Icons (\238\180\xxx range)
    "\238\180\128", "\238\180\129", "\238\180\130", "\238\180\131", "\238\180\132", "\238\180\133", "\238\180\134", "\238\180\135",
    "\238\180\136", "\238\180\137", "\238\180\138", "\238\180\139", "\238\180\140", "\238\180\141", "\238\180\142", "\238\180\143",
    
    -- Octicons (\238\160\xxx range)
    "\238\160\128", "\238\160\129", "\238\160\130", "\238\160\131", "\238\160\132", "\238\160\133", "\238\160\134", "\238\160\135",
    "\238\160\136", "\238\160\137", "\238\160\138", "\238\160\139", "\238\160\140", "\238\160\141", "\238\160\142", "\238\160\143",
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
  
  -- Use the same comprehensive icon cleanup as parse_selection
  local cleaned = M.parse_selection(selection) or selection
  
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