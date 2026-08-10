# macOS 触控板拖拽卡顿无重启修复

[English](README.md)

这是一个针对特定 macOS 故障模式的诊断记录和恢复工具：

- 用鼠标拖动窗口流畅；
- 用内建触控板拖动窗口卡顿，按压拖移和三指拖移都会出现；
- 触控板的其他操作可能仍然正常；
- 只有触控板拖动时，`WindowServer` CPU 占用明显升高；
- 重启 macOS 能恢复，但重启用户态输入监听也能在不重启、不注销的情况下恢复。

本仓库记录了一次可复现案例，并提供一个一键脚本，用于重启所有检测到的第三方后台输入监听软件。

## 下载后直接使用

1. 在 GitHub 页面选择 **Code → Download ZIP**。
2. 解压下载的 ZIP。
3. 双击 `一键重启第三方输入监听.command`。

完成以上操作即可执行恢复，不需要手动拖动测试，也不需要安装开发工具。

## 实际观察

原始案例来自一台 Apple 芯片 MacBook Pro，系统为 macOS Tahoe 26.5.2，登录会话已持续较长时间。

| 测试 | 结果 |
| --- | --- |
| 鼠标拖动窗口 | 流畅 |
| 触控板按压拖移 | 卡顿 |
| 触控板三指拖移 | 卡顿 |
| 故障时的 `WindowServer` | 约 101-109% CPU |
| Apple 触控板驱动 | 约 1% CPU，无严重错误和重置 |
| 调整 ProMotion/默认分辨率 | 未解决 |
| 仅重启一个第三方监听 | 未解决 |
| 重启一组第三方全局输入监听 | 立即恢复流畅 |
| 恢复后的 `WindowServer` | 相同拖动方式下约 63-85% CPU |

随后重新打开所有临时退出的应用，改善仍然保持。实用结论是：当前用户会话中的某个第三方输入监听软件进入了异常状态。一键重启所有检测到的第三方后台输入监听，会让它们重新注册监听并清除问题。实验没有最终锁定或点名任何具体应用。

鼠标仍然流畅，是因为鼠标和触控板并不完全经过相同的输入事件路径；底层软件缺陷的具体位置仍不确定。

## 一键恢复

使用中文脚本：

```bash
chmod +x 一键重启第三方输入监听.command
./一键重启第三方输入监听.command
```

也可以在 Finder 中直接双击 `一键重启第三方输入监听.command`。

只查看将要重启的程序，不执行任何操作：

```bash
./一键重启第三方输入监听.command --list
```

英文脚本行为完全相同：

```bash
./restart-third-party-input-monitors.command
```

执行重置时**不要求**手动拖动触控板。拖动测试只用于完成后确认是否恢复。

## 脚本会做什么

1. 使用 macOS 自带的 Ruby 运行环境调用 Apple 的 `CGGetEventTapList` API。
2. 找到当前登录会话中的输入监听拥有者。
3. 只保留当前用户的第三方后台/菜单栏应用。
4. 排除 Apple 系统进程、root 进程和普通前台/文档应用。
5. 向所有检测到的第三方后台输入监听进程发送 `SIGTERM`，不会使用 `SIGKILL`。
6. 重新打开对应的应用程序包。

脚本**不会**：

- 使用 `sudo`；
- 终止 `WindowServer`；
- 重启或注销 macOS；
- 修改显示器、触控板、辅助功能或隐私设置；
- 重置 TCC 权限；
- 终止任意普通前台应用。

## 运行要求

- macOS 中存在系统自带的 `/usr/bin/ruby`；
- 不需要安装 Homebrew、其他第三方包管理器或 Apple Command Line Tools。

## 重要限制

- `CGGetEventTapList` 只能覆盖 Quartz Event Tap，不能发现所有 IOHID、DriverKit、AppKit 或辅助功能监听。
- 脚本有意不包含任何针对具体应用的补充规则或嫌疑名单。
- 重启检测到的第三方监听是一种恢复手段，并不代表这些程序全部存在缺陷。
- 菜单栏工具在重新启动时可能短暂消失几秒。
- 如果正在进行关键远程控制或依赖辅助功能，请先运行 `--list`，不要直接批量重置。
- 如果鼠标和触控板都卡、普通光标移动也异常，或者安全模式/恢复模式下仍然存在，这很可能是另一个问题。

## 更稳妥的排查顺序

1. 运行 `--list`，检查检测到的后台应用。
2. 执行一键重置。
3. 用触控板拖动窗口测试。
4. 如果仍未恢复，再尝试睡眠/唤醒、注销/登录，或在允许重启时安装最新 macOS 更新。
5. 只有在正常用户会话之外也出现问题，或同时存在触点、点击、光标移动丢失时，才优先怀疑硬件。

## 参考资料

- [Apple：Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services)
- [Apple：CGGetEventTapList](https://developer.apple.com/documentation/coregraphics/cggeteventtaplist%28_%3A_%3A_%3A%29)
- [Apple：NSEvent 手势阶段](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property)

## 许可证

MIT
