import AVFoundation
import CoreLocation
import Foundation

/// Keeps the app process alive in the background using silent audio + background location.
final class KeepAlive: NSObject, CLLocationManagerDelegate {
    static let shared = KeepAlive()

    private let locationManager = CLLocationManager()
    private var player: AVAudioPlayer?
    private(set) var isRunning = false

    private override init() {
        super.init()
        locationManager.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioInterrupted(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startAudio()
        startLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        locationManager.stopUpdatingLocation()
    }

    // MARK: Audio

    private func startAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWAV())
            player?.numberOfLoops = -1
            player?.prepareToPlay()
        }
        player?.play()
    }

    @objc private func audioInterrupted(_ note: Notification) {
        guard isRunning,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        startAudio()
    }

    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize: UInt32 = sampleRate * 2 // 1 second, 16-bit mono
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }

    // MARK: Location

    private func startLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 3000
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
            locationManager.startUpdatingLocation()
        case .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isRunning else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse:
            manager.startUpdatingLocation()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
