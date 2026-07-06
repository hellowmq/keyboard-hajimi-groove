import ApplicationServices
import AppKit
import AVFoundation
import Foundation
import KeyboardHajimiGrooveCore

struct KeyboardInputEvent {
    let keyCode: UInt16
    let timestamp: TimeInterval
    let isAutoRepeat: Bool
    let flags: CGEventFlags
    let isFlagsChanged: Bool
}

final class EventHandlerBox {
    let handler: (KeyboardInputEvent) -> Void

    init(handler: @escaping (KeyboardInputEvent) -> Void) {
        self.handler = handler
    }
}

final class KeyboardEventTap {
    private let box: Unmanaged<EventHandlerBox>
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handler: @escaping (KeyboardInputEvent) -> Void) {
        self.box = Unmanaged.passRetained(EventHandlerBox(handler: handler))
    }

    deinit {
        stop()
        box.release()
    }

    func start() throws {
        let keyDownMask = 1 << CGEventType.keyDown.rawValue
        let flagsChangedMask = 1 << CGEventType.flagsChanged.rawValue
        let eventMask = CGEventMask(keyDownMask | flagsChangedMask)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: keyboardEventCallback,
            userInfo: box.toOpaque()
        ) else {
            throw RuntimeError("无法创建键盘事件监听。请在系统设置里允许本程序使用“辅助功能”或“输入监控”权限。")
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
    }
}

private func keyboardEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard
        type == .keyDown || type == .flagsChanged,
        let userInfo
    else {
        return Unmanaged.passUnretained(event)
    }

    let box = Unmanaged<EventHandlerBox>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let repeatValue = event.getIntegerValueField(.keyboardEventAutorepeat)
    let inputEvent = KeyboardInputEvent(
        keyCode: keyCode,
        timestamp: TimeInterval(event.timestamp) / 1_000_000_000,
        isAutoRepeat: repeatValue != 0,
        flags: event.flags,
        isFlagsChanged: type == .flagsChanged
    )

    box.handler(inputEvent)
    return Unmanaged.passUnretained(event)
}

final class SamplePlayback: NSObject {
    let player: AVAudioPlayer
    var stopTimer: Timer?

    init(player: AVAudioPlayer) {
        self.player = player
    }

    func stop() {
        stopTimer?.invalidate()
        player.stop()
    }

    @objc func stopFromTimer(_ timer: Timer) {
        stop()
    }
}

final class SamplePlayer {
    private let maxPolyphony: Int
    private let baseURL: URL
    private var activePlaybacks: [SamplePlayback] = []

    init(maxPolyphony: Int = 1, baseURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        self.maxPolyphony = max(1, maxPolyphony)
        self.baseURL = baseURL
    }

    func trigger(_ clip: SampleClip, volume: Float) {
        purgeFinishedPlaybacks()

        let url = resolvedURL(for: clip.filePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs("采样文件不存在：\(url.path)\n", stderr)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.currentTime = clip.startTime
            player.volume = max(0, min(1, volume))
            player.prepareToPlay()
            enforcePolyphonyLimit()

            let playback = SamplePlayback(player: player)
            if let duration = clip.duration, shouldUseStopTimer(for: clip) {
                playback.stopTimer = Timer.scheduledTimer(
                    timeInterval: duration,
                    target: playback,
                    selector: #selector(SamplePlayback.stopFromTimer(_:)),
                    userInfo: nil,
                    repeats: false
                )
            }

            player.play()
            activePlaybacks.append(playback)
        } catch {
            fputs("采样播放失败：\(clip.title) \(error)\n", stderr)
        }
    }

    private func shouldUseStopTimer(for clip: SampleClip) -> Bool {
        // Pre-rendered files under clips/ are already cut to length. Let them play to EOF
        // so editing segment-plan.json + recutting does not require reloading theme metadata.
        !clip.filePath.contains("/clips/") || clip.startTime > 0
    }

    private func resolvedURL(for filePath: String) -> URL {
        let url = URL(fileURLWithPath: filePath)
        if url.path == filePath {
            return url
        }

        return URL(fileURLWithPath: filePath, relativeTo: baseURL).standardizedFileURL
    }

    func stopAll() {
        for playback in activePlaybacks {
            playback.stop()
        }

        activePlaybacks.removeAll()
    }

    private func enforcePolyphonyLimit() {
        while activePlaybacks.count >= maxPolyphony {
            activePlaybacks.removeFirst().stop()
        }
    }

