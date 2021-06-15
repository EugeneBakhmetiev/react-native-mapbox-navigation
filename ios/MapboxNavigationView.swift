import Mapbox
import MapboxCoreNavigation
import MapboxDirections
import MapboxNavigation

// adapted from https://pspdfkit.com/blog/2017/native-view-controllers-and-react-native/ and https://github.com/mslabenyak/react-native-mapbox-navigation/blob/master/ios/Mapbox/MapboxNavigationView.swift
extension UIView {
  var parentViewController: UIViewController? {
    var parentResponder: UIResponder? = self
    while parentResponder != nil {
      parentResponder = parentResponder!.next
      if let viewController = parentResponder as? UIViewController {
        return viewController
      }
    }
    return nil
  }
}

extension MGLMapViewDelegate {
    func mapView(_ mapView: MGLMapView, didDeselect annotation: MGLAnnotation) {
        print("---- didSelect ----")
    }
    
    func mapView(_ mapView: MGLMapView, didDeselect waypoint: Waypoint) {
        print("---- didSelect waypoint ----")
    }

}

extension NavigationMapViewDelegate {
    func navigationMapView(_ mapView: NavigationMapView, didDeselect annotation: MGLAnnotation) {
        print("---- didSelect nm ----")
    }
    
    func navigationMapView(_ mapView: NavigationMapView, didSelect waypoint: Waypoint) {
        print("---- didSelect waypoint nm ----")
    }

    func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        print("---- didSelect route nm ----")
    }
}

class MapboxNavigationView: UIView, NavigationViewControllerDelegate {
  weak var navViewController: NavigationViewController?
  var embedded: Bool
  var embedding: Bool
  
  @objc var origin: NSArray = [] {
    didSet { setNeedsLayout() }
  }
  
  @objc var destination: NSArray = [] {
    didSet { setNeedsLayout() }
  }

  @objc var waypoints: NSArray = [] {
    didSet { setNeedsLayout() }
  }
  
  @objc var shouldSimulateRoute: Bool = false
  @objc var showsEndOfRouteFeedback: Bool = false
  
  @objc var onLocationChange: RCTDirectEventBlock?
  @objc var onRouteProgressChange: RCTDirectEventBlock?
  @objc var onError: RCTDirectEventBlock?
  @objc var onCancelNavigation: RCTDirectEventBlock?
  @objc var onArrive: RCTDirectEventBlock?
  @objc var onMarkerTap: RCTDirectEventBlock?
  
  override init(frame: CGRect) {
    self.embedded = false
    self.embedding = false
    super.init(frame: frame)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    if (navViewController == nil && !embedding && !embedded) {
      embed()
    } else {
      navViewController?.view.frame = bounds
    }
  }
  
  override func removeFromSuperview() {
    super.removeFromSuperview()
    // cleanup and teardown any existing resources
    self.navViewController?.removeFromParent()
  }
  
