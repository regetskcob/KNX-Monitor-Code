import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// Privater iCloud-Container für den Abgleich (Kanal „knx/cloud“). Gilt für iOS und
/// macOS; die Datei liegt einmal und gehört zu beiden Targets. Inhalte kommen schon
/// verschlüsselt aus Dart.
final class KnxCloud {
  static let shared = KnxCloud()

  private let queue = DispatchQueue(label: "knx.cloud", qos: .utility)
  private var query: NSMetadataQuery?
  private var observer: NSObjectProtocol?

  /// So lange wartet das Lesen auf den Download; danach versucht es der nächste Abgleich.
  private static let downloadTimeout: TimeInterval = 60

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "knx/cloud", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in shared.handle(call, result) }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let name = args["name"] as? String ?? ""
    switch call.method {
    case "iCloudAvailable":
      queue.async {
        let ok = FileManager.default.ubiquityIdentityToken != nil && Self.folder() != nil
        DispatchQueue.main.async { result(ok) }
      }
    case "iCloudList": list(result)
    case "iCloudRead": run(result) { try Self.read(name).map { FlutterStandardTypedData(bytes: $0) } as Any }
    case "iCloudWrite":
      let bytes = (args["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
      run(result) {
        try Self.write(name, bytes)
        return nil as Any?
      }
    case "iCloudDelete":
      run(result) {
        try Self.delete(name)
        return nil as Any?
      }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func run(_ result: @escaping FlutterResult, _ work: @escaping () throws -> Any?) {
    queue.async {
      do {
        let value = try work()
        DispatchQueue.main.async { result(value) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "icloud", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private static func folder() -> URL? {
    guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
    let url = container.appendingPathComponent("sync", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func url(_ name: String) throws -> URL {
    // Namen kommen aus der App; ein Pfad darf den Ordner nie verlassen.
    guard !name.isEmpty, !name.contains("/"), !name.hasPrefix("."), let folder = folder() else {
      throw CocoaError(.fileNoSuchFile)
    }
    return folder.appendingPathComponent(name)
  }

  /// Fragt iCloud statt des Ordners: Dateien anderer Geräte stehen dort oft noch nicht.
  /// Antwortet die Abfrage nicht, reicht der Blick in den Ordner.
  private func list(_ result: @escaping FlutterResult) {
    let finished = OneShot(result)
    let query = NSMetadataQuery()
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
    self.query = query
    observer = NotificationCenter.default.addObserver(
      forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
    ) { [weak self] _ in
      query.disableUpdates()
      var rows: [[String: Any]] = []
      for case let item as NSMetadataItem in query.results {
        guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
          url.deletingLastPathComponent().lastPathComponent == "sync",
          let name = item.value(forAttribute: NSMetadataItemFSNameKey) as? String
        else { continue }
        rows.append(Self.row(name, item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date))
      }
      self?.stopQuery()
      finished.call(rows)
    }
    guard query.start() else {
      stopQuery()
      fallbackList(finished)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
      guard !finished.done else { return }
      self?.stopQuery()
      self?.fallbackList(finished)
    }
  }

  private func stopQuery() {
    query?.stop()
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    query = nil
  }

  private func fallbackList(_ finished: OneShot) {
    queue.async {
      var rows: [[String: Any]] = []
      if let folder = Self.folder(),
        let urls = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
      {
        for url in urls {
          var name = url.lastPathComponent
          // Noch nicht geladene Dateien liegen als „.name.icloud“ im Ordner.
          if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
          }
          let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
          rows.append(Self.row(name, date))
        }
      }
      DispatchQueue.main.async { finished.call(rows) }
    }
  }

  private static func row(_ name: String, _ date: Date?) -> [String: Any] {
    var row: [String: Any] = ["name": name]
    if let date { row["modified"] = Int64(date.timeIntervalSince1970 * 1000) }
    return row
  }

  /// `nil`: Noch nicht geladen, der nächste Abgleich fragt erneut.
  private static func read(_ name: String) throws -> Data? {
    let target = try url(name)
    let fm = FileManager.default
    if fm.isUbiquitousItem(at: target) { try? fm.startDownloadingUbiquitousItem(at: target) }
    let deadline = Date().addingTimeInterval(downloadTimeout)
    while !isDownloaded(target) {
      if Date() > deadline { return nil }
      Thread.sleep(forTimeInterval: 0.5)
    }
    var coordination: NSError?
    var data: Data?
    var failure: Error?
    NSFileCoordinator().coordinate(readingItemAt: target, options: [], error: &coordination) { url in
      do { data = try Data(contentsOf: url) } catch { failure = error }
    }
    if let coordination { throw coordination }
    if let failure { throw failure }
    return data
  }

  private static func isDownloaded(_ url: URL) -> Bool {
    guard FileManager.default.isUbiquitousItem(at: url) else {
      return FileManager.default.fileExists(atPath: url.path)
    }
    let status = (try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
      .ubiquitousItemDownloadingStatus
    return status == .current || status == .downloaded
  }

  private static func write(_ name: String, _ bytes: Data) throws {
    let target = try url(name)
    var coordination: NSError?
    var failure: Error?
    NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordination) { url in
      do { try bytes.write(to: url, options: .atomic) } catch { failure = error }
    }
    if let coordination { throw coordination }
    if let failure { throw failure }
  }

  private static func delete(_ name: String) throws {
    let target = try url(name)
    var coordination: NSError?
    var failure: Error?
    NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &coordination) { url in
      do { try FileManager.default.removeItem(at: url) } catch { failure = error }
    }
    if let coordination { throw coordination }
    if let failure { throw failure }
  }
}

/// Eine Flutter-Antwort darf nur einmal kommen; läuft auf dem Hauptthread.
private final class OneShot {
  private let result: FlutterResult
  private(set) var done = false

  init(_ result: @escaping FlutterResult) { self.result = result }

  func call(_ value: Any?) {
    guard !done else { return }
    done = true
    result(value)
  }
}
