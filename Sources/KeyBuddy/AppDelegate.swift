import AppKit
import Carbon

/// 菜单栏图标、权限、键盘监听调度
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var keyboardMonitor: KeyboardMonitor?
    private let inputManager = InputSourceManager()
    private var monitorActive = false
    private var retryTimer: Timer?
    private var inputSourceObserver: NSObjectProtocol?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 防止多实例
        let myPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        for app in runningApps where app.processIdentifier != myPID {
            app.activate()
            NSApplication.shared.terminate(nil)
            return
        }

        setupMenuBar()
        attemptStart()

        // 监听外部输入法变化
        inputSourceObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMenuBar()
        }
    }

    /// 双击恢复菜单栏
    func applicationDidBecomeActive(_ notification: Notification) {
        if !statusItem.isVisible {
            statusItem.isVisible = true
            statusItem.button?.performClick(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = inputSourceObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        retryTimer?.invalidate()
        keyboardMonitor?.stop()
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        statusItem.button?.title = inputManager.menuBarLabel

        let menu = NSMenu()
        menu.addItem(withTitle: "切换输入法", action: #selector(toggleInput), keyEquivalent: "")
        menu.addItem(.separator())
        let statusMenuItem = NSMenuItem(title: "监控状态：等待…", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 999
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem(title: "重新检测权限", action: #selector(retryPermission), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "诊断输入源", action: #selector(diagnoseInputSources), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "复制 App 路径", action: #selector(copyAppPath), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏菜单栏图标", action: #selector(toggleMenuBarVisibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 KeyBuddy", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func updateMonitorStatus(_ active: Bool, message: String? = nil) {
        monitorActive = active
        if let item = statusItem.menu?.item(withTag: 999) {
            item.title = message ?? (active ? "监控状态：✅ 运行中" : "监控状态：❌ 未启动")
        }
    }

    private func updateMenuBar() {
        statusItem.button?.title = inputManager.menuBarLabel
    }

    // MARK: - Launch flow

    private func attemptStart() {
        if tryStartMonitor() {
            return
        }
        updateMonitorStatus(false, message: "监控状态：⚠️ 需要辅助功能权限")
        showPermissionAlert()
        startRetryPolling()
    }

    private func showPermissionAlert() {
        let appPath = Bundle.main.bundlePath
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        KeyBuddy 需要辅助功能权限才能监听全局按键。

        当前 App 路径：
        \(appPath)

        请在「系统设置 → 隐私与安全性 → 辅助功能」中：
        1. 点击左下角 + 号
        2. 找到并添加当前 App（路径如上）
        3. 确保开关已打开

        授权后等待几秒即可自动生效，无需重启。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            let urlString: String
            if #available(macOS 13.0, *) {
                urlString = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
            } else {
                urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            }
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func startRetryPolling() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.tryStartMonitor() {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }

    @objc private func retryPermission() {
        if monitorActive { return }
        retryTimer?.invalidate()
        if !tryStartMonitor() {
            showPermissionAlert()
            startRetryPolling()
        }
    }

    @objc private func copyAppPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Bundle.main.bundlePath, forType: .string)
    }

    @objc private func toggleMenuBarVisibility() {
        statusItem.isVisible = false
    }

    // MARK: - Monitor

    @discardableResult
    private func tryStartMonitor() -> Bool {
        keyboardMonitor = KeyboardMonitor { [weak self] in
            DispatchQueue.main.async {
                self?.toggleInput()
            }
        }
        let ok = keyboardMonitor?.start() ?? false
        if ok {
            updateMonitorStatus(true)
        }
        return ok
    }

    // MARK: - Actions

    @objc private func toggleInput() {
        inputManager.toggle { [weak self] in
            self?.updateMenuBar()
        }
    }

    @objc private func diagnoseInputSources() {
        let info = inputManager.diagnose()
        let alert = NSAlert()
        alert.messageText = "输入源诊断"
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    @objc private func quitApp() {
        retryTimer?.invalidate()
        keyboardMonitor?.stop()
        NSApplication.shared.terminate(nil)
    }
}
