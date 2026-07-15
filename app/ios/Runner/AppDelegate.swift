import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let mapsAPIKey = DartDefines.mapsAPIKey(
      from: Bundle.main.infoDictionary,
      failClosed: DartDefines.isFailClosed()
    )
    if !mapsAPIKey.isEmpty {
      GMSServices.provideAPIKey(mapsAPIKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    LiveActivityPlugin.register(with: registrar(forPlugin: "LiveActivityPlugin")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
