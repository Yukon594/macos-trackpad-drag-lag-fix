# macOS Trackpad Drag Lag Fix

[简体中文](README.zh-CN.md)

A small diagnostic and recovery tool for a specific macOS failure mode:

- dragging windows with a mouse is smooth;
- dragging with the built-in trackpad stutters, using either force-click drag or three-finger drag;
- other trackpad actions may remain normal;
- `WindowServer` CPU usage rises sharply only during trackpad dragging;
- restarting macOS fixes it, but restarting user-space input monitors can fix it without a reboot or logout.

This repository documents one reproducible case and provides a one-click reset for all detected third-party background input-monitoring applications.

## Download and run

1. Select **Code → Download ZIP** on GitHub.
2. Extract the downloaded ZIP.
3. Double-click `restart-third-party-input-monitors.command`.

That is enough to run the recovery. No manual trackpad test or developer-tool installation is required.

## What was observed

The original case was recorded on an Apple-silicon MacBook Pro running macOS Tahoe 26.5.2 after a long login session.

| Test | Result |
| --- | --- |
| Mouse window drag | Smooth |
| Trackpad force-click drag | Stuttered |
| Trackpad three-finger drag | Stuttered |
| `WindowServer` during the fault | Approximately 101-109% CPU |
| Apple multitouch driver | Approximately 1% CPU, no critical errors or resets |
| ProMotion/default-resolution changes | Did not fix the fault |
| Restarting one third-party monitor alone | Did not fix the fault |
| Restarting a group of third-party global input monitors | Immediately restored smooth dragging |
| `WindowServer` after recovery | Approximately 63-85% during the same style of drag |

All temporarily stopped applications were relaunched, and the improvement remained. The practical conclusion is that one third-party input-monitoring application in the current user session had entered a bad state. Restarting all detected third-party background input monitors forced them to register fresh listeners and cleared the problem. No specific application was conclusively identified or named.

The mouse could remain smooth because mouse and trackpad input do not follow exactly the same event path. The exact underlying software defect remains unknown.

## One-click recovery

Use the English script:

```bash
chmod +x restart-third-party-input-monitors.command
./restart-third-party-input-monitors.command
```

Or double-click `restart-third-party-input-monitors.command` in Finder.

To inspect what would be restarted without changing anything:

```bash
./restart-third-party-input-monitors.command --list
```

The Chinese script has identical behavior:

```bash
./一键重启第三方输入监听.command
```

Manual trackpad dragging is **not required** for the reset. It is only useful afterward to verify whether the symptom is gone.

## What the script does

1. Uses the macOS-provided Ruby runtime to call Apple's `CGGetEventTapList` API.
2. Finds input-tap owners in the current login session.
3. Keeps only current-user, third-party background/menu-bar applications.
4. Excludes Apple system processes, root-owned processes, and ordinary foreground/document applications.
5. Sends `SIGTERM` to every detected third-party background input-monitor process; it does not use `SIGKILL`.
6. Reopens the corresponding application bundles.

It does **not**:

- use `sudo`;
- kill `WindowServer`;
- restart or log out macOS;
- modify display, trackpad, Accessibility, or privacy settings;
- reset TCC permissions;
- terminate arbitrary foreground applications.

## Requirements

- macOS with the system-provided `/usr/bin/ruby` runtime;
- no Homebrew, third-party package manager, or Apple Command Line Tools installation is required.

## Important limitations

- `CGGetEventTapList` covers Quartz Event Taps, not every possible IOHID, DriverKit, AppKit, or Accessibility-based monitor.
- The script intentionally contains no application-specific fallback or suspect list.
- Restarting all detected third-party monitors is a recovery action, not proof that all of them are faulty.
- Menu-bar utilities may disappear for a few seconds while they restart.
- Do not run the bulk reset during a critical remote-control or accessibility session without first using `--list`.
- If both mouse and trackpad dragging are slow, pointer movement is generally broken, or the issue persists in Safe Mode/Recovery, this is probably a different problem.

## Safer troubleshooting order

1. Run `--list` and review the detected background applications.
2. Run the one-click reset.
3. Test a trackpad window drag.
4. If the problem persists, try sleep/wake, log out/in, or install the latest macOS update when a restart is acceptable.
5. Suspect hardware only if symptoms also occur outside the normal user session or include missed touches, clicks, and pointer movement.

## References

- [Apple: Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services)
- [Apple: CGGetEventTapList](https://developer.apple.com/documentation/coregraphics/cggeteventtaplist%28_%3A_%3A_%3A%29)
- [Apple: NSEvent gesture phase](https://developer.apple.com/documentation/appkit/nsevent/phase-swift.property)

## License

MIT
