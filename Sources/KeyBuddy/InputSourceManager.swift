import Carbon
import CoreGraphics
import Foundation

/// 中英文输入法切换管理器
final class InputSourceManager {

    /// 系统「选择上一个输入源」快捷键配置（读取一次，缓存）
    private let shortcut: (keyCode: CGKeyCode, modifierKeyCode: CGKeyCode, flags: CGEventFlags)?

    init() {
        shortcut = Self.readSelectPreviousShortcut()
    }

    var allSources: [TISInputSource] {
        let props: [String: Any] = [
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        guard let list = TISCreateInputSourceList(props as CFDictionary, false) else { return [] }
        return list.takeRetainedValue() as? [TISInputSource] ?? []
    }

    var englishSources: [TISInputSource] {
        allSources.filter { isEnglish($0) }
    }

    var chineseSources: [TISInputSource] {
        allSources.filter { isChinese($0) }
    }

    /// 上次切换状态（诊断用）
    var lastToggleStatus: String = "未调用"

    func diagnose() -> String {
        let enIDs = englishSources.compactMap { sourceID(for: $0) }
        let zhIDs = chineseSources.compactMap { sourceID(for: $0) }
        let curID: String
        if let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
            curID = sourceID(for: cur) ?? "?"
        } else {
            curID = "?"
        }
        return "当前: \(curID)\n英文源: \(enIDs)\n中文源: \(zhIDs)\n\(lastToggleStatus)"
    }

    func toggle(completion: (() -> Void)? = nil) {
        let sources = allSources
        let en = sources.first(where: { isEnglish($0) })
        let zh = sources.first(where: { isChinese($0) })

        guard let en, let zh, en !== zh else {
            lastToggleStatus = "❌ 缺少输入源"
            completion?()
            return
        }

        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            lastToggleStatus = "❌ 无法获取当前输入法"
            completion?()
            return
        }

        let target = (sourceID(for: cur) == sourceID(for: en)) ? zh : en
        let targetID = sourceID(for: target) ?? "?"
        let switchingFromChinese = isChinese(cur)

        if switchingFromChinese, let shortcut {
            // 中→英：模拟 ^Space 走系统路径，触发 deactivateServer 提交文字+关窗
            simulateSelectPreviousShortcut(shortcut)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                // 兜底：确保最终是英文（^Space 切到非英文源时纠正）
                if let cur2 = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                   self.isChinese(cur2) || self.sourceID(for: cur2) != self.sourceID(for: target) {
                    TISSelectInputSource(target)
                }
                self.lastToggleStatus = "✅ 已切换到 \(targetID)"
                completion?()
            }
            return
        }

        // 英→中 / 无快捷键：直接 TISSelectInputSource
        let status = TISSelectInputSource(target)
        if status == noErr {
            lastToggleStatus = "✅ 已切换到 \(targetID)"
        } else {
            lastToggleStatus = "❌ 切换失败 status=\(status)"
        }
        completion?()
    }

    var menuBarLabel: String {
        guard let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "?"
        }
        return isEnglish(cur) ? "A" : "中"
    }

    // MARK: - Shortcut Simulation

    /// 从 com.apple.symbolichotkeys 读取「选择上一个输入源」快捷键配置
    private static func readSelectPreviousShortcut() -> (keyCode: CGKeyCode, modifierKeyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let dict = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let hotKeys = dict["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = hotKeys["60"] as? [String: Any],
              entry["enabled"] as? Int == 1,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [NSNumber],
              params.count >= 3 else { return nil }

        let keyCode = CGKeyCode(params[1].intValue)
        let rawFlags = params[2].uint64Value

        let cgFlags = CGEventFlags(rawValue: rawFlags & 0xFFFF0000)

        let modKeyCode: CGKeyCode
        if rawFlags & 0x40000 != 0 { modKeyCode = 0x3B }      // Control
        else if rawFlags & 0x80000 != 0 { modKeyCode = 0x3A }  // Option
        else if rawFlags & 0x100000 != 0 { modKeyCode = 0x38 } // Shift
        else if rawFlags & 0x1000000 != 0 { modKeyCode = 0x37 } // Command
        else { return nil }

        return (keyCode, modKeyCode, cgFlags)
    }

    /// 模拟系统「选择上一个输入源」快捷键
    private func simulateSelectPreviousShortcut(_ sc: (keyCode: CGKeyCode, modifierKeyCode: CGKeyCode, flags: CGEventFlags)) {
        let src = CGEventSource(stateID: .hidSystemState)
        let modDown = CGEvent(keyboardEventSource: src, virtualKey: sc.modifierKeyCode, keyDown: true)!
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: sc.keyCode, keyDown: true)!
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: sc.keyCode, keyDown: false)!
        let modUp   = CGEvent(keyboardEventSource: src, virtualKey: sc.modifierKeyCode, keyDown: false)!

        keyDown.flags = sc.flags
        keyUp.flags = sc.flags

        [modDown, keyDown, keyUp, modUp].forEach { $0.post(tap: .cghidEventTap) }
    }

    // MARK: - Helpers

    private func sourceID(for src: TISInputSource) -> String? {
        TISGetInputSourceProperty(src, kTISPropertyInputSourceID)
            .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }

    private func languages(for src: TISInputSource) -> [String] {
        guard let langs = TISGetInputSourceProperty(src, kTISPropertyInputSourceLanguages) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as? [String] ?? []
    }

    private func isEnglish(_ src: TISInputSource) -> Bool {
        if isChinese(src) { return false }
        let langs = languages(for: src)
        if langs.contains(where: { $0.hasPrefix("en") }) { return true }
        let id = sourceID(for: src) ?? ""
        let knownEnglishIDs = [
            "com.apple.keylayout.ABC", "com.apple.keylayout.US",
            "com.apple.keylayout.British", "com.apple.keylayout.Canadian",
        ]
        return knownEnglishIDs.contains { id.hasPrefix($0) }
    }

    private func isChinese(_ src: TISInputSource) -> Bool {
        let langs = languages(for: src)
        if langs.contains(where: { $0.hasPrefix("zh") }) { return true }
        let id = sourceID(for: src) ?? ""
        let knownChineseIDs = [
            "com.apple.inputmethod.SCIM",
            "com.apple.inputmethod.TCIM",
            "com.sogou.inputmethod.sogou.pinyin",
            "com.baidu.inputmethod",
            "im.rime.inputmethod.Squirrel",
        ]
        return knownChineseIDs.contains { id.hasPrefix($0) }
    }
}
