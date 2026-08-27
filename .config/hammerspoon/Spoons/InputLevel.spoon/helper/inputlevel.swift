// Mic peak-level probe for InputLevel.spoon: while some other process has an active
// input stream, taps the default input and writes the peak dBFS of each ~100ms window
// to a file; otherwise leaves the tap off so this process is never itself the reason
// the mic shows as in use.
//
// This exists as a separate signed app bundle rather than Lua in the spoon because
// Hammerspoon cannot be granted microphone access at all: its Info.plist carries no
// NSMicrophoneUsageDescription, so TCC refuses the request without prompting, and
// hs.audiodevice exposes only the input gain setting, never the incoming signal. The
// bundle around this binary is what holds the grant. See NextEvent/helper/nextevent.swift
// for the calendar equivalent of this same constraint.
//
// Unlike that helper, this one never exits on its own: it runs the whole time the spoon
// is started, gating its own tap on and off, killed by monitor.lua when the spoon stops.

import AVFoundation
import CoreAudio
import Foundation

// Where to leave the JSON. Launched through LaunchServices there is no stdout to
// inherit, so a path argument is how the caller reads this back; run by hand with no
// argument it just prints once per window instead of writing.
let outPath: String? = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

func emit(_ json: String) {
    guard let path = outPath else {
        print(json)
        return
    }
    // Written beside the target and renamed, so a reader polling the file never sees a
    // half-written payload and mistakes it for a malformed one.
    let tmp = path + ".tmp"
    do {
        try json.write(toFile: tmp, atomically: false, encoding: .utf8)
        _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                  withItemAt: URL(fileURLWithPath: tmp))
        if FileManager.default.fileExists(atPath: tmp) {
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
        }
    } catch {
        FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    }
}

func fail(_ reason: String) -> Never {
    emit("{\"error\":\"\(reason)\"}")
    exit(2)
}

// The floor a silent input reports as, since 20*log10(0) is -infinity and that neither
// encodes to JSON nor means anything on a meter with a bottom.
let silenceFloorDb = -60.0

// The threshold "over" is judged against. Kept here rather than read from Lua so this
// binary needs no arguments beyond the output path; monitor.lua's own clipThresholdDb
// is the latch policy built on top of this, and the two are independent on purpose —
// changing the hold behaviour in Lua should not require a rebuild here.
let clipThresholdDb = -1.0

// How often to recheck whether some other process is using the input device. Same
// reasoning as clipThresholdDb above for living here rather than in Lua.
let gateIntervalSeconds = 0.5

// Whether some process other than this one currently has an active input stream —
// the same public CoreAudio property macOS itself reads to build the "who's using
// your mic" list in Control Center. Checking it needs no permission and involves no
// audio capture of our own, so it is safe to poll continuously as the gate for
// whether *our* tap should be running at all: excluding our own PID is what keeps
// this from being self-referential the way the device-wide "is anything using the
// input" flag would be once our own tap is one of the things using it.
//
// Returns nil only if the top-level process-list query itself failed — a real
// CoreAudio error, not "nobody else happens to be using the mic right now."
let myPID = ProcessInfo.processInfo.processIdentifier

func audioProcessObjectList() -> [AudioObjectID]? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyProcessObjectList,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dataSize: UInt32 = 0
    var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
    guard status == noErr, dataSize > 0 else { return status == noErr ? [] : nil }

    let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
    var list = [AudioObjectID](repeating: 0, count: count)
    status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &list)
    return status == noErr ? list : nil
}

func audioProcessPID(_ object: AudioObjectID) -> pid_t? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

func audioProcessIsRunningInput(_ object: AudioObjectID) -> Bool? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningInput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
    return status == noErr ? value != 0 : nil
}

func anotherProcessIsUsingInput() -> Bool? {
    guard let processes = audioProcessObjectList() else { return nil }
    for process in processes {
        guard let pid = audioProcessPID(process), pid != myPID else { continue }
        if audioProcessIsRunningInput(process) == true {
            return true
        }
    }
    return false
}

var granted = false
let sem = DispatchSemaphore(value: 0)

AVCaptureDevice.requestAccess(for: .audio) { ok in
    granted = ok
    sem.signal()
}

// An unattended first run would otherwise hang here holding the launch open forever
// waiting on a prompt nobody is at the keyboard to answer.
if sem.wait(timeout: .now() + 25) == .timedOut {
    fail("access-timeout")
}
guard granted else { fail("no-access") }

let engine = AVAudioEngine()
let input = engine.inputNode

// Guards runningPeak, which the tap block (an audio realtime thread) writes and the
// flush timer (the main run loop) reads and resets. Neither side ever blocks the
// other for long, so a plain lock beats bringing in an actor for one shared Float.
let lock = NSLock()
var runningPeak: Float = 0

func installTap() {
    let format = input.outputFormat(forBus: 0)
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        for ch in 0..<Int(buffer.format.channelCount) {
            let samples = channels[ch]
            for i in 0..<frames {
                let s = abs(samples[i])
                if s > peak { peak = s }
            }
        }
        lock.lock()
        if peak > runningPeak { runningPeak = peak }
        lock.unlock()
    }
}

// engineActive tracks whether *we* are currently tapping, separately from
// engine.isRunning, so the gate timer below has an idempotent on/off to call and the
// config-change observer knows whether reconfiguring is its job right now.
var engineActive = false
var gateError: String? = nil

func startEngine() {
    guard !engineActive else { return }
    installTap()
    do {
        try engine.start()
        engineActive = true
    } catch {
        // Left false; the next gate tick will try again.
    }
}

func stopEngine() {
    guard engineActive else { return }
    engine.stop()
    input.removeTap(onBus: 0)
    engineActive = false
    lock.lock()
    runningPeak = 0
    lock.unlock()
}

// Fires when the active input device or its format changes underneath the engine —
// switching from the built-in mic to a USB interface, or a Bluetooth mic completing
// its connection — so the tap is rebuilt against whatever format is current instead
// of the meter silently going dead on a route change. Only relevant while we are
// actually tapping; gated off, there is nothing running to reconfigure.
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
) { _ in
    guard engineActive else { return }
    installTap()
    if !engine.isRunning {
        try? engine.start()
    }
}

// scheduledTimer schedules itself on the current run loop's default mode, which
// RunLoop.main.run() below spins forever, so no explicit add() is needed and no
// reference to the timer has to be kept alive. Both timers below run on the main run
// loop, so engineActive/gateError need no lock of their own — only runningPeak, torn
// between this loop and the tap's realtime thread, does.
_ = Timer.scheduledTimer(withTimeInterval: gateIntervalSeconds, repeats: true) { _ in
    switch anotherProcessIsUsingInput() {
    case true:
        gateError = nil
        startEngine()
    case false:
        gateError = nil
        stopEngine()
    case nil:
        // Fail closed: an unreadable gate is not evidence anyone is on a call.
        gateError = "gate-check-failed"
        stopEngine()
    }
}

_ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    var payload: [String: Any] = [
        "active": engineActive,
        "ts": Date().timeIntervalSince1970,
    ]
    if let gateError {
        payload["gateError"] = gateError
    }
    if engineActive {
        lock.lock()
        let peak = runningPeak
        runningPeak = 0
        lock.unlock()

        let peakDb = peak > 0 ? max(silenceFloorDb, 20 * log10(Double(peak))) : silenceFloorDb
        payload["peakDb"] = peakDb
        payload["over"] = peakDb >= clipThresholdDb
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let json = String(data: data, encoding: .utf8) {
        emit(json)
    }
}

RunLoop.main.run()
