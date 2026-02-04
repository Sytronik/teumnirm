import CoreAudio
import Foundation

// MARK: - Microphone Usage Detector

/// Detects whether any input audio device is currently active.
final class MicrophoneUsageDetector {
    private var cachedInputDeviceIDs: [AudioDeviceID] = []
    private var lastCacheRefreshTime: Date = .distantPast
    private let cacheRefreshInterval: TimeInterval = 5.0

    func isMicrophoneInUse() -> Bool {
        refreshInputDeviceCacheIfNeeded()
        return cachedInputDeviceIDs.contains { isInputRunning(on: $0) }
    }

    private func refreshInputDeviceCacheIfNeeded() {
        let now = Date()
        guard
            cachedInputDeviceIDs.isEmpty
                || now.timeIntervalSince(lastCacheRefreshTime) >= cacheRefreshInterval
        else {
            return
        }

        cachedInputDeviceIDs = loadInputDeviceIDs()
        lastCacheRefreshTime = now
    }

    private func loadInputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        let loadStatus = deviceIDs.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        guard loadStatus == noErr else { return [] }

        return deviceIDs.filter { hasInputStream(on: $0) }
    }

    private func hasInputStream(on deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        let loadStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawBuffer
        )
        guard loadStatus == noErr else { return false }

        let bufferList = rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        let audioBuffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return audioBuffers.contains { $0.mNumberChannels > 0 }
    }

    private func isInputRunning(on deviceID: AudioDeviceID) -> Bool {
        if let running = readDeviceRunningFlag(deviceID: deviceID, scope: kAudioObjectPropertyScopeInput) {
            return running
        }

        if let running = readDeviceRunningFlag(
            deviceID: deviceID, scope: kAudioObjectPropertyScopeGlobal)
        {
            return running
        }

        return false
    }

    private func readDeviceRunningFlag(
        deviceID: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isRunning
        )
        guard status == noErr else { return nil }

        return isRunning != 0
    }
}
