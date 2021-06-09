@objc(MapboxNavigationManager)
class MapboxNavigationManager: RCTViewManager {
  override func view() -> UIView! {
    return MapboxNavigationView();
  }

  override static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc func triggerRerouteFromManager(_ node: NSNumber) {
    DispatchQueue.main.async {
      let component = self.bridge.uiManager.view(
        forReactTag: node
      ) as! MapboxNavigationView

      print(component)
      component.triggerReroute()
    }
  }
}