    private func purgeFinishedPlaybacks() {
        activePlaybacks.removeAll { !$0.player.isPlaying }
    }
}

struct RuntimeError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

final class GrooveRuntime {
    private let allowRepeats: Bool
    private let analysisEvery: Int?
    private let clock: BeatBinder
    private let samplePlayer = SamplePlayer()
    private var tap: KeyboardEventTap?
    private var analyzer = KeyEventAnalyzer()

    private(set) var loadedTheme: LoadedTheme
    var onThemeChanged: ((LoadedTheme) -> Void)?

    init(loadedTheme: LoadedTheme, bpm: Double, allowRepeats: Bool, analysisEvery: Int? = nil) throws {
        self.loadedTheme = loadedTheme
        self.allowRepeats = allowRepeats
        self.analysisEvery = analysisEvery
        self.clock = BeatBinder(bpm: bpm, origin: ProcessInfo.processInfo.systemUptime)

        self.tap = KeyboardEventTap { [weak self] input in
            self?.handle(input)
        }
    }

    func start() throws {
        try tap?.start()
    }

    func switchTheme(_ nextTheme: LoadedTheme) {
        samplePlayer.stopAll()
        loadedTheme = nextTheme
        onThemeChanged?(nextTheme)
        printTheme(nextTheme.theme, prefix: "已切换主题")
        printMissingSamplesIfNeeded(for: nextTheme.theme)
    }

    func reloadCurrentTheme(currentDirectory: URL) {
        do {
            let argument: String? = switch loadedTheme.source {
            case .builtIn(let name):
                name
            case .file(let url):
                url.path
            }
            let nextTheme = try ThemeLoader.load(argument: argument, currentDirectory: currentDirectory)
            switchTheme(nextTheme)
        } catch {
            fputs("重新载入主题失败：\(error)\n", stderr)
        }
    }

    func printAnalysis() {
        print(formatAnalysis())
        fflush(stdout)
    }

    func resetAnalysis() {
        analyzer.reset()
        print("按键分析已重置。")
        fflush(stdout)
    }

    private func handle(_ input: KeyboardInputEvent) {
        guard allowRepeats || !input.isAutoRepeat else {
            return
        }

        let event: ShortcutMusicEvent
        guard let shortcutEvent = shortcutEvent(for: input) else {
            return
        }
        event = shortcutEvent

        analyzer.record(event)
        if let analysisEvery, analysisEvery > 0, analyzer.summary().totalEvents % analysisEvery == 0 {
            printAnalysis()
        }

        let beat = clock.bind(timestamp: ProcessInfo.processInfo.systemUptime)
        if let sampleClip = event.sampleClip {
            samplePlayer.trigger(sampleClip, volume: event.sampleVolume)
            print("[\(beat.label)] \(event.keyName.padding(toLength: 13, withPad: " ", startingAt: 0)) -> sample:\(sampleClip.id) -> \(event.shortcutID)")
        } else {
            print("[\(beat.label)] \(event.keyName.padding(toLength: 13, withPad: " ", startingAt: 0)) -> no-sample -> \(event.shortcutID)")
        }
        fflush(stdout)
    }

    private func shortcutEvent(for input: KeyboardInputEvent) -> ShortcutMusicEvent? {
        guard !input.isFlagsChanged else {
            return nil
        }

        let currentModifiers = modifiers(from: input.flags)
        guard let binding = loadedTheme.theme.shortcutBindings.first(where: {
            $0.keyCode == input.keyCode && Set($0.modifiers) == currentModifiers
        }) else {
            return nil
        }

        let sample = loadedTheme.theme.sampleClip(id: binding.sampleClipID, volume: binding.sampleVolume)

        return ShortcutMusicEvent(
            keyCode: input.keyCode,
            keyName: binding.title,
            shortcutID: binding.id,
            sampleClip: sample?.clip,
            sampleVolume: sample?.volume ?? 1,
            timestamp: input.timestamp
        )
    }

