import Cocoa

class MicMuteDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isMuted = false
    private var savedVolume: Int = 100

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let currentVol = getInputVolume()
        isMuted = currentVol == 0
        if !isMuted { savedVolume = currentVol }

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateStatusIcon()
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuitMenu()
        } else {
            toggleMicrophone()
        }
    }

    private func toggleMicrophone() {
        if isMuted {
            setInputVolume(savedVolume > 0 ? savedVolume : 100)
            isMuted = false
        } else {
            savedVolume = getInputVolume()
            if savedVolume == 0 { savedVolume = 100 }
            setInputVolume(0)
            isMuted = true
        }
        updateStatusIcon()
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit MicMute", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = isMuted ? "mic.slash.fill" : "mic.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Microphone")
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = image?.withSymbolConfiguration(config)
    }

    private func getInputVolume() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "input volume of (get volume settings)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return Int(output) ?? 0
    }

    private func setInputVolume(_ volume: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "set volume input volume \(volume)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MicMuteDelegate()
app.delegate = delegate
app.run()