  private func embed() {
    guard origin.count == 2 && destination.count == 5 else { return }
    
    embedding = true

    let originWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: origin[1] as! CLLocationDegrees, longitude: origin[0] as! CLLocationDegrees))
    let destinationWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: destination[1] as! CLLocationDegrees, longitude: destination[0] as! CLLocationDegrees))

    var intermediateWaypoints: [Waypoint] = [originWaypoint]

    waypoints.compactMap { $0 as? NSArray }
        .forEach { point in
            intermediateWaypoints.append(Waypoint(coordinate: CLLocationCoordinate2D(latitude: point[1] as! CLLocationDegrees, longitude: point[0] as! CLLocationDegrees)))
        }
    
    intermediateWaypoints.append(destinationWaypoint)
    
    let options = NavigationRouteOptions(waypoints: intermediateWaypoints)
    
    Directions.shared.calculate(options) { [weak self] (session, result) in
      guard let strongSelf = self, let parentVC = strongSelf.parentViewController else {
        return
      }
      
      switch result {
        case .failure(let error):
          strongSelf.onError!(["message": error.localizedDescription])
        case .success(let response):
          guard let route = response.routes?.first else {
            return
          }
          
          let navigationService = MapboxNavigationService(route: route, routeIndex: 0, routeOptions: options, simulating: strongSelf.shouldSimulateRoute ? .always : .never)
          
//          let bottomBannerView = InvisibleBottomBarViewController()

//          let navigationOptions = NavigationOptions(navigationService: navigationService, bottomBanner: bottomBannerView)
            
//          let style = DefaultStyle()
//            let style = MGLStyle()
//
//            let point = MGLPointAnnotation()
//            point.coordinate = CLLocationCoordinate2D(latitude: destinationWaypoint.coordinate.latitude, longitude: destinationWaypoint.coordinate.longitude)
//
//            // Create a data source to hold the point data
//            let shapeSource = MGLShapeSource(identifier: "marker-source", shape: point, options: nil)
//
//            // Create a style layer for the symbol
//            let shapeLayer = MGLSymbolStyleLayer(identifier: "marker-style", source: shapeSource)
//
//            // Add the image to the style's sprite
//            if let image = UIImage(named: "ContainerIcon") {
//                style.setImage(image, forName: "ContainerSymbol")
//            }
//
//            // Tell the layer to use the image in the sprite
//            shapeLayer.iconImageName = NSExpression(forConstantValue: "ContainerSymbol")
//
//            // Add the source and style layer to the map
//            style.addSource(shapeSource)
//            style.addLayer(shapeLayer)

//            let navigationOptions = NavigationOptions(styles: [style], navigationService: navigationService)
            let navigationOptions = NavigationOptions(navigationService: navigationService)
            
            let vc = NavigationViewController(for: route, routeIndex: 0, routeOptions: options, navigationOptions: navigationOptions)

          vc.showsEndOfRouteFeedback = strongSelf.showsEndOfRouteFeedback
          
          vc.delegate = strongSelf
        
          parentVC.addChild(vc)
          strongSelf.addSubview(vc.view)
          vc.view.frame = strongSelf.bounds
          vc.didMove(toParent: parentVC)
          strongSelf.navViewController = vc
                      
//            vc.mapView?.styleURL = MGLStyle.lightStyleURL

            print("---- before style ----")
            if let style = vc.mapView?.style {
                print("---- style is present ----", style)
                // Create point to represent where the symbol should be placed
                let point = MGLPointAnnotation()
                point.coordinate = CLLocationCoordinate2D(latitude: destinationWaypoint.coordinate.latitude, longitude: destinationWaypoint.coordinate.longitude)
                 
                // Create a data source to hold the point data
                let shapeSource = MGLShapeSource(identifier: "marker-source", shape: point, options: nil)
                 
                // Create a style layer for the symbol
                let shapeLayer = MGLSymbolStyleLayer(identifier: "marker-style", source: shapeSource)
                 
                // Add the image to the style's sprite
                if let image = UIImage(named: "ContainerIcon") {
                    style.setImage(image, forName: "ContainerSymbol")
                }
                 
                // Tell the layer to use the image in the sprite
                shapeLayer.iconImageName = NSExpression(forConstantValue: "ContainerSymbol")
                 
                // Add the source and style layer to the map
                style.addSource(shapeSource)
                style.addLayer(shapeLayer)
            }

      }
      
      strongSelf.embedding = false
      strongSelf.embedded = true
    }
  }
  
  func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
    onLocationChange?(["longitude": location.coordinate.longitude, "latitude": location.coordinate.latitude])
    onRouteProgressChange?(["distanceTraveled": progress.distanceTraveled,
                            "durationRemaining": progress.durationRemaining,
                            "fractionTraveled": progress.fractionTraveled,
                            "distanceRemaining": progress.distanceRemaining])
  }
  
  func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
    if (!canceled) {
      return;
    }
    
    onCancelNavigation?(["message": ""]);
  }
  
  func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
    onArrive?(["message": ""]);
    return true;
  }
    
//    func navigationViewController(_ navigationViewController: NavigationViewController, waypointStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
    func navigationViewController(_ navigationViewController: NavigationViewController, waypointSymbolStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
        let styleLayer = MGLSymbolStyleLayer(identifier: identifier, source: source)
        return styleLayer
    }


