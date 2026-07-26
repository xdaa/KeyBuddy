# KeyBuddy

macOS 菜单栏小工具：**单独敲一下 Shift 键，快速切换中英文输入法**。

## 功能

- 监听全局键盘事件，检测独立按松 Shift 键（无组合键）
- 检测到后自动切换中英文输入法
- 菜单栏图标实时显示当前输入法（A / 中）
- 中→英切换时模拟 ^Space 快捷键，确保输入法窗口正确关闭
- 支持 ABC、US、拼音、五笔、搜狗、百度、鼠须管等常见输入法

## 安装

Xcode 打开 `KeyBuddy.xcodeproj`，Archive 后导出 `KeyBuddy.app`，拖入 `/Applications`。

## 使用

1. 首次启动会提示需要**辅助功能权限**
2. 前往「系统设置 → 隐私与安全性 → 辅助功能」，添加 KeyBuddy 并开启
3. 授权后单独按下 Shift 键即可切换输入法

> **Tips**: 从中文切换到英文前会先按 ^Space，确保搜狗等输入法的候选窗先关闭再切走，避免文字残留。

## 菜单栏操作

| 菜单项 | 说明 |
|--------|------|
| 切换输入法 | 手动触发切换 |
| 监控状态 | 显示当前监听是否运行 |
| 重新检测权限 | 权限未授权时的重试入口 |
| 诊断输入源 | 列出系统所有中英文输入源 |
| 复制 App 路径 | 方便在「辅助功能」中添加 |
| 隐藏菜单栏图标 | 隐藏后双击 Dock 图标恢复 |

## 技术实现

- **Swift** + **AppKit**
- 全局键盘监听：`CGEvent.tapCreate` (headInsertEventTap)
- 输入法切换：Carbon Text Input Sources API
- 快捷键模拟：`CGEvent` post to `cghidEventTap`
- 系统快捷键读取：`com.apple.symbolichotkeys` (hotKey 60)