    private func modifiers(from flags: CGEventFlags) -> Set<KeyModifier> {
        var modifiers: Set<KeyModifier> = []

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }

        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }

        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }

        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }

        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.fn)
        }

        return modifiers
    }

    private func formatAnalysis() -> String {
        let summary = analyzer.summary(top: 10)
        let averageInterval = summary.averageGlobalInterval.map { formatSeconds($0) } ?? "n/a"
        var lines = [
            "",
            "=== 按键事件分析 ===",
            "总事件：\(summary.totalEvents)",
            "有效学习时长：\(formatSeconds(summary.observedDuration))",
            "学习段数：\(summary.segmentCount)",
            "忽略长停顿：\(summary.ignoredGapCount) 次（阈值 \(formatSeconds(summary.maxLearningGap))）",
            "整体平均间隔：\(averageInterval)",
            String(format: "事件密度：%.2f 次/秒", summary.eventsPerSecond),
            "Top keys:"
        ]

        if summary.topKeys.isEmpty {
            lines.append("  （暂无事件）")
        } else {
            for key in summary.topKeys {
                let average = key.averageInterval.map { formatSeconds($0) } ?? "n/a"
                let minimum = key.minimumInterval.map { formatSeconds($0) } ?? "n/a"
                let maximum = key.maximumInterval.map { formatSeconds($0) } ?? "n/a"
                lines.append("  \(key.keyName): count=\(key.count), avg=\(average), min=\(minimum), max=\(maximum)")
            }
        }

        lines.append("====================")
        return lines.joined(separator: "\n")
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.3fs", value)
    }

    func printMissingSamplesIfNeeded(for theme: MusicTheme) {
        let missing = missingSampleClips(for: theme)
        guard !missing.isEmpty else {
            return
        }

        fputs("缺少 \(missing.count) 个采样文件。请放入素材并运行 make recut-hajimi，或打开 make segment-ui 调整切片。\n", stderr)
        for clip in missing.prefix(5) {
            fputs("- \(clip.id): \(clip.filePath)\n", stderr)
        }
    }

    private func missingSampleClips(for theme: MusicTheme) -> [SampleClip] {
        let baseURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return theme.sampleClips.filter { clip in
            let url = URL(fileURLWithPath: clip.filePath)
            let resolved = url.path == clip.filePath ? url : URL(fileURLWithPath: clip.filePath, relativeTo: baseURL).standardizedFileURL
            return !FileManager.default.fileExists(atPath: resolved.path)
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let runtime: GrooveRuntime
    private let currentDirectory: URL

    init(runtime: GrooveRuntime, currentDirectory: URL) {
        self.runtime = runtime
        self.currentDirectory = currentDirectory
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        statusItem.button?.title = "哈"
        statusItem.button?.toolTip = "Keyboard Hajimi Groove"
        runtime.onThemeChanged = { [weak self] _ in
            Task { @MainActor in
                self?.rebuildMenu()
            }
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let currentName = runtime.loadedTheme.theme.name

        let currentItem = NSMenuItem(title: "当前：\(runtime.loadedTheme.theme.displayName)", action: nil, keyEquivalent: "")
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        menu.addItem(NSMenuItem.separator())

        if !ThemeLibrary.builtInNames.isEmpty {
            addSectionTitle("内置主题", to: menu)
            for name in ThemeLibrary.builtInNames {
                guard let theme = ThemeLibrary.builtIns[name] else {
                    continue
                }

                addThemeItem(
                    title: theme.displayName,
                    argument: name,
                    isSelected: theme.name == currentName,
                    to: menu
                )
            }
        }

        let fileThemes = discoverThemeFiles()
        if !fileThemes.isEmpty {
            menu.addItem(NSMenuItem.separator())
            addSectionTitle("JSON 主题", to: menu)

            for fileTheme in fileThemes {
                addThemeItem(
                    title: fileTheme.title,
                    argument: fileTheme.argument,
                    isSelected: fileTheme.name == currentName,
                    to: menu
                )
            }
        }

        menu.addItem(NSMenuItem.separator())
        addSectionTitle("按键学习", to: menu)

        let analysisItem = NSMenuItem(title: "打印按键分析", action: #selector(printKeyAnalysis), keyEquivalent: "a")
        analysisItem.target = self
        menu.addItem(analysisItem)

        let resetAnalysisItem = NSMenuItem(title: "重置按键分析", action: #selector(resetKeyAnalysis), keyEquivalent: "")
        resetAnalysisItem.target = self
        menu.addItem(resetAnalysisItem)

        menu.addItem(NSMenuItem.separator())
        let reloadThemeItem = NSMenuItem(title: "重新载入当前主题", action: #selector(reloadCurrentTheme), keyEquivalent: "l")
        reloadThemeItem.target = self
        menu.addItem(reloadThemeItem)

        let openEditorItem = NSMenuItem(title: "打开切片编辑器", action: #selector(openSegmentEditor), keyEquivalent: "e")
        openEditorItem.target = self
        menu.addItem(openEditorItem)

        let refreshItem = NSMenuItem(title: "刷新主题列表", action: #selector(refreshThemes), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "退出 Keyboard Hajimi Groove", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func addSectionTitle(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addThemeItem(title: String, argument: String, isSelected: Bool, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectTheme(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = argument
        item.state = isSelected ? .on : .off
        menu.addItem(item)
    }

    private func discoverThemeFiles() -> [(title: String, argument: String, name: String)] {
        let themesDirectory = currentDirectory.appendingPathComponent("Themes", isDirectory: true)

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: themesDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let loadedTheme = try? ThemeLoader.load(argument: url.path, currentDirectory: currentDirectory) else {
                    return nil
                }

                return (
                    title: loadedTheme.theme.displayName,
                    argument: url.path,
                    name: loadedTheme.theme.name
                )
            }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let argument = sender.representedObject as? String else {
            return
        }

        do {
            let nextTheme = try ThemeLoader.load(argument: argument, currentDirectory: currentDirectory)
            runtime.switchTheme(nextTheme)
        } catch {
            showThemeLoadError(error)
        }
    }

    @objc private func refreshThemes() {
        rebuildMenu()
    }

    @objc private func printKeyAnalysis() {
        runtime.printAnalysis()
    }

    @objc private func resetKeyAnalysis() {
        runtime.resetAnalysis()
    }

    @objc private func reloadCurrentTheme() {
        runtime.reloadCurrentTheme(currentDirectory: currentDirectory)
    }

    @objc private func openSegmentEditor() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8765")!)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showThemeLoadError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "主题加载失败"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
    }
}

func parseBPM(from arguments: [String]) -> Double {
    guard let index = arguments.firstIndex(of: "--bpm"), arguments.indices.contains(index + 1) else {
        return 96
    }

    return Double(arguments[index + 1]).map { max(40, min(220, $0)) } ?? 96
}

func parseThemeArgument(from arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "--theme"), arguments.indices.contains(index + 1) else {
        return nil
    }

    return arguments[index + 1]
}

func parseAnalysisEvery(from arguments: [String]) -> Int? {
    guard let index = arguments.firstIndex(of: "--analysis-every"), arguments.indices.contains(index + 1) else {
        return nil
    }

    return Int(arguments[index + 1]).map { max(1, $0) }
}

func printTheme(_ theme: MusicTheme, prefix: String = "当前主题") {
    print("\(prefix)：\(theme.displayName)（\(theme.name)）。")
    fflush(stdout)
}

let arguments = CommandLine.arguments
let allowRepeats = arguments.contains("--allow-repeat")
let bpm = parseBPM(from: arguments)
let selectedTheme = parseThemeArgument(from: arguments)
let analysisEvery = parseAnalysisEvery(from: arguments)

let promptOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
if !AXIsProcessTrustedWithOptions(promptOptions) {
    print("需要 macOS 辅助功能/输入监控权限。授权后请重新运行：swift run keyboard-hajimi-groove")
    fflush(stdout)
}

do {
    let loadedTheme = try ThemeLoader.load(argument: selectedTheme)
    let theme = loadedTheme.theme
    let runtime = try GrooveRuntime(
        loadedTheme: loadedTheme,
        bpm: bpm,
        allowRepeats: allowRepeats,
        analysisEvery: analysisEvery
    )

    NSApplication.shared.setActivationPolicy(.accessory)
    let statusBarController = StatusBarController(
        runtime: runtime,
        currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    )
    _ = statusBarController

    print("Keyboard Hajimi Groove 已启动。当前仅响应快捷键掉宝主题。")
    print("顶部状态栏会出现“哈”入口，可从菜单切换 Themes/*.json。")
    print("默认主题：\(ThemeLibrary.defaultThemePath)")
    printTheme(theme)
    runtime.printMissingSamplesIfNeeded(for: theme)
    print("参数：--bpm 120 改速度，--allow-repeat 允许长按连发。按 Control-C 退出。")
    fflush(stdout)

    try runtime.start()
    NSApplication.shared.run()
} catch {
    fputs("启动失败：\(error)\n", stderr)
    exit(1)
}
