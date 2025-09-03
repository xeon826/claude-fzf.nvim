# claude-fzf.nvim

**fzf-lua 与 claudecode.nvim 的无缝集成**

claude-fzf.nvim 是一个专业的 Neovim 插件，将 [fzf-lua](https://github.com/ibhagwan/fzf-lua) 强大的文件选择功能与 [claudecode.nvim](https://github.com/coder/claudecode.nvim) 的 AI 上下文管理能力完美整合，为使用 Claude Code 的开发者提供卓越的工作流程体验。

[中文文档](README-zh.md) | [English Documentation](README.md)

## ✨ 特性

- 🚀 **批量文件选择**: 使用 fzf-lua 多选功能批量添加文件到 Claude 上下文
- 🔍 **智能搜索集成**: 通过 grep 搜索并直接发送相关代码片段到 Claude
- 🌳 **智能上下文提取**: 基于 Tree-sitter 的语法感知上下文检测
- 📁 **多种选择器**: 支持文件、缓冲区、Git 文件、目录文件等多种选择方式
- ⚡ **性能优化**: 懒加载、缓存和批处理确保流畅体验
- 🎨 **可视化反馈**: 进度指示器和状态通知
- 🛠️ **高度可配置**: 丰富的配置选项和自定义键映射
- 🔧 **健康检查**: 内置诊断功能确保环境正确配置

## 📋 依赖要求

- **Neovim**: >= 0.9.0
- **必需插件**:
  - [fzf-lua](https://github.com/ibhagwan/fzf-lua) - 模糊查找界面
  - [claudecode.nvim](https://github.com/coder/claudecode.nvim) - Claude Code 集成
- **可选依赖**:
  - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - 智能上下文提取

## 📦 安装

### 使用 lazy.nvim

```lua
{
  "pittcat/claude-fzf.nvim",
  dependencies = {
    "ibhagwan/fzf-lua",
    "coder/claudecode.nvim"
  },
  opts = {
    auto_context = true,
    batch_size = 10,
  },
  cmd = { "ClaudeFzf", "ClaudeFzfFiles", "ClaudeFzfGrep", "ClaudeFzfBuffers", "ClaudeFzfGitFiles", "ClaudeFzfDirectory" },
  keys = {
    { "<leader>cf", "<cmd>ClaudeFzfFiles<cr>", desc = "Claude: 添加文件" },
    { "<leader>cg", "<cmd>ClaudeFzfGrep<cr>", desc = "Claude: 搜索并添加" },
    { "<leader>cb", "<cmd>ClaudeFzfBuffers<cr>", desc = "Claude: 添加缓冲区" },
    { "<leader>cgf", "<cmd>ClaudeFzfGitFiles<cr>", desc = "Claude: 添加 Git 文件" },
    { "<leader>cd", "<cmd>ClaudeFzfDirectory<cr>", desc = "Claude: 添加目录文件" },
  },
}
```

### 使用 vim-plug

```vim
" 在你的 init.vim 或 vimrc 中添加
Plug 'ibhagwan/fzf-lua'
Plug 'coder/claudecode.nvim'
Plug 'pittcat/claude-fzf.nvim'

" 然后运行 :PlugInstall

" 在 init.vim 中配置（使用 Vimscript）
lua << EOF
require('claude-fzf').setup({
  auto_context = true,
  batch_size = 10,
  keymaps = {
    files = "<leader>cf",
    grep = "<leader>cg", 
    buffers = "<leader>cb",
    git_files = "<leader>cgf",
    directory_files = "<leader>cd",
  },
})
EOF

" 或者如果使用 init.lua，在文件中添加：
" require('claude-fzf').setup({
"   auto_context = true,
"   batch_size = 10,
" })
```

**安装步骤：**

1. 在你的 `~/.vimrc` 或 `~/.config/nvim/init.vim` 中添加上述 Plug 配置
2. 重启 Neovim 或重新加载配置：`:source %`
3. 运行安装命令：`:PlugInstall`
4. 等待安装完成
5. 重启 Neovim 享受新功能！

**快速验证安装：**
```vim
:ClaudeFzfHealth  " 检查插件健康状态
:ClaudeFzfFiles   " 测试文件选择器
```

### 使用 packer.nvim

```lua
use {
  "pittcat/claude-fzf.nvim",
  requires = {
    "ibhagwan/fzf-lua",
    "coder/claudecode.nvim"
  },
  config = function()
    require('claude-fzf').setup({
      auto_context = true,
      batch_size = 10,
    })
  end
}
```

## ⚙️ 配置

### 默认配置

```lua
require('claude-fzf').setup({
  -- 基本设置
  batch_size = 5,                    -- 批处理大小
  show_progress = true,              -- 显示进度指示器
  auto_open_terminal = true,         -- 自动打开 Claude 终端
  auto_context = true,               -- 启用智能上下文检测
  
  -- 日志配置
  logging = {
    level = "INFO",              -- TRACE, DEBUG, INFO, WARN, ERROR
    file_logging = true,         -- 启用文件日志
    console_logging = true,      -- 启用控制台日志
    show_caller = true,          -- 显示调用位置
    timestamp = true,            -- 显示时间戳
  },
  
  -- 键映射设置
  keymaps = {
    files = "<leader>cf",            -- 文件选择器
    grep = "<leader>cg",             -- 搜索选择器
    buffers = "<leader>cb",          -- 缓冲区选择器
    git_files = "<leader>cgf",       -- Git 文件选择器
    directory_files = "<leader>cd",     -- 目录文件选择器
  },
  
  -- fzf-lua 配置
  fzf_opts = {
    preview = {
      border = 'sharp',
      title = '预览',
      wrap = 'wrap',
    },
    winopts = {
      height = 0.8,              -- 窗口高度比例
      width = 0.8,               -- 窗口宽度比例
      backdrop = 60,             -- 背景透明度
    }
  },
  
  -- 目录搜索配置
  directory_search = {
    directories = {
      -- 在这里添加您的自定义目录
      -- 示例:
      -- screenshots = {
      --   path = vim.fn.expand("~/Desktop"),
      --   extensions = { "png", "jpg", "jpeg" },
      --   description = "截图文件"
      -- }
    },
    default_extensions = {},  -- 空表示所有文件
  },

  -- Claude 集成配置
  claude_opts = {
    auto_open_terminal = true,       -- 发送后自动打开终端
    context_lines = 5,               -- 上下文额外行数
    source_tag = "claude-fzf",       -- 来源标签
  },
})
```

## 🚀 使用方法

### 命令

| 命令 | 描述 |
|------|------|
| `:ClaudeFzfFiles` | 使用 fzf 选择文件发送到 Claude |
| `:ClaudeFzfGrep` | 使用 fzf grep 搜索并发送到 Claude |
| `:ClaudeFzfBuffers` | 使用 fzf 选择缓冲区发送到 Claude |
| `:ClaudeFzfGitFiles` | 使用 fzf 选择 Git 文件发送到 Claude |
| `:ClaudeFzfDirectory` | 使用 fzf 选择特定目录的文件发送到 Claude |
| `:ClaudeFzf [subcommand]` | 通用命令，支持子命令 |
| `:ClaudeFzfHealth` | 检查插件健康状态 |
| `:ClaudeFzfDebug [option]` | 调试工具和日志管理 |

### 键盘快捷键（默认）

| 键映射 | 功能 |
|--------|------|
| `<leader>cf` | 打开文件选择器 |
| `<leader>cg` | 打开搜索选择器 |
| `<leader>cb` | 打开缓冲区选择器 |
| `<leader>cgf` | 打开 Git 文件选择器 |
| `<leader>cd` | 打开目录文件选择器 |

### fzf 界面快捷键

在 fzf 选择器中：

| 快捷键 | 功能 |
|--------|------|
| `Tab` | 多选/取消选择 |
| `Enter` | 确认选择并发送到 Claude |
| `Ctrl-y` | 发送时包含智能上下文 |
| `Ctrl-l` | 复制到剪切板（带@前缀） |
| `Ctrl-d` | 发送目录（仅文件选择器） |
| `Alt-a` | 全选/取消全选 |
| `Esc` | 取消并退出 |

## 📚 API 参考

### 主要函数

```lua
-- 设置插件
require('claude-fzf').setup(opts)

-- 文件选择器
require('claude-fzf').files(opts)

-- 搜索选择器  
require('claude-fzf').grep_add(opts)

-- 缓冲区选择器
require('claude-fzf').buffers(opts)

-- Git 文件选择器
require('claude-fzf').git_files(opts)

-- 目录文件选择器
require('claude-fzf').directory_files(opts)

-- 获取当前配置
require('claude-fzf').get_config()
```

### 配置选项

```lua
---@class ClaudeFzf.Config
---@field batch_size number 批处理大小
---@field show_progress boolean 显示进度
---@field auto_open_terminal boolean 自动打开终端
---@field auto_context boolean 智能上下文
---@field keymaps table<string, string> 键映射
---@field fzf_opts table fzf-lua 配置
---@field claude_opts table Claude 集成配置
```

## 🔧 健康检查

运行健康检查以确保插件正确配置：

```vim
:ClaudeFzfHealth
```

健康检查将验证：
- Neovim 版本兼容性
- 必需依赖是否安装
- 配置是否有效
- 集成功能是否可用

## 📂 目录文件功能

目录文件选择器允许您快速搜索和选择您配置的目录中的文件，并支持可选的文件类型过滤。

### 需要配置

目录文件选择器是完全用户可配置的。没有预定义目录 - 您必须在配置中定义要使用的目录。

### 使用示例

**先配置目录，然后使用:**
```vim
:ClaudeFzfDirectory                 " 显示已配置的目录选择器
```

**键盘快捷键:**
```vim
<leader>cd                          " 打开目录选择器
```

**程序化使用:**
```lua
-- 显示目录选择器（仅在配置了目录时有效）
require('claude-fzf').directory_files()

-- 直接访问特定目录（如果已配置）
require('claude-fzf').directory_files({ directory = 'screenshots' })
```

### 自定义目录配置

在配置中添加您自己的目录:

```lua
require('claude-fzf').setup({
  directory_search = {
    directories = {
      -- 添加您的自定义目录
      screenshots = {
        path = vim.fn.expand("~/Desktop"),
        extensions = { "png", "jpg", "jpeg" },
        description = "截图文件"
      },
      my_configs = {
        path = vim.fn.expand("~/.config"),
        extensions = { "lua", "vim", "json", "yaml" },
        description = "配置文件"
      },
      project_docs = {
        path = vim.fn.expand("~/Projects/docs"),
        extensions = { "md", "txt", "rst" },
        description = "项目文档"
      }
    }
  }
})
```

### 目录选择器工作流程

1. **目录选择**: 首先从可用目录中选择
2. **文件过滤**: 文件按配置的扩展名自动过滤
3. **多选**: 使用 Tab 键选择多个文件
4. **发送到 Claude**: 按 Enter 键发送选中的文件

### 功能特点

- ✅ **智能路径验证**: 搜索前检查目录是否存在
- ✅ **扩展名过滤**: 只显示匹配配置扩展名的文件
- ✅ **性能优化**: 使用 `fd` 命令进行快速文件发现
- ✅ **可视状态**: 目录可用性用 ✓/✗ 指示器显示
- ✅ **Unicode 支持**: 正确处理 Unicode 文件名和路径

## 🎯 高级用法

### 自定义动作

```lua
local claude_fzf = require('claude-fzf')

-- 自定义文件选择器
claude_fzf.files({
  prompt = '选择配置文件> ',
  cwd = '~/.config',
  fzf_opts = {
    ['--header'] = '选择配置文件添加到 Claude'
  }
})
```

### 程序化使用

```lua
local actions = require('claude-fzf.actions')

-- 直接发送文件列表到 Claude
local files = {'src/main.lua', 'src/config.lua'}
actions.send_to_claude(files, { with_context = true })
```

## 🐛 故障排除

### 常见问题

**Q: 提示 "fzf-lua 未找到"**
A: 请确保已安装 fzf-lua 插件并正确配置

**Q: 提示 "claudecode.nvim 未找到"**
A: 请确保已安装 claudecode.nvim 插件并正确配置

**Q: 智能上下文不工作**
A: 请确保安装了 nvim-treesitter 并为当前文件类型安装了解析器

**Q: 键映射冲突**
A: 在配置中自定义键映射或设置为空字符串禁用

### 调试和日志

插件内置了完整的日志系统，方便调试问题：

**启用调试日志：**
```vim
:ClaudeFzfDebug on        " 启用调试日志
:ClaudeFzfDebug trace     " 启用详细跟踪日志
```

**查看日志：**
```vim
:ClaudeFzfDebug log       " 打开日志文件
:ClaudeFzfDebug stats     " 显示日志统计信息
```

**配置日志选项：**
```lua
require('claude-fzf').setup({
  logging = {
    level = "DEBUG",           -- TRACE, DEBUG, INFO, WARN, ERROR
    file_logging = true,       -- 启用文件日志
    console_logging = true,    -- 启用控制台日志
    show_caller = true,        -- 显示调用位置
    timestamp = true,          -- 显示时间戳
  },
})
```

**日志文件位置：**
- 默认路径：`~/.local/state/nvim/log/claude-fzf.log`
- 使用 `:ClaudeFzfDebug log` 直接打开日志文件

**常用调试命令：**
```vim
:ClaudeFzfDebug           " 显示帮助信息
:ClaudeFzfDebug on        " 启用调试
:ClaudeFzfDebug off       " 禁用调试
:ClaudeFzfDebug clear     " 清空日志文件
:ClaudeFzfHealth          " 检查插件状态
```

## 🤝 贡献

欢迎贡献！请阅读 [贡献指南](CONTRIBUTING.md) 了解详情。

## 📄 许可证

MIT License. 详见 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [fzf-lua](https://github.com/ibhagwan/fzf-lua) - 强大的模糊查找界面
- [claudecode.nvim](https://github.com/coder/claudecode.nvim) - Claude Code 集成
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) - 语法分析支持

---

**创造更好的 Claude Code 开发体验** 🚀