local M = {}
local logger = require('claude-fzf.logger')
local notify = require('claude-fzf.notify')

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
    return false, "claudecode.nvim not found"
  end
  
  logger.debug("claudecode.nvim loaded successfully")
  
  local config = require('claude-fzf.config')
  local claude_opts = config.get_claude_opts()
  
  -- Prepare clean file paths for claudecode.nvim batch sending
  local clean_paths = {}
  local total = #selections
  
  for i, selection in ipairs(selections) do
    logger.debug("Processing selection %d/%d: %s", i, total, selection)
    
    local file_info = M.parse_selection(selection)
    if file_info then
      logger.debug("Parsed file info: %s", vim.inspect(file_info))
      table.insert(clean_paths, file_info.path)
    else
      logger.warn("[SEND_SELECTIONS] Invalid selection: '%s' (trimmed: '%s')", selection, vim.trim(selection))
      logger.debug("[SEND_SELECTIONS] Selection bytes: [%s]", 
        table.concat({string.byte(selection, 1, #selection)}, ", "))
      M.handle_error(ErrorTypes.INVALID_SELECTION, { selection = selection })
    end
  end
  
  local success_count = 0
  if #clean_paths > 0 then
    logger.debug("Using claudecode.nvim send_at_mention for %d files", #clean_paths)
    
    -- Check for duplicate paths before sending
    local unique_paths = {}
    local seen_paths = {}
    local duplicate_count = 0
    
    for _, file_path in ipairs(clean_paths) do
      -- Convert to absolute path for comparison
      local abs_path = vim.fn.fnamemodify(file_path, ':p')
      if not seen_paths[abs_path] then
        seen_paths[abs_path] = true
        table.insert(unique_paths, file_path)
        logger.debug("Added unique path: %s -> %s", file_path, abs_path)
      else
        duplicate_count = duplicate_count + 1
        logger.warn("Duplicate path detected: %s -> %s", file_path, abs_path)
      end
    end
    
    if duplicate_count > 0 then
      logger.warn("Found %d duplicate paths, sending %d unique files", duplicate_count, #unique_paths)
    end
    
    -- Send each file individually using send_at_mention
    for i, file_path in ipairs(unique_paths) do
      logger.debug("Sending file %d/%d: %s", i, #unique_paths, file_path)
      
      local success, err = logger.safe_call(
        claudecode.send_at_mention,
        string.format("send_at_mention(%s)", file_path),
        file_path,
        nil,
        nil,
        claude_opts.source_tag or "claude-fzf-integration"
      )
      
      if success then
        success_count = success_count + 1
        logger.debug("Successfully sent: %s", file_path)
        
        -- Add delay to prevent Claude Code CLI from dropping files in rapid succession
        vim.wait(100)
      else
        logger.error("Failed to send %s: %s", file_path, err or "unknown error")
        notify.error(
          string.format('Send failed: %s - %s', file_path, err or "unknown error")
        )
      end
    end
  end
  
  M.show_final_result(success_count, total, "files")
  
  if config.should_auto_open_terminal() and success_count > 0 then
    M.auto_open_terminal()
  end
  
  return success_count > 0
end

-- Copy selections to clipboard with @ prefix
function M.copy_selections_to_clipboard(selections, opts)
  opts = opts or {}
  logger.info("Copying %d selections to clipboard", #selections)
  logger.debug("Selections: %s", vim.inspect(selections))
  logger.debug("Options: %s", vim.inspect(opts))
  
  if not selections or #selections == 0 then
    notify.info('No items selected')
    return false, "No items selected"
  end
  
  -- Prepare clean file paths with @ prefix
  local clipboard_content = {}
  local total = #selections
  local success_count = 0
  
  for i, selection in ipairs(selections) do
    logger.debug("Processing selection %d/%d for clipboard: %s", i, total, selection)
    
    local file_info = M.parse_selection(selection)
    if file_info then
      logger.debug("Parsed file info for clipboard: %s", vim.inspect(file_info))
      -- Format with @ prefix like Claude sends
      local formatted_path = "@" .. file_info.path
      if file_info.start_line then
        formatted_path = formatted_path .. ":" .. file_info.start_line
        if file_info.end_line and file_info.end_line ~= file_info.start_line then
          formatted_path = formatted_path .. "-" .. file_info.end_line
        end
      end
      table.insert(clipboard_content, formatted_path)
      success_count = success_count + 1
    else
      logger.warn("[COPY_CLIPBOARD] Invalid selection: '%s'", selection)
      notify.warning(string.format('Invalid selection: %s', selection))
    end
  end
  
  if #clipboard_content > 0 then
    -- Join all paths with spaces instead of newlines
    local clipboard_text = table.concat(clipboard_content, " ")
    logger.debug("Clipboard content: %s", clipboard_text)
    
    -- Copy to system clipboard
    vim.fn.setreg('+', clipboard_text)
    
    -- Also copy to unnamed register for easy pasting
    vim.fn.setreg('"', clipboard_text)
    
    logger.info("Successfully copied %d items to clipboard", success_count)
    notify.info(string.format('Copied %d file%s to clipboard with @ prefix', 
      success_count, success_count == 1 and "" or "s"))
    
    return true, success_count
  else
    logger.error("No valid selections to copy")
    notify.error("No valid selections to copy")
    return false, "No valid selections"
  end
end

-- Copy grep results to clipboard with @ prefix
function M.copy_grep_results_to_clipboard(selections, opts)
  opts = opts or {}
  logger.info("Copying %d grep results to clipboard", #selections)
  
  if not selections or #selections == 0 then
    notify.info('No items selected')
    return false, "No items selected"
  end
  
  local clipboard_content = {}
  local success_count = 0
  
  for i, selection in ipairs(selections) do
    logger.debug("Processing grep result %d/%d for clipboard: %s", i, #selections, selection)
    -- Parse grep result format using the same logic as send_grep_results
    local file_info = M.parse_grep_selection and M.parse_grep_selection(selection) or nil
    if file_info then
      local formatted_path = "@" .. file_info.path
      if file_info.start_line then
        formatted_path = formatted_path .. ":" .. file_info.start_line
      end
      table.insert(clipboard_content, formatted_path)
      success_count = success_count + 1
    else
      logger.warn("[COPY_GREP_CLIPBOARD] Invalid grep result: '%s'", selection)
    end
  end
  
  if #clipboard_content > 0 then
    local clipboard_text = table.concat(clipboard_content, " ")
    vim.fn.setreg('+', clipboard_text)
    vim.fn.setreg('"', clipboard_text)
    
    logger.info("Successfully copied %d grep results to clipboard", success_count)
    notify.info(string.format('Copied %d grep result%s to clipboard with @ prefix', 
      success_count, success_count == 1 and "" or "s"))
    
    return true, success_count
  else
    notify.error("No valid grep results to copy")
    return false, "No valid selections"
  end
end

-- Copy buffer selections to clipboard with @ prefix  
function M.copy_buffer_selections_to_clipboard(selections, opts)
  opts = opts or {}
  logger.info("Copying %d buffer selections to clipboard", #selections)
  
  if not selections or #selections == 0 then
    notify.info('No items selected')
    return false, "No items selected"
  end
  
  local clipboard_content = {}
  local success_count = 0
  
  for i, selection in ipairs(selections) do
    logger.debug("Processing buffer selection %d/%d for clipboard: %s", i, #selections, selection)
    
    local parsed = M.parse_buffer_selection(selection)
    if parsed then
      -- parse_buffer_selection currently returns a string path; accept both string and table
      local path = type(parsed) == 'string' and parsed or parsed.path
      local start_line = type(parsed) == 'table' and parsed.start_line or nil
      local formatted_path = "@" .. path
      if start_line then
        formatted_path = formatted_path .. ":" .. start_line
      end
      table.insert(clipboard_content, formatted_path)
      success_count = success_count + 1
    else
      logger.warn("[COPY_BUFFER_CLIPBOARD] Invalid buffer selection: '%s'", selection)
    end
  end
  
  if #clipboard_content > 0 then
    local clipboard_text = table.concat(clipboard_content, " ")
    vim.fn.setreg('+', clipboard_text)
    vim.fn.setreg('"', clipboard_text)
    
    logger.info("Successfully copied %d buffer selections to clipboard", success_count)
    notify.info(string.format('Copied %d buffer%s to clipboard with @ prefix', 
      success_count, success_count == 1 and "" or "s"))
    
    return true, success_count
  else
    notify.error("No valid buffer selections to copy")
    return false, "No valid selections"
  end
end

-- Parse a single ripgrep/fzf-lua grep selection line into path and line
-- Returns a table: { path = <absolute or resolved path>, start_line = <number>, end_line = <number> }
function M.parse_grep_selection(line)
  if not line or line == '' then return nil end

  -- Safe Unicode cleanup (keep CJK, remove Nerd Font icons and special spaces)
  local function remove_icons_safely(str)
    local result, i = {}, 1
    while i <= #str do
      local b1 = string.byte(str, i)
      local len, cp = 1, nil
      if b1 < 128 then cp, len = b1, 1
      elseif b1 >= 194 and b1 <= 223 then local b2=string.byte(str,i+1); cp=((b1-192)*64)+(b2-128); len=2
      elseif b1 >= 224 and b1 <= 239 then local b2=string.byte(str,i+1); local b3=string.byte(str,i+2); cp=((b1-224)*4096)+((b2-128)*64)+(b3-128); len=3
      elseif b1 >= 240 and b1 <= 244 then local b2=string.byte(str,i+1); local b3=string.byte(str,i+2); local b4=string.byte(str,i+3); cp=((b1-240)*262144)+((b2-128)*4096)+((b3-128)*64)+(b4-128); len=4 end
      local keep = true
      if cp then
        if (cp >= 0xE000 and cp <= 0xF8FF) or (cp >= 0xF0000 and cp <= 0xFFFFD) or (cp >= 0x100000 and cp <= 0x10FFFD) then
          keep = false
        elseif cp >= 0x2000 and cp <= 0x200F then
          keep = false
        elseif cp < 32 and cp ~= 9 and cp ~= 10 and cp ~= 13 then
          keep = false
        end
      end
      if keep and len > 0 then table.insert(result, string.sub(str, i, i+len-1)) end
      i = i + len
    end
    return table.concat(result)
  end

  line = remove_icons_safely(vim.trim(line))

  -- Extract file path before first numeric field, supports formats:
  -- path:line:col:content or path:line:content
  local file_path, rest = line:match('^([^:]+):(%d+.*)$')
  if not file_path or not rest then return nil end

  local line_num, col_num, content = rest:match('^(%d+):(%d+):(.*)$')
  if not line_num then line_num, content = rest:match('^(%d+):(.*)$') end
  if not line_num then return nil end

  -- Resolve file path using strategies similar to parse_selection
  local info = { path = vim.trim(file_path), start_line = tonumber(line_num), end_line = tonumber(line_num) }
  if info.path == '' then return nil end

  local paths = { info.path }
  local expanded = vim.fn.expand(info.path)
  if expanded ~= info.path then table.insert(paths, expanded) end
  if not vim.startswith(info.path, '/') then
    local cwd = vim.loop.cwd()
    table.insert(paths, cwd .. '/' .. info.path)
    local home = vim.env.HOME or os.getenv('HOME')
    if home then table.insert(paths, home .. '/' .. info.path) end
  end
  local found = vim.fn.findfile(info.path, '.;')
  if found ~= '' then table.insert(paths, vim.fn.fnamemodify(found, ':p')) end

  for _, p in ipairs(paths) do
    local st = vim.loop.fs_stat(p)
    if st then
      info.path = p
      return info
    end
  end

  return info -- return best-effort even if fs_stat failed (clipboard still useful)
end

function M.send_grep_results(selections, opts)
  opts = opts or {}
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    M.handle_error(ErrorTypes.DEPENDENCY_MISSING, {
      dependency = 'claudecode.nvim',
      install_cmd = 'lazy.nvim: { "coder/claudecode.nvim" }'
    })
    return false, "claudecode.nvim not found"
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
    -- Progress notifications disabled - only show completion notification
    
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
    return false, "claudecode.nvim not found"
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
      
      -- Progress notifications disabled - only show completion notification
      
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

        -- Add delay to prevent Claude Code CLI from dropping files in rapid succession
        vim.wait(100)
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
  
  -- First, remove Git status characters (?, M, A, D, R, C, U, !) from the beginning
  local function remove_git_status_prefix(str)
    -- Common Git status prefixes: ? (untracked), M (modified), A (added), D (deleted), 
    -- R (renamed), C (copied), U (unmerged), ! (ignored)
    -- Match Git status character followed by any whitespace (including Unicode spaces)
    local cleaned = str
    
    -- First try to match Git status character followed by Unicode or regular spaces
    local git_pattern = "^([?MADRCUI!])(.*)$"
    local git_char, rest = str:match(git_pattern)
    
    if git_char and rest then
      -- Remove leading whitespace using the same safe method as Unicode cleanup
      local i = 1
      while i <= #rest do
        local byte1 = string.byte(rest, i)
        local char_len = 1
        local codepoint = nil
        
        -- Determine UTF-8 character length and decode codepoint
        if byte1 < 128 then
          codepoint = byte1
          char_len = 1
        elseif byte1 >= 194 and byte1 <= 223 then
          if i + 1 <= #rest then
            local byte2 = string.byte(rest, i + 1)
            codepoint = ((byte1 - 192) * 64) + (byte2 - 128)
            char_len = 2
          end
        elseif byte1 >= 224 and byte1 <= 239 then
          if i + 2 <= #rest then
            local byte2 = string.byte(rest, i + 1)
            local byte3 = string.byte(rest, i + 2)
            codepoint = ((byte1 - 224) * 4096) + ((byte2 - 128) * 64) + (byte3 - 128)
            char_len = 3
          end
        elseif byte1 >= 240 and byte1 <= 244 then
          if i + 3 <= #rest then
            local byte2 = string.byte(rest, i + 1)
            local byte3 = string.byte(rest, i + 2)
            local byte4 = string.byte(rest, i + 3)
            codepoint = ((byte1 - 240) * 262144) + ((byte2 - 128) * 4096) + ((byte3 - 128) * 64) + (byte4 - 128)
            char_len = 4
          end
        end
        
        -- Check if this is a space/whitespace character to skip
        local is_space = false
        if codepoint then
          -- Regular whitespace characters
          if codepoint == 32 or codepoint == 9 or codepoint == 10 or codepoint == 13 then
            is_space = true
          -- Unicode space characters
          elseif codepoint >= 0x2000 and codepoint <= 0x200F then
            is_space = true
          end
        end
        
        if not is_space then
          -- Found non-space character, take the rest of the string
          cleaned = string.sub(rest, i)
          break
        end
        
        i = i + char_len
      end
      
      if cleaned ~= str then
        logger.debug("[PARSE_SELECTION] Removed Git status prefix: '%s' -> '%s'", str, cleaned)
      end
    end
    
    return cleaned
  end
  
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
  
  -- Apply Git status cleanup first, then Unicode cleanup
  local file_path = remove_git_status_prefix(selection)
  file_path = remove_icons_safely(file_path)
  
  file_path = vim.trim(file_path)
  if opts.is_buffer then
    -- For buffers, remove flags like 'a' (active), '#' (alt), '%' (current), 'h' (hidden), etc.
    -- Also handle Unicode spaces that might surround these flags
    -- Match any combination of buffer flags with optional Unicode spaces
    file_path = file_path:gsub("^[%s ]*[a#%%h]+[%s ]*", "")
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

  -- Try multiple path resolution strategies
  local paths_to_try = {}

  -- 1. Use parsed path directly
  table.insert(paths_to_try, line_info.path)
  
  -- 2. Expand path (handle ~ etc.)
  local expanded_path = vim.fn.expand(line_info.path)
  if expanded_path ~= line_info.path then
    table.insert(paths_to_try, expanded_path)
  end
  
  -- 3. If relative path, try based on current working directory
  if not vim.startswith(line_info.path, '/') then
    local cwd = vim.loop.cwd()
    table.insert(paths_to_try, cwd .. '/' .. line_info.path)
  end
  
  -- 4. If relative path, try based on HOME directory
  if not vim.startswith(line_info.path, '/') then
    local home = vim.env.HOME or os.getenv('HOME')
    if home then
      table.insert(paths_to_try, home .. '/' .. line_info.path)
    end
  end
  
  -- 5. Try using vim.fn.findfile
  local found_file = vim.fn.findfile(line_info.path, '.;')
  if found_file ~= "" then
    table.insert(paths_to_try, vim.fn.fnamemodify(found_file, ':p'))
  end
  
  -- Try each path
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
    -- Buffer selections include line numbers, but we only need the file path for Claude
    -- The parse_selection function already handles line number separation, so we return just the path
    return file_info.path
  else
    logger.warn("[PARSE_BUFFER] M.parse_selection failed to find a valid file for: '%s'", file_part)
    return nil
  end
end

-- Use new notification service
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
    return false, 'claudecode.nvim not installed'
  end
  
  local ok, claudecode = pcall(require, 'claudecode')
  if not ok then
    return false, 'claudecode.nvim failed to load'
  end
  
  if not claudecode.send_at_mention then
    return false, 'claudecode.nvim version too old, missing send_at_mention function'
  end
  
  return true, 'claudecode.nvim available'
end

return M
