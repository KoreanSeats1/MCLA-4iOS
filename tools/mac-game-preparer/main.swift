import AppKit
import UniformTypeIdentifiers

final class Cancellation {
    private let lock = NSLock()
    private var flag = false
    func set(_ value: Bool) { lock.lock(); flag = value; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "")
    let sourceLabel = NSTextField(wrappingLabelWithString: "")
    let bar = NSProgressIndicator()
    let dropZone = ISODropZone(frame: .zero)
    let prepare = NSButton(title: "Prepare Game Folder", target: nil, action: nil)
    let choose = NSButton(title: "Choose Game…", target: nil, action: nil)
    let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    let reveal = NSButton(title: "Show in Finder", target: nil, action: nil)
    let cancellation = Cancellation()
    var source: URL?
    var output: URL?
    var running = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenuItem(); menu.addItem(appMenu)
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: "Quit MCLA Game Prep", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MCLA Game Prep"; window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        let title = NSTextField(labelWithString: "MIDNIGHT CLUB · GAME PREP")
        title.font = .systemFont(ofSize: 23, weight: .bold)
        let expected = NSTextField(wrappingLabelWithString: "Expected game\nMidnight Club: Los Angeles — Complete Edition\nXbox 360 · USA / NTSC-U")
        expected.font = .systemFont(ofSize: 16, weight: .semibold)
        expected.textColor = .systemTeal
        let description = NSTextField(wrappingLabelWithString: "Checks compatibility and extracts the complete MCLA_Game_Files folder for MCLA 4iOS. No title update needed.")
        description.textColor = .secondaryLabelColor
        status.stringValue = "Drop an Xbox 360 ISO, archive or extracted folder above."
        dropZone.onChoose = { [weak self] in self?.pick() }
        dropZone.onDrop = { [weak self] url in self?.setSource(url) }
        bar.minValue = 0; bar.maxValue = 1; bar.isIndeterminate = false
        for (button, action) in [(prepare, #selector(start)), (choose, #selector(pick)), (cancel, #selector(stop)), (reveal, #selector(showOutput))] {
            button.target = self; button.action = action; button.bezelStyle = .rounded
        }
        prepare.keyEquivalent = "\r"; cancel.isHidden = true; reveal.isHidden = true
        let buttons = NSStackView(views: [choose, prepare, cancel, reveal]); buttons.orientation = .horizontal
        let hint = NSTextField(wrappingLabelWithString: "When finished, copy MCLA_Game_Files to Files → On My iPhone/iPad → MCLA. Keep the iOS app closed while copying.")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, expected, description, dropZone, sourceLabel, bar, status, buttons, hint])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28),
            bar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dropZone.widthAnchor.constraint(equalTo: stack.widthAnchor),
            dropZone.heightAnchor.constraint(equalToConstant: 104),
            expected.widthAnchor.constraint(equalTo: stack.widthAnchor),
            description.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            sourceLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        prepare.isEnabled = false
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        // Directory access can wait on macOS privacy checks. Never block window creation.
        let beside = Bundle.main.bundleURL.deletingLastPathComponent()
        DispatchQueue.global(qos: .utility).async {
            let isos = ((try? FileManager.default.contentsOfDirectory(at: beside, includingPropertiesForKeys: [.isRegularFileKey])) ?? []).filter { $0.pathExtension.lowercased() == "iso" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            DispatchQueue.main.async {
                guard self.source == nil, !self.running else { return }
                if isos.count == 1 { self.setSource(isos[0]) }
                else if isos.count > 1 { self.status.stringValue = "Several ISOs found. Choose the Complete Edition ISO." }
            }
        }
    }
    func setSource(_ url: URL) {
        source = url; sourceLabel.stringValue = url.path
        dropZone.showSelected(true)
        prepare.isEnabled = true; reveal.isHidden = true; output = nil
        status.stringValue = "Ready to check and prepare your game folder."
    }
    @objc func pick() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.allowsMultipleSelection = false
        picker.allowedContentTypes = ["iso", "rar", "zip", "7z"].compactMap { UTType(filenameExtension: $0) }
        picker.message = "Choose the Xbox 360 Complete Edition ISO, archive or extracted game folder."
        picker.beginSheetModal(for: window) { response in
            if response == .OK, let url = picker.url { self.setSource(url) }
        }
    }
    @objc func start() {
        guard let source, !running else { return }
        running = true; cancellation.set(false)
        dropZone.isEnabled = false
        choose.isEnabled = false; prepare.isEnabled = false; cancel.isHidden = false; cancel.isEnabled = true; reveal.isHidden = true
        bar.doubleValue = 0; status.stringValue = "Checking game input…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let manifestURL = Bundle.main.url(forResource: "GameDataManifest", withExtension: "json") else { throw PreparationError(message: "App compatibility manifest is missing. Rebuild the app.") }
                let manifest = try JSONDecoder().decode(GameManifest.self, from: Data(contentsOf: manifestURL))
                                var last = Date.distantPast
                let output = try GameInput.prepare(source, manifest: manifest, cancelled: { self.cancellation.get() }) { progress, file in
                    if Date().timeIntervalSince(last) > 0.15 || progress == 0 {
                        last = Date()
                        DispatchQueue.main.async { self.bar.isIndeterminate = progress < 0; if progress < 0 { self.bar.startAnimation(nil) } else { self.bar.stopAnimation(nil); self.bar.doubleValue = progress }; self.status.stringValue = progress <= 0 ? file : "\(Int(progress * 100))% · \(file)" }
                    }
                }
                DispatchQueue.main.async {
                    self.output = output; self.finish()
                    self.bar.isIndeterminate = false; self.bar.stopAnimation(nil); self.bar.doubleValue = 1
                    self.status.stringValue = "Verified executable. MCLA_Game_Files is ready to copy."
                    self.reveal.isHidden = false
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                }
            } catch {
                DispatchQueue.main.async {
                    self.finish(); self.status.stringValue = error.localizedDescription
                    let alert = NSAlert(); alert.messageText = "Game preparation stopped"
                    alert.informativeText = error.localizedDescription; alert.beginSheetModal(for: self.window)
                }
            }
        }
    }
    func finish() { bar.isIndeterminate = false; bar.stopAnimation(nil); running = false; dropZone.isEnabled = true; choose.isEnabled = true; prepare.isEnabled = true; cancel.isHidden = true }
    @objc func stop() { cancellation.set(true); cancel.isEnabled = false; status.stringValue = "Cancelling and removing unfinished extraction…" }
    @objc func showOutput() { if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if running { stop(); return .terminateCancel }; return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if running { stop(); return false }; NSApp.terminate(nil); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
