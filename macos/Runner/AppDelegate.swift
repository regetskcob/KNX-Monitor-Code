import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Doppelklick im Finder, AirDrop, Mail. Dateien an die App, alles andere
  /// (knxmonitor://) wie bisher an Flutter.
  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingFiles.shared.receive(urls.filter(\.isFileURL))
    let links = urls.filter { !$0.isFileURL }
    if !links.isEmpty { super.application(application, open: links) }
  }
}

/// Geöffnete Dateien, bis die App sie abholt („incomingFiles“). Beim Kaltstart
/// kommen sie vor dem Fenster und damit vor dem Kanal.
final class IncomingFiles {
  static let shared = IncomingFiles()

  var channel: FlutterMethodChannel?
  private var waiting: [URL] = []

  func receive(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    waiting += urls
    channel?.invokeMethod("incomingFilesChanged", arguments: nil)
  }

  func read(maxBytes: Int, _ result: @escaping FlutterResult) {
    let urls = waiting
    waiting = []
    DispatchQueue.global(qos: .userInitiated).async {
      let files = urls.map { IncomingFiles.readFile($0, maxBytes: maxBytes) }
      DispatchQueue.main.async { result(files) }
    }
  }

  private static func readFile(_ url: URL, maxBytes: Int) -> [String: Any] {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
      values.isRegularFile == true,
      let handle = try? FileHandle(forReadingFrom: url)
    else { return ["problem": "unreadable"] }
    defer { try? handle.close() }
    if (values.fileSize ?? 0) > maxBytes { return ["problem": "tooLarge"] }
    guard let data = try? handle.read(upToCount: maxBytes + 1) else {
      // Leere Datei: read liefert nil; die Weiche meldet sie als kein Paket.
      return ["bytes": FlutterStandardTypedData(bytes: Data())]
    }
    return data.count > maxBytes ? ["problem": "tooLarge"] : ["bytes": FlutterStandardTypedData(bytes: data)]
  }
}
