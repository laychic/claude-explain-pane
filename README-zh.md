# Claude Code 解释面板（Claude Code Explain Pane）

[English](../README.md) | **简体中文**

---

一个用于 Claude Code 的隐身侧边面板——在单独的终端中询问关于当前对话的问题，不会污染主会话。

## 功能特点

- **隐身模式** — 无会话历史、无记忆写入、零痕迹
- **自动读取上下文** — 读取主对话记录（最近 5 轮对话，已压缩）
- **滑动窗口** — 最近对话保留完整文本，较早对话自动摘要以控制在 3000 字符以内
- **上下文缓存** — 每 3 个问题才重新提取上下文，中间复用缓存
- **语言锁定** — 从第一个问题自动检测语言，保持会话内语言一致
- **多行粘贴** — 两次回车提交，粘贴不会提前触发
- **纯 Bash 实现** — 无需 Python、Node.js、jq，无外部依赖
- **跨平台** — 支持 Windows Terminal / tmux / iTerm2 / Terminal.app

## 安装

```bash
git clone https://github.com/laychic/claude-explain-pane.git
cd claude-explain-pane
bash install.sh
```

Windows 用户请运行 `install.bat`。

## 使用方法

在 Claude Code 中输入：

```text
/explain-e              # 打开面板
/explain-e what is this # 打开面板并自动提问
/explain-e -m sonnet    # 使用指定模型
```

如果面板已打开，`/explain-e <问题>` 会将问题直接发送到现有面板。

## 命令说明

| 命令 | 作用 |
|---|---|
| `exit` / `q` / `Ctrl+C` | 关闭面板 |
| `r` | 清除缓存，重新读取对话记录 |
| `lang:zh` | 锁定语言（支持 zh/en/ja/ko 等） |

## 工作原理

`/explain-e` → `explain-send.sh` → `open-pane.sh` → `watcher.sh`（交互式）

详细说明请继续阅读原 README。

---

## 链接路径注意事项

链接路径需要根据目录层级调整：

- 在 `docs/zh/README.md` 中链接到英文版：`../en/README.md`
- 在 `docs/zh/README.md` 中链接回根目录入口：`../../README.md`

## 可选：在入口 README 添加 badges 和统计信息

你可以参考下面的样式，在仓库入口 README 中添加项目统计信息：

```markdown
<div align="center">

# Claude Code Explain Pane

[![Stars](https://img.shields.io/github/stars/laychic/claude-explain-pane)](https://github.com/laychic/claude-explain-pane/stargazers)
[![Forks](https://img.shields.io/github/forks/laychic/claude-explain-pane)](https://github.com/laychic/claude-explain-pane/network)
[![License](https://img.shields.io/github/license/laychic/claude-explain-pane)](LICENSE)

**English** | [简体中文](docs/zh/README.md)

</div>
```
