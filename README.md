# SimpleUI - Neovim UI组件集合

SimpleUI是一个轻量级的Neovim UI插件集合，提供现代化的状态栏、缓冲区标签栏和Git状态集成功能。

## 功能特性

### 状态栏(Statusline)

- 显示当前编辑模式(NORMAL/INSERT/VISUAL等)
- 显示当前文件信息和图标(支持nvim-web-devicons)
- Git分支和变更状态显示(added/modified/deleted)
- LSP诊断信息和客户端状态
- 当前工作目录显示
- 光标位置显示
- 多种分隔符样式可选(default/round/block/arrow)

### 缓冲区标签栏(Bufferline)

- 显示带编号的缓冲区标签
- 支持文件类型图标(nvim-web-devicons)
- 显示修改状态指示器
- 自适应宽度显示
- 提供缓冲区导航功能
- 提供缓冲区关闭功能

### Git状态集成

- 异步检测Git仓库状态
- 显示当前分支名称
- 显示文件变更状态(added/modified/deleted)
- 自动触发更新(文件保存后/会话加载后)

## 安装

使用你喜欢的插件管理器安装:

```lua
-- Packer.nvim
use {
  "jianshanbushishan/simpleui",
  requires = {
    "nvim-tree/nvim-web-devicons", -- 可选，用于文件图标
  },
  config = function()
    require("simpleui").setup()
  end
}
```

## 快捷键

- `<left>`: 切换到上一个缓冲区
- `<right>`: 切换到下一个缓冲区
- `<del>`: 关闭当前缓冲区
- `<s-del>`: 关闭所有缓冲区(保留当前)

## 依赖

- Neovim 0.9+
- (可选) nvim-web-devicons - 用于文件类型图标

## 贡献

欢迎提交Issue和PR!

## 许可证

MIT
