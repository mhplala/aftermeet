import Foundation
import CoreAudio

/// 可选的录音输入设备。
///
/// 存在的理由是蓝牙协议的硬限制：A2DP（高音质输出）和 HFP（带麦克风的双向通话）不能共存。
/// 只要有 App 打开了蓝牙耳机的麦克风，macOS 就会把耳机从 A2DP 切到 HFP —— 整条链路掉到
/// 16kHz 单声道电话音质，而且 HFP 麦克风的 AGC 会把电平顶到接近满幅（实测导致混音后
/// 24%~30% 的样本削顶，云端识别几乎废掉）。
/// 所以默认策略是"避开蓝牙输入"：耳机保持 A2DP 听会，你的声音用内置麦克风采。
struct AudioInputDevice: Identifiable, Hashable {
    let id: String          // deviceUID，直接喂给 SCStreamConfiguration.microphoneCaptureDeviceID
    let name: String
    let isBluetooth: Bool
    let isBuiltIn: Bool
}

enum AudioInputDevices {
    static let modeKey = "micDeviceMode"     // "auto" | "system" | <deviceUID>

    static var mode: String {
        UserDefaults.standard.string(forKey: modeKey) ?? "auto"
    }

    /// 解析成实际要传给 SCStream 的 deviceUID；nil = 跟随系统默认（不指定）
    static func resolvedDeviceUID() -> String? {
        let m = mode
        if m == "system" { return nil }
        let devices = list()
        if m != "auto", devices.contains(where: { $0.id == m }) { return m }   // 用户点名的设备还在
        // auto（或点名的设备已拔掉）：默认输入是蓝牙就换成内置麦克风，否则不干预
        guard let def = defaultInputUID(), let cur = devices.first(where: { $0.id == def }) else { return nil }
        guard cur.isBluetooth else { return nil }
        return devices.first(where: { $0.isBuiltIn })?.id
    }

    /// 当前选择是否会把蓝牙耳机拽进 HFP（设置页据此给提示）
    static func willForceBluetoothHFP() -> Bool {
        let uid = resolvedDeviceUID() ?? defaultInputUID()
        guard let uid else { return false }
        return list().first(where: { $0.id == uid })?.isBluetooth ?? false
    }

    static func list() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioObjectID>.size else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }

        return ids.compactMap { dev -> AudioInputDevice? in
            guard hasInput(dev), let uid = stringProperty(dev, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(dev, kAudioObjectPropertyName) ?? uid
            let transport = uint32Property(dev, kAudioDevicePropertyTransportType)
            return AudioInputDevice(id: uid, name: name,
                                    isBluetooth: transport == kAudioDeviceTransportTypeBluetooth
                                              || transport == kAudioDeviceTransportTypeBluetoothLE,
                                    isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn)
        }
    }

    static func defaultInputUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr
        else { return nil }
        return stringProperty(dev, kAudioDevicePropertyDeviceUID)
    }

    // MARK: - CoreAudio 取值

    private static func hasInput(_ dev: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr) == noErr else { return false }
        let abl = UnsafeMutableAudioBufferListPointer(ptr.assumingMemoryBound(to: AudioBufferList.self))
        return abl.contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(_ dev: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: CFString? = nil
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }
        return value as String?
    }

    private static func uint32Property(_ dev: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}
