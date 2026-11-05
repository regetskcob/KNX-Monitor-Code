import AudioToolbox
import Flutter
import NetworkExtension
import StoreKit
import UIKit
import UserNotifications

/// Native Helfer für den Monitor (Kanal „knx/native“): Hintergrund-Gnadenfrist,
/// damit der Tunnel sauber abgemeldet werden kann, lokale Alarm-Mitteilungen
/// und der Beitritt zum WLAN der KNX-Box.
final class KnxNative {
  static let shared = KnxNative()

  private var tasks: [Int: UIBackgroundTaskIdentifier] = [:]
  private var nextTaskId = 1
  private var channel: FlutterMethodChannel?

  /// Geöffnete Dateien, bis die App sie abholt („incomingFiles“).
  private var incoming: [URL] = []

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "knx/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in shared.handle(call, result) }
    shared.channel = channel
  }

  /// Datei aus Mail, AirDrop oder Dateien. Beim Kaltstart gibt es noch keinen
  /// Empfänger, dann holt die App sie ab, sobald ihre Oberfläche steht.
  func receive(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    incoming += urls
    channel?.invokeMethod("incomingFilesChanged", arguments: nil)
  }

  private func readIncoming(maxBytes: Int, _ result: @escaping FlutterResult) {
    let urls = incoming
    incoming = []
    DispatchQueue.global(qos: .userInitiated).async {
      let files = urls.map { KnxNative.readIncomingFile($0, maxBytes: maxBytes) }
      DispatchQueue.main.async { result(files) }
    }
  }

  /// Im Ort (Dateien, iCloud: Zugriff anmelden, koordiniert lesen) oder als Kopie
  /// in Documents/Inbox (dann danach wegräumen).
  private static func readIncomingFile(_ url: URL, maxBytes: Int) -> [String: Any] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped { url.stopAccessingSecurityScopedResource() }
      let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Inbox", isDirectory: true).standardizedFileURL.path
      if let inbox, url.standardizedFileURL.path.hasPrefix(inbox + "/") {
        try? FileManager.default.removeItem(at: url)
      }
    }
    var file: [String: Any] = ["problem": "unreadable"]
    var failure: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &failure) { readable in
      guard let values = try? readable.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
        values.isRegularFile == true,
        let handle = try? FileHandle(forReadingFrom: readable)
      else { return }
      defer { try? handle.close() }
      if (values.fileSize ?? 0) > maxBytes {
        file = ["problem": "tooLarge"]
        return
      }
      guard let data = try? handle.read(upToCount: maxBytes + 1) else {
        // Leere Datei: read liefert nil; die Weiche meldet sie als kein Paket.
        file = ["bytes": FlutterStandardTypedData(bytes: Data())]
        return
      }
      file = data.count > maxBytes ? ["problem": "tooLarge"] : ["bytes": FlutterStandardTypedData(bytes: data)]
    }
    return file
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "incomingFiles":
      readIncoming(maxBytes: args["maxBytes"] as? Int ?? 0, result)
    case "beginBackgroundTask":
      let id = nextTaskId
      nextTaskId += 1
      tasks[id] = UIApplication.shared.beginBackgroundTask(withName: "KNX-Tunnel abmelden") { [weak self] in
        self?.endTask(id)
      }
      result(id)
    case "endBackgroundTask":
      endTask(args["id"] as? Int ?? -1)
      result(nil)
    case "notifyPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
        DispatchQueue.main.async { result(nil) }
      }
    case "notify":
      let content = UNMutableNotificationContent()
      content.title = args["title"] as? String ?? "KNX"
      content.body = args["body"] as? String ?? ""
      // Wächter: ohne Systemton, die App spielt ihren eigenen.
      content.sound = (args["silent"] as? Bool ?? false) ? nil : .default
      // Gleiche Kennung ersetzt die vorige Mitteilung derselben Adresse.
      let request = UNNotificationRequest(
        identifier: args["id"] as? String ?? UUID().uuidString, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { _ in
        DispatchQueue.main.async { result(nil) }
      }
    case "joinWifi":
      // iOS fragt einmal „WLAN … verbinden?“; danach bleibt es gespeichert.
      let config = NEHotspotConfiguration(
        ssid: args["ssid"] as? String ?? "", passphrase: args["password"] as? String ?? "", isWEP: false)
      config.joinOnce = false
      NEHotspotConfigurationManager.shared.apply(config) { error in
        DispatchQueue.main.async {
          guard let error = error as NSError? else { return result("joined") }
          if error.domain == NEHotspotConfigurationErrorDomain {
            switch error.code {
            case NEHotspotConfigurationError.alreadyAssociated.rawValue: return result("joined")
            case NEHotspotConfigurationError.userDenied.rawValue: return result("denied")
            default: break
            }
          }
          result("error: \(error.localizedDescription)")
        }
      }
    case "storeEnvironment":
      storeEnvironment(result)
    case "alertSound":
      // Wächter: Systemton mit Vibration (im Stummmodus nur Vibration).
      AudioServicesPlayAlertSound(SystemSoundID(1005))
      result(nil)
    case "alertSoundQuiet":
      // Wächter zwischen zwei Mitteilungen: derselbe Ton ohne Vibration.
      AudioServicesPlaySystemSound(SystemSoundID(1005))
      result(nil)
    case "ackSound":
      // Klangquittung: kurze Systemtöne ohne Vibration (folgen dem
      // Stummschalter). Schreiben = Tock, Antwort = Tink, fremder Absender =
      // negativer Quittungston mit Vibration.
      switch args["kind"] as? String {
      case "response": AudioServicesPlaySystemSound(SystemSoundID(1103))
      case "foreign": AudioServicesPlayAlertSound(SystemSoundID(1054))
      default: AudioServicesPlaySystemSound(SystemSoundID(1104))
      }
      result(nil)
    case "copySecret":
      // Copied secret (token, password, code): only on this device, not via
      // Universal Clipboard, and gone after the expiry the system enforces.
      let seconds = (args["seconds"] as? NSNumber)?.doubleValue ?? 60
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": args["text"] as? String ?? ""]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(seconds)])
      result(true)
    case "keepAwake":
      // Wächter scharf: Display bleibt an, die App im Vordergrund hört weiter.
      UIApplication.shared.isIdleTimerDisabled = args["on"] as? Bool ?? false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func endTask(_ id: Int) {
    guard let task = tasks.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(task)
  }
}

/// Herkunft der installierten App: „production“ (App Store), „sandbox“
/// (TestFlight), „xcode“ oder nil (unbekannt, z. B. flutter run).
func storeEnvironment(_ result: @escaping FlutterResult) {
  if #available(iOS 16.0, macOS 13.0, *) {
    Task {
      var env: String?
      if let transaction = try? await AppTransaction.shared {
        switch transaction {
        case .verified(let t), .unverified(let t, _): env = t.environment.rawValue.lowercased()
        }
      }
      DispatchQueue.main.async { result(env ?? receiptEnvironment()) }
    }
  } else {
    result(receiptEnvironment())
  }
}

/// Ältere Systeme: TestFlight legt den Beleg als „sandboxReceipt“ ab.
private func receiptEnvironment() -> String? {
  guard let url = Bundle.main.appStoreReceiptURL, FileManager.default.fileExists(atPath: url.path) else {
    return nil
  }
  return url.lastPathComponent == "sandboxReceipt" ? "sandbox" : "production"
}
