import Foundation
import CoreAudio

/// Fires `onChange(true)` only when BOTH the mic is in use AND a meeting/call window is on screen,
/// so a lone mic user (Siri, a voice memo, a one-off recording) no longer auto-triggers a recording.
/// The mic side is a permission-free Core Audio listener; the window side (`MeetingDetector`) is polled
/// every few seconds so a meeting window opening/closing without a mic-state change is still caught.
final class MeetingWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var active = false

    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var block: AudioObjectPropertyListenerBlock?
    private var started = false
    private var pollTimer: Timer?
    private var falseStrikes = 0
    private var lastCalibLog = Date.distantPast

    private var runningAddr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !started else { return }
        deviceID = defaultInputDevice()
        started = true
        if deviceID != kAudioObjectUnknown {
            let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            block = b
            AudioObjectAddPropertyListenerBlock(deviceID, &runningAddr, DispatchQueue.main, b)
        }
        // poll so a meeting window opening/closing is caught even without a mic-state change
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        if started, deviceID != kAudioObjectUnknown, let b = block {
            AudioObjectRemovePropertyListenerBlock(deviceID, &runningAddr, DispatchQueue.main, b)
        }
        started = false
    }

    /// START and STOP are deliberately decoupled:
    ///   • START — only when the mic is in use AND a meeting/call window is on screen (precise: no
    ///     false triggers from Siri / a lone voice memo).
    ///   • STOP — only when the mic device is actually released, i.e. you LEFT the call (debounced).
    ///     Muting keeps the device running, so mute won't stop it; and the (still-uncalibrated, flaky)
    ///     window detection is never allowed to cut a live recording.
    private func evaluate() {
        let mic = micRunning()
        if !active {
            if mic && MeetingDetector.meetingWindowPresent() {
                falseStrikes = 0
                active = true
                onChange?(true)
            } else if mic, Date().timeIntervalSince(lastCalibLog) > 30 {
                lastCalibLog = Date()
                MeetingDetector.logCandidates()    // mic on but no recognized meeting window → log for calibration
            }
        } else {
            if !mic {
                falseStrikes += 1
                if falseStrikes >= 2 { falseStrikes = 0; active = false; onChange?(false) }  // ~8s after mic released
            } else {
                falseStrikes = 0
            }
        }
    }

    private func micRunning() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        var val: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let st = AudioObjectGetPropertyData(deviceID, &runningAddr, 0, nil, &size, &val)
        return st == noErr && val != 0
    }

    private func defaultInputDevice() -> AudioObjectID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
        return dev
    }
}
