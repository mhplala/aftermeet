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
        attachListener()
        // poll so a meeting window opening/closing is caught even without a mic-state change;
        // 每拍先校正默认输入设备（会中戴上 AirPods 切设备时，别把"旧设备停了"误判成离会）
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            self?.refreshDeviceIfChanged()
            self?.evaluate()
        }
        evaluate()
    }

    private func attachListener() {
        guard deviceID != kAudioObjectUnknown else { return }
        let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
        block = b
        AudioObjectAddPropertyListenerBlock(deviceID, &runningAddr, DispatchQueue.main, b)
    }

    private func refreshDeviceIfChanged() {
        let current = defaultInputDevice()
        guard current != deviceID else { return }
        if deviceID != kAudioObjectUnknown, let b = block {
            AudioObjectRemovePropertyListenerBlock(deviceID, &runningAddr, DispatchQueue.main, b)
        }
        deviceID = current
        attachListener()
        falseStrikes = 0            // 设备切换瞬间的假"停"不算 strike
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
    private let detectQueue = DispatchQueue(label: "aftermeet.watcher.detect", qos: .utility)
    private var detecting = false

    private func evaluate() {
        let mic = micRunning()
        if !active {
            guard mic, !detecting else { return }
            detecting = true
            // CGWindowListCopyWindowInfo 是 WindowServer 同步 IPC（可达几十 ms），不占主线程
            detectQueue.async { [weak self] in
                let present = MeetingDetector.meetingWindowPresent()
                var shouldLog = false
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.detecting = false
                    if self.active { return }                       // 后台检测期间已被手动开启
                    if present && self.micRunning() {
                        self.falseStrikes = 0
                        self.active = true
                        self.onChange?(true)
                    } else if Date().timeIntervalSince(self.lastCalibLog) > 30 {
                        self.lastCalibLog = Date()
                        shouldLog = true
                    }
                    if shouldLog {
                        self.detectQueue.async { MeetingDetector.logCandidates() }
                    }
                }
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

    /// 「麦克风在用」= 有 *AfterMeet 之外* 的进程正在这台默认输入设备上跑 input IO。
    /// 自从 macOS 15 captureMicrophone（双流混音）后，AfterMeet 自己会整段录制占用麦克风，
    /// 全局 kAudioDevicePropertyDeviceIsRunningSomewhere 因此永远为 true，auto-STOP 的
    /// `!mic` 永远不触发 → 会议不自动结束。必须把自家进程排除掉，只看别的进程。
    private func micRunning() -> Bool {
        guard deviceID != kAudioObjectUnknown else { return false }
        return anyOtherProcessRunningInput(on: deviceID)
    }

    private func anyOtherProcessRunningInput(on device: AudioObjectID) -> Bool {
        // 自家 PID → Process 对象，好跳过 AfterMeet 自己的占用
        var pid: pid_t = getpid()
        var ownID = AudioObjectID(kAudioObjectUnknown)
        var paddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var psize = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &paddr,
                                   UInt32(MemoryLayout<pid_t>.size), &pid, &psize, &ownID)

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.size else { return false }
        var list = [AudioObjectID](repeating: kAudioObjectUnknown,
                                   count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &list) == noErr else { return false }

        for obj in list {
            guard obj != AudioObjectID(kAudioObjectUnknown), obj != ownID else { continue }
            // 只认「正在跑 input IO」的进程，再核对它确实在用这台设备
            var runningInput: UInt32 = 0
            var raddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var rsize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(obj, &raddr, 0, nil, &rsize, &runningInput) == noErr,
                  runningInput != 0 else { continue }
            var daddr = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyDevices,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var dsize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(obj, &daddr, 0, nil, &dsize) == noErr else { continue }
            var devices = [AudioObjectID](repeating: kAudioObjectUnknown,
                                          count: Int(dsize) / MemoryLayout<AudioObjectID>.size)
            guard AudioObjectGetPropertyData(obj, &daddr, 0, nil, &dsize, &devices) == noErr else { continue }
            if devices.contains(device) { return true }
        }
        return false
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
