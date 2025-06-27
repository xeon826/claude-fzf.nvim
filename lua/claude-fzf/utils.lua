local M = {}

function M.filter_directories(selections)
  local dirs = {}
  for _, path in ipairs(selections) do
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == 'directory' then
      table.insert(dirs, path)
    end
  end
  return dirs
end

function M.filter_files(selections)
  local files = {}
  for _, path in ipairs(selections) do
    local stat = vim.loop.fs_stat(path)
    if stat and stat.type == 'file' then
      table.insert(files, path)
    end
  end
  return files
end

function M.get_directory_files(dir_path, max_depth)
  max_depth = max_depth or 2
  local files = {}
  
  local function scan_directory(path, current_depth)
    if current_depth > max_depth then
      return
    end
    
    local handle = vim.loop.fs_scandir(path)
    if not handle then
      return
    end
    
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      
      local full_path = path .. '/' .. name
      
      if type == 'file' then
        if not M.is_ignored_file(full_path) then
          table.insert(files, full_path)
        end
      elseif type == 'directory' and not M.is_ignored_directory(name) then
        scan_directory(full_path, current_depth + 1)
      end
    end
  end
  
  scan_directory(dir_path, 1)
  return files
end

function M.is_ignored_file(file_path)
  local ignored_patterns = {
    '%.git/',
    'node_modules/',
    '%.DS_Store$',
    '%.pyc$',
    '%.pyo$',
    '%.class$',
    '%.o$',
    '%.so$',
    '%.dll$',
    '%.exe$',
    '/%..*',
  }
  
  for _, pattern in ipairs(ignored_patterns) do
    if file_path:match(pattern) then
      return true
    end
  end
  
  return false
end

function M.is_ignored_directory(dir_name)
  local ignored_dirs = {
    '.git',
    'node_modules',
    '.svn',
    '.hg',
    '__pycache__',
    '.pytest_cache',
    '.mypy_cache',
    'target',
    'build',
    'dist',
    '.idea',
    '.vscode',
  }
  
  return vim.tbl_contains(ignored_dirs, dir_name)
end

function M.get_file_preview(file_path, max_lines)
  max_lines = max_lines or 50
  
  local stat = vim.loop.fs_stat(file_path)
  if not stat then
    return nil
  end
  
  if stat.type ~= 'file' then
    return string.format("[目录] %s", file_path)
  end
  
  local file = io.open(file_path, 'r')
  if not file then
    return "[无法读取文件]"
  end
  
  local lines = {}
  local line_count = 0
  
  for line in file:lines() do
    line_count = line_count + 1
    if line_count <= max_lines then
      table.insert(lines, line)
    else
      table.insert(lines, string.format("... (还有 %d 行)", M.count_file_lines(file_path) - max_lines))
      break
    end
  end
  
  file:close()
  return table.concat(lines, '\n')
end

function M.count_file_lines(file_path)
  local file = io.open(file_path, 'r')
  if not file then
    return 0
  end
  
  local count = 0
  for _ in file:lines() do
    count = count + 1
  end
  
  file:close()
  return count
end

function M.get_file_info(file_path)
  local stat = vim.loop.fs_stat(file_path)
  if not stat then
    return nil
  end
  
  return {
    path = file_path,
    size = stat.size,
    type = stat.type,
    mtime = stat.mtime.sec,
    is_binary = M.is_binary_file(file_path),
    line_count = stat.type == 'file' and M.count_file_lines(file_path) or nil,
  }
end

function M.is_binary_file(file_path, sample_size)
  sample_size = sample_size or 1024
  
  local file = io.open(file_path, 'rb')
  if not file then
    return false
  end
  
  local sample = file:read(sample_size)
  file:close()
  
  if not sample then
    return false
  end
  
  for i = 1, #sample do
    local byte = sample:byte(i)
    if byte == 0 or (byte < 32 and byte ~= 9 and byte ~= 10 and byte ~= 13) then
      return true
    end
  end
  
  return false
end

function M.normalize_path(path)
  path = vim.fn.expand(path)
  return vim.fn.fnamemodify(path, ':p')
end

function M.get_relative_path(path, base_path)
  base_path = base_path or vim.loop.cwd()
  path = M.normalize_path(path)
  base_path = M.normalize_path(base_path)
  
  if path:sub(1, #base_path) == base_path then
    return path:sub(#base_path + 2)
  end
  
  return path
end

function M.split_path(path)
  local dir = vim.fn.fnamemodify(path, ':h')
  local name = vim.fn.fnamemodify(path, ':t')
  local ext = vim.fn.fnamemodify(path, ':e')
  
  return {
    dir = dir,
    name = name,
    ext = ext,
    basename = vim.fn.fnamemodify(path, ':t:r')
  }
end

function M.debounce(fn, delay)
  local timer = nil
  return function(...)
    local args = {...}
    if timer then
      timer:stop()
      timer:close()
    end
    timer = vim.loop.new_timer()
    timer:start(delay, 0, vim.schedule_wrap(function()
      fn(unpack(args))
      timer:close()
      timer = nil
    end))
  end
end

function M.throttle(fn, delay)
  local last_call = 0
  return function(...)
    local now = vim.loop.hrtime() / 1e6
    if now - last_call >= delay then
      last_call = now
      return fn(...)
    end
  end
end

function M.deep_merge(target, source)
  for key, value in pairs(source) do
    if type(value) == 'table' and type(target[key]) == 'table' then
      M.deep_merge(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

function M.table_contains(table, value)
  for _, v in ipairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

function M.table_unique(table)
  local seen = {}
  local result = {}
  for _, value in ipairs(table) do
    if not seen[value] then
      seen[value] = true
      table.insert(result, value)
    end
  end
  return result
end

function M.escape_pattern(str)
  return str:gsub("([^%w])", "%%%1")
end

function M.format_file_size(bytes)
  local units = {'B', 'KB', 'MB', 'GB', 'TB'}
  local size = bytes
  local unit_index = 1
  
  while size >= 1024 and unit_index < #units do
    size = size / 1024
    unit_index = unit_index + 1
  end
  
  return string.format("%.1f %s", size, units[unit_index])
end

function M.get_git_root()
  local git_dir = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 then
    return git_dir
  end
  return nil
end

function M.is_git_repo()
  return M.get_git_root() ~= nil
end

-- 使用新的通知服务
local notify = require('claude-fzf.notify')

function M.notify_error(message, title)
  notify.error(message, { title = title })
end

function M.notify_warn(message, title)
  notify.warning(message, { title = title })
end

function M.notify_info(message, title)
  notify.info(message, { title = title })
end

-- 新增便捷方法
function M.notify_success(message, title)
  notify.success(message, { title = title })
end

return M