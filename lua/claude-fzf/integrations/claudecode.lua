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
      
      -- 只在开始时显示进度通知
      if config.should_show_progress() and i == 1 then
        notify.progress("Sending to Claude...", { id = 'claude_send_progress' })
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
        logger.error("Failed to send %s: %s", file_info.path, err or "unknown error")
        notify.error(
          string.format('Send failed: %s - %s', 
            file_info.path, err or "unknown error")
        )
      end
    else
      logger.warn("[SEND_SELECTIONS] Invalid selection: '%s' (trimmed: '%s')", selection, vim.trim(selection))
      logger.debug("[SEND_SELECTIONS] Selection bytes: [%s]", 
        table.concat({string.byte(selection, 1, #selection)}, ", "))
      M.handle_error(ErrorTypes.INVALID_SELECTION, { selection = selection })
    end
  end
  
  M.show_final_result(success_count, total, "files")
  
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
    logger.debug("[GREP_PARSE] Processing line: '%s'", line)
    
    -- Clean Unicode icons from grep results first
    local cleaned_line = line
    
    -- Safe Unicode cleanup function that preserves Chinese characters
    -- Based on UTF-8 encoding research and best practices
    local function remove_icons_safely(str)
      -- Remove characters using proper UTF-8 iteration to avoid corrupting Chinese text
      local result = {}
      local i = 1
      
      while i <= #str do
        local byte1 = string.byte(str, i)
        local char_len = 1
        local codepoint = nil
        
        -- Determine UTF-8 character length and decode codepoint
        if byte1 < 128 then
          -- ASCII character (1 byte)
          codepoint = byte1
          char_len = 1
        elseif byte1 >= 194 and byte1 <= 223 then
          -- 2-byte UTF-8 character
          if i + 1 <= #str then
            local byte2 = string.byte(str, i + 1)
            codepoint = ((byte1 - 192) * 64) + (byte2 - 128)
            char_len = 2
          end
        elseif byte1 >= 224 and byte1 <= 239 then
          -- 3-byte UTF-8 character
          if i + 2 <= #str then
            local byte2 = string.byte(str, i + 1)
            local byte3 = string.byte(str, i + 2)
            codepoint = ((byte1 - 224) * 4096) + ((byte2 - 128) * 64) + (byte3 - 128)
            char_len = 3
          end
        elseif byte1 >= 240 and byte1 <= 244 then
          -- 4-byte UTF-8 character
          if i + 3 <= #str then
            local byte2 = string.byte(str, i + 1)
            local byte3 = string.byte(str, i + 2)
            local byte4 = string.byte(str, i + 3)
            codepoint = ((byte1 - 240) * 262144) + ((byte2 - 128) * 4096) + ((byte3 - 128) * 64) + (byte4 - 128)
            char_len = 4
          end
        end
        
        -- Filter out unwanted characters while preserving Chinese and other legitimate text
        local should_keep = true
        if codepoint then
          -- Remove Private Use Area characters (Nerd Font icons)
          if (codepoint >= 0xE000 and codepoint <= 0xF8FF) or
             (codepoint >= 0xF0000 and codepoint <= 0xFFFFD) or
             (codepoint >= 0x100000 and codepoint <= 0x10FFFD) then
            should_keep = false
          -- Remove specific Unicode space characters  
          elseif codepoint >= 0x2000 and codepoint <= 0x200F then
            should_keep = false
          -- Remove other control characters except common whitespace
          elseif codepoint < 32 and codepoint ~= 9 and codepoint ~= 10 and codepoint ~= 13 then
            should_keep = false
          end
        end
        
        if should_keep and char_len > 0 then
          table.insert(result, string.sub(str, i, i + char_len - 1))
        end
        
        i = i + char_len
      end
      
      return table.concat(result)
    end
    
    cleaned_line = remove_icons_safely(cleaned_line)
    
    cleaned_line = vim.trim(cleaned_line)
    
    logger.debug("[GREP_PARSE] After cleanup: '%s'", cleaned_line)
    
    -- Parse ripgrep format: "file:line:column:content" or "file:line:content"
    -- First extract file path by finding the pattern before first number
    local file_path, rest = cleaned_line:match("^([^:]+):(%d+.*)$")
    
    if file_path and rest then
      -- Now parse the rest which should be "line:column:content" or "line:content"
      local line_num, col_num, content = rest:match("^(%d+):(%d+):(.*)$")
      
      if not line_num then
        -- Try format without column: "line:content"
        line_num, content = rest:match("^(%d+):(.*)$")
        col_num = nil
      end
      
      if line_num then
        logger.debug("[GREP_PARSE] Parsed - file: '%s', line: %s, column: %s", 
          file_path, line_num, col_num or "none")
        
        -- Convert relative path to absolute if needed
        local abs_file_path = file_path
        if not vim.startswith(file_path, '/') then
          -- Get current working directory from fzf context or vim
          local cwd = vim.loop.cwd()
          abs_file_path = cwd .. '/' .. file_path
          logger.debug("[GREP_PARSE] Converted relative path: '%s' -> '%s'", file_path, abs_file_path)
        end
        
        -- Validate file exists before adding to selections
        local file_exists = vim.loop.fs_stat(abs_file_path) ~= nil
        if file_exists then
          table.insert(file_selections, {
            file = abs_file_path,
            line = tonumber(line_num),
            content = content or ""
          })
          logger.debug("[GREP_PARSE] Added file to selections: '%s'", abs_file_path)
        else
          logger.warn("[GREP_PARSE] File does not exist: '%s'", abs_file_path)
        end
      else
        logger.warn("[GREP_PARSE] Failed to parse line/content from: '%s'", rest)
      end
    else
      logger.warn("[GREP_PARSE] Failed to parse grep line: '%s'", cleaned_line)
    end
  end
  
  total = #file_selections
  
  for i, selection in ipairs(file_selections) do
    -- 只在开始时显示进度通知
    if config.should_show_progress() and i == 1 then
      notify.progress("Sending search results to Claude...", { id = 'claude_grep_progress' })
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
      notify.error(
        string.format('Send failed: %s:%d - %s', 
          selection.file, selection.line, err or "unknown error")
      )
    end
  end
  
  M.show_final_result(success_count, total, "search results")
  
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
      
      -- 只在开始时显示进度通知
      if config.should_show_progress() and i == 1 then
        notify.progress("Sending buffers to Claude...", { id = 'claude_buffer_progress' })
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
        logger.error("[BUFFER_SELECTIONS] Failed to send %s: %s", file_path, err or "unknown error")
        notify.error(
          string.format('Send failed: %s - %s', 
            file_path, err or "unknown error")
        )
      end
    else
      logger.warn("[BUFFER_SELECTIONS] Failed to parse buffer selection: '%s'", selection)
      M.handle_error(ErrorTypes.INVALID_SELECTION, { selection = selection })
    end
  end
  
  logger.debug("[BUFFER_SELECTIONS] Completed: %d/%d successful", success_count, total)
  M.show_final_result(success_count, total, "buffers")
  
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

function M.parse_selection(selection, opts)
  opts = opts or {}
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
  
  -- Use the same safe Unicode cleanup function as in send_grep_results
  local function remove_icons_safely(str)
    local result = {}
    local i = 1
    
    while i <= #str do
      local byte1 = string.byte(str, i)
      local char_len = 1
      local codepoint = nil
      
      -- Determine UTF-8 character length and decode codepoint
      if byte1 < 128 then
        codepoint = byte1
        char_len = 1
      elseif byte1 >= 194 and byte1 <= 223 then
        if i + 1 <= #str then
          local byte2 = string.byte(str, i + 1)
          codepoint = ((byte1 - 192) * 64) + (byte2 - 128)
          char_len = 2
        end
      elseif byte1 >= 224 and byte1 <= 239 then
        if i + 2 <= #str then
          local byte2 = string.byte(str, i + 1)
          local byte3 = string.byte(str, i + 2)
          codepoint = ((byte1 - 224) * 4096) + ((byte2 - 128) * 64) + (byte3 - 128)
          char_len = 3
        end
      elseif byte1 >= 240 and byte1 <= 244 then
        if i + 3 <= #str then
          local byte2 = string.byte(str, i + 1)
          local byte3 = string.byte(str, i + 2)
          local byte4 = string.byte(str, i + 3)
          codepoint = ((byte1 - 240) * 262144) + ((byte2 - 128) * 4096) + ((byte3 - 128) * 64) + (byte4 - 128)
          char_len = 4
        end
      end
      
      -- Filter out unwanted characters while preserving Chinese and other legitimate text
      local should_keep = true
      if codepoint then
        -- Remove Private Use Area characters (Nerd Font icons)
        if (codepoint >= 0xE000 and codepoint <= 0xF8FF) or
           (codepoint >= 0xF0000 and codepoint <= 0xFFFFD) or
           (codepoint >= 0x100000 and codepoint <= 0x10FFFD) then
          should_keep = false
        -- Remove specific Unicode space characters  
        elseif codepoint >= 0x2000 and codepoint <= 0x200F then
          should_keep = false
        -- Remove other control characters except common whitespace
        elseif codepoint < 32 and codepoint ~= 9 and codepoint ~= 10 and codepoint ~= 13 then
          should_keep = false
        end
      end
      
      if should_keep and char_len > 0 then
        table.insert(result, string.sub(str, i, i + char_len - 1))
      end
      
      i = i + char_len
    end
    
    return table.concat(result)
  end
  
  local file_path = remove_icons_safely(selection)
  
  file_path = vim.trim(file_path)
  if opts.is_buffer then
    -- For buffers, remove flags like '#' (alt) or '%' (current) from the beginning.
    file_path = file_path:gsub("^[#%%]%s*", "")
    file_path = vim.trim(file_path)
  end
  
  logger.debug("[PARSE_SELECTION] After icon/Unicode cleanup: '%s' (length: %d)", file_path, #file_path)

  local line_info = {
    path = file_path,
    start_line = nil,
    end_line = nil
  }

  -- Separate the path from line/col numbers. Handles `path:line`.
  -- This regex is intentionally greedy on the path part to handle Windows paths with colons.
  logger.debug("[PARSE_SELECTION] Attempting to separate line number from: '%s'", line_info.path)
  local matched_path, matched_line = line_info.path:match("^(.*):(%d+)$")
  logger.debug("[PARSE_SELECTION] Regex match result: matched_path='%s', matched_line='%s'", matched_path or "nil", matched_line or "nil")
  
  if matched_path and #matched_path > 0 then
    -- This is a simple heuristic to avoid misinterpreting a Windows drive letter (e.g., "C:") as a path and a line number.
    if not (matched_path:match("^[a-zA-Z]$") and vim.fn.has('win32')) then
      logger.debug("[PARSE_SELECTION] Detected path and line number: '%s' and '%s'", matched_path, matched_line)
      line_info.path = matched_path
      line_info.start_line = tonumber(matched_line)
      line_info.end_line = tonumber(matched_line)
      logger.debug("[PARSE_SELECTION] After line separation: path='%s', line=%s", line_info.path, line_info.start_line)
    else
      logger.debug("[PARSE_SELECTION] Path '%s' looks like a Windows drive letter, not splitting.", matched_path)
    end
  else
    logger.debug("[PARSE_SELECTION] No line number pattern found in path: '%s'", line_info.path)
  end

  if line_info.path == "" then
    logger.debug("File path is empty after trimming and parsing")
    return nil
  end

  -- 尝试多种路径解析策略
  local paths_to_try = {}

  -- 1. 直接使用解析后的路径
  table.insert(paths_to_try, line_info.path)
  
  -- 2. 展开路径（处理 ~ 等）
  local expanded_path = vim.fn.expand(line_info.path)
  if expanded_path ~= line_info.path then
    table.insert(paths_to_try, expanded_path)
  end
  
  -- 3. 如果是相对路径，尝试基于当前工作目录
  if not vim.startswith(line_info.path, '/') then
    local cwd = vim.loop.cwd()
    table.insert(paths_to_try, cwd .. '/' .. line_info.path)
  end
  
  -- 4. 如果是相对路径，尝试基于 HOME 目录
  if not vim.startswith(line_info.path, '/') then
    local home = vim.env.HOME or os.getenv('HOME')
    if home then
      table.insert(paths_to_try, home .. '/' .. line_info.path)
    end
  end
  
  -- 5. 尝试使用 vim.fn.findfile
  local found_file = vim.fn.findfile(line_info.path, '.;')
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
        start_line = line_info.start_line,
        end_line = line_info.end_line
      }
    else
      logger.debug("[PARSE_SELECTION] ✗ File not found: '%s'", path)
    end
  end
  
  logger.debug("[PARSE_SELECTION] ✗ File not found after trying %d paths for input '%s':", #paths_to_try, selection)
  logger.debug("[PARSE_SELECTION] Trimmed path: '%s'", line_info.path)
  logger.debug("[PARSE_SELECTION] Paths tried: %s", vim.inspect(paths_to_try))
  
  -- Validate that we have a clean file path
  if line_info.path == "" then
    logger.debug("[PARSE_SELECTION] File path empty after cleanup")
    return nil
  end
  
  -- Additional debugging: Show the cleaning process
  logger.debug("[PARSE_SELECTION] Cleaning result: '%s' -> '%s'", selection, line_info.path)
  
  M.handle_error(ErrorTypes.FILE_NOT_FOUND, { file_path = line_info.path })
  return nil
end

function M.parse_buffer_selection(selection)
  logger.debug("[PARSE_BUFFER] Raw input: '%s' (type: %s, length: %d)",
    selection or "nil", type(selection), selection and #selection or 0)

  if not selection or selection == "" then
    logger.debug("[PARSE_BUFFER] Empty or nil buffer selection")
    return nil
  end

  -- The fzf-lua buffer format is typically `[bufnr] [flags] [icon] path:linenr`
  -- We want to strip the `[bufnr]` part and delegate the rest to the main file parser.
  -- This regex captures the part after `[<number>]` and optional whitespace.
  local file_part = selection:match("^%[%d+%]%s*(.*)$") or selection

  logger.debug("[PARSE_BUFFER] Stripped buffer number, passing to M.parse_selection: '%s'", file_part)

  -- Delegate to the more robust file parser
  local file_info = M.parse_selection(file_part, { is_buffer = true })

  if file_info and file_info.path then
    logger.debug("[PARSE_BUFFER] Successfully parsed with M.parse_selection, result: '%s'", file_info.path)
    -- The buffer selection doesn't imply a line range, so we just return the path.
    return file_info.path
  else
    logger.warn("[PARSE_BUFFER] M.parse_selection failed to find a valid file for: '%s'", file_part)
    return nil
  end
end

-- 使用新的通知服务
local notify = require('claude-fzf.notify')

function M.show_progress(current, total, message)
  notify.show_progress(current, total, message, 'claude_fzf_progress')
end

function M.show_final_result(success_count, total, item_type)
  notify.show_final_result(success_count, total, item_type)
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
      notify.error(
        string.format('Missing dependency: %s\nPlease install: %s', 
          ctx.dependency, ctx.install_cmd)
      )
    end,
    
    [ErrorTypes.CONNECTION_FAILED] = function(ctx)
      notify.warning('Claude connection failed, retrying...')
    end,
    
    [ErrorTypes.INVALID_SELECTION] = function(ctx)
      notify.warning(
        string.format('Invalid selection: %s', ctx.selection)
      )
    end,
    
    [ErrorTypes.FILE_NOT_FOUND] = function(ctx)
      notify.error(
        string.format('File not found: %s', ctx.file_path)
      )
    end,
  }
  
  local handler = handlers[error_type]
  if handler then 
    handler(context) 
  else
    notify.error(
      string.format('Unknown error type: %s', error_type)
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
