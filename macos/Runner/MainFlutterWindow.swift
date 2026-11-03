import Cocoa
import FlutterMacOS
import StoreKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // Kleiner als ein Telefon-Layout wird es nicht sinnvoll.
    self.contentMinSize = NSSize(width: 380, height: 560)
    self.setFrameAutosaveName("KNXMonitorMainWindow")

    RegisterGeneratedPlugins(registry: flutterViewController)

    KnxCloud.register(messenger: flutterViewController.engine.binaryMessenger)

    // Kanal „knx/native“ auf dem Mac: Herkunft der App (TestFlight-Beta), Töne, geöffnete Dateien.
    let channel = FlutterMethodChannel(
      name: "knx/native", binaryMessenger: flutterViewController.engine.binaryMessenger)
    IncomingFiles.shared.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "incomingFiles":
        let args = call.arguments as? [String: Any] ?? [:]
        IncomingFiles.shared.read(maxBytes: args["maxBytes"] as? Int ?? 0, result)
      case "storeEnvironment": storeEnvironment(result)
      case "alertSound", "alertSoundQuiet":
        // Wächter: Systemton „Glass“ (der Mac vibriert nicht).
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        result(nil)
      case "ackSound":
        // Klangquittung: Schreiben = „Tink“, Antwort = „Pop“, fremd = „Basso“.
        let args = call.arguments as? [String: Any] ?? [:]
        let name: String
        switch args["kind"] as? String {
        case "response": name = "Pop"
        case "foreign": name = "Basso"
        default: name = "Tink"
        }
        // Eigene Instanz je Ton, damit schnelle Folgen nicht abgeschnitten werden.
        (NSSound(named: name)?.copy() as? NSSound)?.play()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
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