//    func navigationViewController(_ navigationViewController: NavigationViewController, waypointSymbolStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
    func navigationViewController(_ navigationViewController: NavigationViewController, waypointStyleLayerWithIdentifier identifier: String, source: MGLSource) -> MGLStyleLayer? {
        if let style = self.navViewController?.mapView?.style {

            
//            var activeContainerFeatures: [Any] = []
//            var completedContainerFeatures: [Any] = []
//            var skippedContainerFeatures: [Any] = []
            
            var activeFeatures: [MGLPointFeature] = []
            var skippedFeatures: [MGLPointFeature] = []
            var completedFeatures: [MGLPointFeature] = []
            var wasteStationFeatures: [MGLPointFeature] = []
            var depotFeatures: [MGLPointFeature] = []
            
            waypoints.compactMap { $0 as? NSArray }
                .forEach { point in
                    let pointType = point[2] as! String
                    let pointStatus = point[3] as! String
                    let pickupOrderId = point[4] as! String

                    let coordinate = CLLocationCoordinate2D(latitude: point[1] as! CLLocationDegrees, longitude: point[0] as! CLLocationDegrees)
                    let newFeature = MGLPointFeature()
                    newFeature.coordinate = coordinate
                    // A feature’s attributes can used by runtime styling for things like text labels.
                    newFeature.attributes = [
//                            "type": pointType,
//                            "status": pointStatus,
                        "id": pickupOrderId
                    ]

                    print("---- point info ----", pointType, pointStatus)
                    
                    if pointType == "container" {
                        switch pointStatus {
                            // maybe keep all geoJsons in a single dict, and use status/type combo as a key?
                            case "completed":
                                print("---- container completed ----")
                                completedFeatures.append(newFeature)

                            case "connected_to_route":
                                print("---- container active ----")
                                activeFeatures.append(newFeature)

                            case "skipped":
                                print("---- container skipped ----")
                                skippedFeatures.append(newFeature)

                            default:
                                print("---- container default ----")
                                skippedFeatures.append(newFeature)

                        }
                    } else {
                        if pointType == "depot" {
                            depotFeatures.append(newFeature)
                        } else {
                            wasteStationFeatures.append(newFeature)
                        }
                    }
                }
            
            let pointType = destination[2] as! String
            let pointStatus = destination[3] as! String
            let pickupOrderId = destination[4] as! String

            let coordinate = CLLocationCoordinate2D(latitude: destination[1] as! CLLocationDegrees, longitude: destination[0] as! CLLocationDegrees)
            let newFeature = MGLPointFeature()
            newFeature.coordinate = coordinate
            // A feature’s attributes can used by runtime styling for things like text labels.
            newFeature.attributes = [
//                            "type": pointType,
//                            "status": pointStatus,
                "id": pickupOrderId
            ]
            print("---- dest ----", pointType, pointStatus)
            
            if pointType == "container" {
                switch pointStatus {
                    // maybe keep all geoJsons in a single dict, and use status/type combo as a key?
                    case "completed":
                        print("---- container completed ----")
                        completedFeatures.append(newFeature)

                    case "connected_to_route":
                        print("---- container active ----")
                        activeFeatures.append(newFeature)

                    case "skipped":
                        print("---- container skipped ----")
                        skippedFeatures.append(newFeature)

                    default:
                        print("---- container default ----")
                        skippedFeatures.append(newFeature)

                }
            } else {
                if pointType == "depot" {
                    depotFeatures.append(newFeature)
                } else {
                    wasteStationFeatures.append(newFeature)
                }
            }

//            activeContainers["features"] = activeContainerFeatures
//            completedContainers["features"] = completedContainerFeatures
            
//            print("---- activeContainers ----", activeContainers)
            if !activeFeatures.isEmpty {
                print("---- activeFeatures ----", activeFeatures)

                style.setImage(UIImage(named: "ContainerIcon")!, forName: "activeContainer")
                
                let iconSource = MGLShapeSource(identifier: "activeContainersSource", features: activeFeatures, options: nil)
                
                let symbols = MGLSymbolStyleLayer(identifier: "activeContainersLayer", source: iconSource)

                symbols.iconImageName = NSExpression(forConstantValue: "activeContainer")

                style.addSource(iconSource)
                style.addLayer(symbols)
            }

            if !skippedFeatures.isEmpty {
                print("---- skippedFeatures ----", skippedFeatures)

                style.setImage(UIImage(named: "SkippedContainerIcon")!, forName: "skippedContainer")
                
                let iconSource = MGLShapeSource(identifier: "skippedContainersSource", features: skippedFeatures, options: nil)
                
                let symbols = MGLSymbolStyleLayer(identifier: "skippedContainersLayer", source: iconSource)

                symbols.iconImageName = NSExpression(forConstantValue: "skippedContainer")

                style.addSource(iconSource)
                style.addLayer(symbols)
            }
            
            if !completedFeatures.isEmpty {
                print("---- completedFeatures ----", completedFeatures)

                style.setImage(UIImage(named: "CompletedContainerIcon")!, forName: "completedContainer")
                
                let iconSource = MGLShapeSource(identifier: "completedContainersSource", features: completedFeatures, options: nil)
                
                let symbols = MGLSymbolStyleLayer(identifier: "completedContainersLayer", source: iconSource)

                symbols.iconImageName = NSExpression(forConstantValue: "completedContainer")

                style.addSource(iconSource)
                style.addLayer(symbols)
            }

            if !depotFeatures.isEmpty {
                print("---- depotFeatures ----", depotFeatures)

                style.setImage(UIImage(named: "DepotIcon")!, forName: "depot")
                
                let iconSource = MGLShapeSource(identifier: "depotsSource", features: depotFeatures, options: nil)
                
                let symbols = MGLSymbolStyleLayer(identifier: "depotsLayer", source: iconSource)

                symbols.iconImageName = NSExpression(forConstantValue: "depot")

                style.addSource(iconSource)
                style.addLayer(symbols)
            }

            if !wasteStationFeatures.isEmpty {
                print("---- wasteStationFeatures ----", wasteStationFeatures)

                style.setImage(UIImage(named: "WasteStationIcon")!, forName: "wasteStation")
                
                let iconSource = MGLShapeSource(identifier: "wasteStationsSource", features: wasteStationFeatures, options: nil)
                
                let symbols = MGLSymbolStyleLayer(identifier: "wasteStationsLayer", source: iconSource)

                symbols.iconImageName = NSExpression(forConstantValue: "wasteStation")

                style.addSource(iconSource)
                style.addLayer(symbols)
            }

//            print("---- completedContainers ----", completedContainers)
//            if let completedData = try? JSONSerialization.data(withJSONObject: completedContainers, options: .prettyPrinted) {
//                print("---- completedData ----", completedData)
//                style.setImage(UIImage(named: "CompletedContainerIcon")!, forName: "completedContainer")
//
//                guard let shapeFromGeoJSON = try? MGLShape(data: completedData, encoding: String.Encoding.utf8.rawValue) else {
//                    fatalError("Could not generate MGLShape")
//                }
//
//                let iconSource = MGLShapeSource(identifier: "completedContainersSource", shape: shapeFromGeoJSON, options: nil)
//
//                let symbols = MGLSymbolStyleLayer(identifier: "completedContainersLayer", source: iconSource)
//
//                symbols.iconImageName = NSExpression(forConstantValue: "completedContainer")
//
//                style.addSource(iconSource)
//                style.addLayer(symbols)
//            }
            
            print("---- here ----")
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(sender:)))
            print("---- here 2 ----", #selector(handleMapTap(sender:)))
//            for recognizer in navViewController?.mapView?.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
//                singleTap.require(toFail: recognizer)
//            }
            print("---- here 3 ----")
            navViewController?.mapView?.addGestureRecognizer(singleTap)
        }
        
        let styleLayer = MGLSymbolStyleLayer(identifier: identifier, source: source)

        return styleLayer
    }

    // MARK: - Feature interaction
    @objc @IBAction func handleMapTap(sender: UITapGestureRecognizer) {
        print("---- TAP ----")
        if sender.state == .ended {
            // Limit feature selection to just the following layer identifiers.
            let layerIdentifiers: Set = ["completedContainersLayer", "skippedContainersLayer", "activeContainersLayer", "wasteStationsLayer", "depotsLayer"]
         
            // Try matching the exact point first.
            let point = sender.location(in: sender.view!)
            for feature in navViewController?.mapView?.visibleFeatures(at: point, styleLayerIdentifiers: layerIdentifiers) ?? []
                where feature is MGLPointFeature {
                    guard let selectedFeature = feature as? MGLPointFeature else {
                        fatalError("Failed to cast selected feature as MGLPointFeature")
                    }
                    showCallout(feature: selectedFeature)
                    return
                }
             
            let touchCoordinate = navViewController?.mapView?.convert(point, toCoordinateFrom: sender.view!)
            let touchLocation = CLLocation(latitude: touchCoordinate!.latitude, longitude: touchCoordinate!.longitude)
             
            // Otherwise, get all features within a rect the size of a touch (44x44).
            let touchRect = CGRect(origin: point, size: .zero).insetBy(dx: -22.0, dy: -22.0)
            let possibleFeatures = navViewController?.mapView?.visibleFeatures(in: touchRect, styleLayerIdentifiers: Set(layerIdentifiers)).filter { $0 is MGLPointFeature } ?? []
             
            // Select the closest feature to the touch center.
            let closestFeatures = possibleFeatures.sorted(by: {
                return CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: touchLocation) < CLLocation(latitude: $1.coordinate.latitude, longitude: $1.coordinate.longitude).distance(from: touchLocation)
            })
            if let feature = closestFeatures.first {
                guard let closestFeature = feature as? MGLPointFeature else {
                    fatalError("Failed to cast selected feature as MGLPointFeature")
                }
                showCallout(feature: closestFeature)
                return
            }
         
            // If no features were found, deselect the selected annotation, if any.
//            navViewController?.mapView?.deselectAnnotation(navViewController?.mapView?.selectedAnnotations.first, animated: true)
        }
    }
     
    func showCallout(feature: MGLPointFeature) {
        print("---- point tapped ----", feature.attributes["id"] as? String)
        onMarkerTap?(["id": feature.attributes["id"] as? String])

        // Selecting an feature that doesn’t already exist on the map will add a new annotation view.
        // We’ll need to use the map’s delegate methods to add an empty annotation view and remove it when we’re done selecting it.
        // mapView.selectAnnotation(point, animated: true, completionHandler: nil)
    }

  @objc
  func triggerReroute() {
    embed();
  }
}

class InvisibleBottomBarViewController: ContainerViewController {}

class DefaultStyle: DayStyle {
    required init() {
        super.init()
        mapStyleURL = MGLStyle.lightStyleURL
   }
}
