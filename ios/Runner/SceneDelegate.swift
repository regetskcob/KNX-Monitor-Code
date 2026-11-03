import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // Kaltstart über eine Datei. Die Optionen lassen sich nicht filtern; die
    // Route, die Flutter daraus macht, verwirft IncomingFiles in Dart.
    KnxNative.shared.receive(connectionOptions.urlContexts.map(\.url).filter(\.isFileURL))
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    // Dateien an die App, alles andere (knxmonitor://) wie bisher an Flutter.
    let files = URLContexts.filter(\.url.isFileURL)
    KnxNative.shared.receive(files.map(\.url))
    let links = URLContexts.subtracting(files)
    if !links.isEmpty { super.scene(scene, openURLContexts: links) }
  }
}
