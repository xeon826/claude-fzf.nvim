# claude-fzf.nvim Development Documentation

## Project Overview

**claude-fzf.nvim** is a professional Neovim plugin that seamlessly integrates [fzf-lua](https://github.com/ibhagwan/fzf-lua) with [claudecode.nvim](https://github.com/coder/claudecode.nvim), enabling developers to efficiently select files and send them to Claude Code for analysis.

## Current Implementation Status

### Core Features ✅ **COMPLETED**
- **File Selection**: Multi-select file picker using fzf-lua interface
- **Buffer Integration**: Select and send open buffers to Claude
- **Git Files Support**: Pick from Git-tracked files  
- **Search Integration**: Live grep with result selection for Claude context
- **Batch Processing**: Efficient handling of multiple file selections
- **Progress Indicators**: Visual feedback during file processing

### Advanced Features ✅ **COMPLETED**
- **Unicode/Icon Support**: Comprehensive Nerd Fonts icon cleanup system
- **Smart Context Detection**: Tree-sitter based syntax-aware context extraction
- **Error Handling**: Robust error handling and recovery mechanisms
- **Logging System**: Complete logging framework with multiple levels
- **Health Checks**: Built-in diagnostics and dependency verification
- **Configuration System**: Flexible, extensible configuration options

### Recent Improvements ✅ **COMPLETED**
- **Unicode Character Handling**: Fixed multiple Unicode parsing issues for better compatibility
- **Buffer Path Parsing**: Enhanced parsing of buffer paths with line number information
- **Grep Output Processing**: Improved ripgrep output parsing and result formatting
- **Icon Cleanup**: Comprehensive cleanup of Nerd Fonts icons in file paths
- **Internationalization**: Added bilingual documentation (English/Chinese)

## Architecture

### Module Structure
```
lua/claude-fzf/
├── init.lua              # Main plugin entry point
├── config.lua            # Configuration management
├── actions.lua           # Core action handlers
├── commands.lua          # Vim command definitions
├── health.lua            # Health check system
├── logger.lua            # Logging framework
├── utils.lua            # Utility functions
└── integrations/
    ├── fzf.lua          # fzf-lua integration
    └── claudecode.lua   # Claude Code integration
```

### Key Components

#### 1. File Selection System (`integrations/fzf.lua`)
- Multi-picker support (files, buffers, Git files, grep)
- Unicode-safe file path processing
- Progress tracking and batch processing
- Custom keybindings and actions

#### 2. Claude Integration (`integrations/claudecode.lua`)
- Seamless communication with claudecode.nvim
- Context-aware file sending
- Terminal auto-opening
- Smart batching to avoid overwhelming Claude

#### 3. Configuration System (`config.lua`)
- Flexible configuration options
- Runtime configuration updates
- Validation and error handling
- Default configurations

#### 4. Logging Framework (`logger.lua`)
- Multiple log levels (TRACE, DEBUG, INFO, WARN, ERROR)
- File and console output options
- Caller information tracking
- Timestamp support

## Best Practices Learned

### Unicode and Character Handling
- **Always use byte-level operations** for Unicode character cleanup
- **Implement comprehensive icon detection** covering all Nerd Fonts character ranges
- **Use vim.fn.substitute()** for reliable character replacement
- **Test with various Unicode characters** to ensure robustness

### Error Handling and Robustness
- **Validate all inputs** before processing
- **Provide meaningful error messages** with context
- **Implement graceful degradation** when dependencies are missing
- **Use pcall() wrapper** for all external API calls

### Performance Optimization
- **Batch process** multiple files to reduce API overhead
- **Implement lazy loading** for heavy dependencies
- **Cache frequently accessed data** (configuration, etc.)
- **Use async processing** where possible to avoid blocking UI

### User Experience
- **Provide visual feedback** for all operations
- **Implement comprehensive health checks** for troubleshooting
- **Support customizable keybindings** for workflow integration
- **Maintain consistent command naming** patterns

## Development Workflow

### Testing Approach
- **Manual testing** with various file types and Unicode characters
- **Integration testing** with fzf-lua and claudecode.nvim
- **Edge case testing** for error conditions and malformed inputs
- **Performance testing** with large codebases

### Debugging Tools
- **Comprehensive logging system** with configurable levels
- **Health check command** for dependency verification
- **Debug command** for log management and analysis
- **Error reporting** with stack traces and context

### Code Quality Standards
- **Consistent code style** following Lua best practices
- **Comprehensive documentation** in code and README
- **Type annotations** using EmmyLua format
- **Error handling** for all external dependencies

## Known Issues and Limitations

### Resolved Issues ✅
- **Unicode character parsing** - Fixed multiple parsing edge cases
- **Buffer path handling** - Enhanced line number separation logic
- **Icon cleanup** - Comprehensive Nerd Fonts character removal
- **Grep output parsing** - Improved ripgrep format handling

### Current Limitations
- **Tree-sitter dependency** - Smart context requires nvim-treesitter
- **Plugin compatibility** - Requires specific versions of fzf-lua and claudecode.nvim
- **Platform-specific behavior** - Some features may behave differently across platforms

## Future Enhancements

### Planned Features
- **Custom preview modes** for different file types
- **Integration with more fuzzy finders** (Telescope, etc.)
- **Advanced filtering options** for file selection
- **Session management** for Claude contexts

### Performance Improvements
- **Async file processing** for large selections
- **Caching mechanisms** for frequently accessed files
- **Memory optimization** for large codebases
- **Background processing** options

## Troubleshooting Guide

### Common Issues
1. **"fzf-lua not found"** - Ensure fzf-lua is installed and loaded
2. **"claudecode.nvim not found"** - Verify claudecode.nvim installation
3. **Unicode display issues** - Check terminal and font support
4. **Performance with large repos** - Adjust batch_size configuration

### Debug Commands
```vim
:ClaudeFzfHealth          " Check plugin status
:ClaudeFzfDebug on        " Enable debug logging
:ClaudeFzfDebug log       " View log file
:ClaudeFzfDebug clear     " Clear logs
```

## Project Completion Status

**Overall Progress: 95% Complete**

- ✅ Core functionality implementation
- ✅ Unicode and character handling
- ✅ Error handling and robustness
- ✅ Documentation and user guides
- ✅ Health checks and debugging tools
- ⚠️ Testing framework (manual testing only)
- ⚠️ CI/CD pipeline setup (future enhancement)

The plugin is production-ready with comprehensive features, robust error handling, and excellent user experience. Recent focus has been on polishing Unicode handling and improving parsing reliability.