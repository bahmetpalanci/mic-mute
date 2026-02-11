import Cocoa
import CoreAudio

// MARK: - Logger

final class Logger {
    static let shared = Logger()
    private let handle: FileHandle?
    private init() {
        let path = "/tmp/micmute-debug.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        handle?.seekToEndOfFile()
    }
    func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        if let data = line.data(using: .utf8) {
            handle?.write(data)
            handle?.synchronizeFile()
        }
    }
}

func dlog(_ msg: String) { Logger.shared.log(msg) }

// MARK: - CoreAudio Helpers

func getDefaultInputDeviceID() -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var deviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &deviceID
    )
    guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else { return nil }
    return deviceID
}

func getDeviceName(_ deviceID: AudioObjectID) -> String {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &name) { ptr in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
    }
    return status == noErr ? name as String : "unknown"
}

func getTransportType(_ deviceID: AudioObjectID) -> UInt32 {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
    return transport
}

func getDeviceUID(_ deviceID: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var uid: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    let status = withUnsafeMutablePointer(to: &uid) { ptr in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
    }
    return status == noErr ? uid as String : nil
}

/// Get all input stream IDs for a device
func getInputStreamIDs(_ deviceID: AudioObjectID) -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
        return []
    }
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var streamIDs = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streamIDs) == noErr else {
        return []
    }
    return streamIDs
}

/// Deactivate/activate input streams on a device
func setInputStreamsActive(_ deviceID: AudioObjectID, active: Bool) -> Bool {
    let streams = getInputStreamIDs(deviceID)
    dlog("Device \(deviceID) has \(streams.count) input stream(s)")

    var anySuccess = false
    for streamID in streams {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyIsActive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable: DarwinBoolean = false
        AudioObjectIsPropertySettable(streamID, &address, &isSettable)
        dlog("  Stream \(streamID) isActive settable: \(isSettable.boolValue)")

        if isSettable.boolValue {
            var val: UInt32 = active ? 1 : 0
            let status = AudioObjectSetPropertyData(
                streamID, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &val
            )
            dlog("  Stream \(streamID) setActive(\(active)): \(status == noErr ? "OK" : "ERR \(status)")")
            if status == noErr { anySuccess = true }
        }
    }
    return anySuccess
}

/// Set mute + volume on a device (all methods)
func muteDevice(_ deviceID: AudioObjectID, mute: Bool) {
    let volume: Float = mute ? 0.0 : 1.0
    let muteVal: UInt32 = mute ? 1 : 0

    for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
        // Mute property
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: element
        )
        var isSettable: DarwinBoolean = false
        AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if isSettable.boolValue {
            var val = muteVal
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
        }

        // Volume property
        address.mSelector = kAudioDevicePropertyVolumeScalar
        isSettable = false
        AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        if isSettable.boolValue {
            var vol = volume
            AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &vol)
        }
    }
}

/// Find all input devices
func getAllInputDeviceIDs() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size
    ) == noErr else { return [] }

    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    var deviceIDs = [AudioObjectID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address, 0, nil, &size, &deviceIDs
    ) == noErr else { return [] }

    return deviceIDs.filter { devID in
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &streamAddr, 0, nil, &streamSize) == noErr,
              streamSize > 0 else { return false }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(streamSize))
        defer { bufferList.deallocate() }
        guard AudioObjectGetPropertyData(devID, &streamAddr, 0, nil, &streamSize, bufferList) == noErr else {
            return false
        }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        var channels = 0
        for buf in abl { channels += Int(buf.mNumberChannels) }
        return channels > 0
    }
}

// MARK: - App Delegate

class MicMuteDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isMuted = false
    private var isToggling = false
    private var muteSound: NSSound?
    private var unmuteSound: NSSound?
    private var inputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var savedVolume: Int = 100

    func applicationDidFinishLaunching(_ notification: Notification) {
        dlog("=== MicMute launched ===")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Log all input devices
        let inputDevices = getAllInputDeviceIDs()
        for devID in inputDevices {
            let name = getDeviceName(devID)
            let transport = getTransportType(devID)
            let streams = getInputStreamIDs(devID)
            dlog("Input device: \(name) (id=\(devID), transport=\(transport), streams=\(streams))")
        }

        if let devID = getDefaultInputDeviceID() {
            dlog("Default input: \(getDeviceName(devID)) (id=\(devID))")
        }

        let currentVol = getASInputVolume()
        isMuted = currentVol == 0
        if !isMuted { savedVolume = currentVol }
        dlog("Initial: vol=\(currentVol), muted=\(isMuted)")

        muteSound = NSSound(named: NSSound.Name("Tink"))
        unmuteSound = NSSound(named: NSSound.Name("Pop"))

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])

        updateStatusIcon()
        registerInputDeviceChangeListener()
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
        guard !isToggling else { return }
        isToggling = true

        if isMuted {
            dlog("UNMUTE")
            performUnmute()
            isMuted = false
        } else {
            savedVolume = getASInputVolume()
            if savedVolume == 0 { savedVolume = 100 }
            dlog("MUTE")
            performMute()
            isMuted = true
        }
        updateStatusIcon()
        playFeedbackSound()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isToggling = false
        }
    }

    /// Get physical input devices only (skip virtual/aggregate to avoid killing TeamsVolume etc.)
    private func physicalInputDeviceIDs() -> [AudioObjectID] {
        return getAllInputDeviceIDs().filter { devID in
            let transport = getTransportType(devID)
            let isVirtual = transport == kAudioDeviceTransportTypeVirtual
                         || transport == kAudioDeviceTransportTypeAggregate
            if isVirtual {
                dlog("Skipping virtual/aggregate: \(getDeviceName(devID)) (transport=\(transport))")
            }
            return !isVirtual
        }
    }

    /// Mute ALL physical input devices
    private func performMute() {
        let inputDevices = physicalInputDeviceIDs()
        for devID in inputDevices {
            let name = getDeviceName(devID)

            // 1. Try deactivating input streams
            let streamResult = setInputStreamsActive(devID, active: false)
            dlog("[\(name)] stream deactivate: \(streamResult)")

            // 2. Set mute + volume 0
            muteDevice(devID, mute: true)
            dlog("[\(name)] mute+vol0 set")
        }

        // 3. Also AppleScript as fallback
        setASInputVolume(0)
        dlog("AppleScript vol=0")
    }

    /// Unmute ALL physical input devices
    private func performUnmute() {
        let inputDevices = physicalInputDeviceIDs()
        for devID in inputDevices {
            let name = getDeviceName(devID)

            // 1. Reactivate streams
            let streamResult = setInputStreamsActive(devID, active: true)
            dlog("[\(name)] stream activate: \(streamResult)")

            // 2. Unmute + restore volume
            muteDevice(devID, mute: false)
            dlog("[\(name)] unmute set")
        }

        // 3. AppleScript restore
        setASInputVolume(savedVolume > 0 ? savedVolume : 100)
        dlog("AppleScript vol=\(savedVolume)")
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "Quit MicMute", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
        }
    }

    @objc private func quit() {
        if isMuted { performUnmute() }
        NSApplication.shared.terminate(nil)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = isMuted ? "mic.slash.fill" : "mic.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Microphone")
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        button.image = image?.withSymbolConfiguration(config)
    }

    private func playFeedbackSound() {
        let sound = isMuted ? muteSound : unmuteSound
        sound?.stop()
        sound?.play()
    }

    // MARK: - AppleScript

    private func getASInputVolume() -> Int {
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

    private func setASInputVolume(_ volume: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "set volume input volume \(volume)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    // MARK: - Device Change Listener

    private func registerInputDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        inputDeviceListenerBlock = { [weak self] (_, _) in
            DispatchQueue.main.async {
                self?.handleInputDeviceChanged()
            }
        }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            inputDeviceListenerBlock!
        )
        dlog("Registered input device change listener")
    }

    private func handleInputDeviceChanged() {
        guard !isToggling else { return }

        if let devID = getDefaultInputDeviceID() {
            dlog("DEVICE CHANGED: \(getDeviceName(devID))")
        }

        if isMuted {
            dlog("Re-applying mute for new device")
            performMute()
        } else {
            savedVolume = getASInputVolume()
        }
        updateStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let block = inputDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MicMuteDelegate()
app.delegate = delegate
app.run()
