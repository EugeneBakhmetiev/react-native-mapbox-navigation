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

  @objc var geojson: NSString = ""
  
  @objc var shouldSimulateRoute: Bool = false
  @objc var showsEndOfRouteFeedback: Bool = false
  
  @objc var onLocationChange: RCTDirectEventBlock?
  @objc var onRouteProgressChange: RCTDirectEventBlock?
  @objc var onError: RCTDirectEventBlock?
  @objc var onCancelNavigation: RCTDirectEventBlock?
  @objc var onArrive: RCTDirectEventBlock?
  @objc var onMarkerTap: RCTDirectEventBlock?
  @objc var onRerouteFinished: RCTDirectEventBlock?
  
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

    let options = NavigationRouteOptions(waypoints: [originWaypoint, destinationWaypoint, destinationWaypoint])
    options.allowsUTurnAtWaypoint = true

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

            let navigationOptions = NavigationOptions(navigationService: navigationService)

            let vc = NavigationViewController(for: route, routeIndex: 0, routeOptions: options, navigationOptions: navigationOptions)

            vc.showsEndOfRouteFeedback = strongSelf.showsEndOfRouteFeedback

            vc.delegate = strongSelf
                
//                vc.navigationService ? i think we can hot-swap nav service, needs testing

            strongSelf.navViewController?.view.removeFromSuperview()
            strongSelf.navViewController?.removeFromParent()
            
            print("---strongSelf.subviews---", strongSelf.subviews)

            parentVC.addChild(vc)
            strongSelf.addSubview(vc.view)

            vc.view.frame = strongSelf.bounds
            vc.didMove(toParent: parentVC)
            strongSelf.navViewController = vc
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
        drawRoutes()
        drawIcons()
    
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(sender:)))
//            for recognizer in navViewController?.mapView?.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
//                singleTap.require(toFail: recognizer)
//            }
        navViewController?.mapView?.addGestureRecognizer(singleTap)
        
        let styleLayer = MGLSymbolStyleLayer(identifier: identifier, source: source)
        return styleLayer
    }
    
    func drawRoutes() {
        guard let style = navViewController?.mapView?.style else {
            return
        }
        // step 1 -- check geojson length

        if geojson.length == 0 {
            return
        }

        guard let geojsonData = geojson.data(using: String.Encoding.utf8.rawValue) else {
            return
        }

        guard let shapeFromGeoJSON = try? MGLShape(data: geojsonData, encoding: String.Encoding.utf8.rawValue) else {
            fatalError("Could not generate MGLShape")
        }
        
        let sourceIdentifier = "geojsonSource"

        if let source = style.source(withIdentifier: sourceIdentifier) as? MGLShapeSource {
            source.shape = shapeFromGeoJSON
        } else {
            let source = MGLShapeSource(identifier: sourceIdentifier, shape: shapeFromGeoJSON, options: nil)
            let polylineLayer = MGLLineStyleLayer(identifier: "geojsonLayer", source: source)

            // Set the line join and cap to a rounded end.
            polylineLayer.lineJoin = NSExpression(forConstantValue: "round")
            polylineLayer.lineCap = NSExpression(forConstantValue: "round")
             
            // Set the line color to a constant blue color.
            polylineLayer.lineColor = NSExpression(forConstantValue: UIColor(red: 88/255, green: 168/255, blue: 252/255, alpha: 0.3))
             
            // Use `NSExpression` to smoothly adjust the line width from 2pt to 20pt between zoom levels 14 and 18. The `interpolationBase` parameter allows the values to interpolate along an exponential curve.
            polylineLayer.lineWidth = NSExpression(format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)",
                                                   [14: 8, 18: 20])
//                        polylineLayer.lineWidth = NSExpression(forConstantValue: 20)

            // We can also add a second layer that will draw a stroke around the original line.
            let casingLayer = MGLLineStyleLayer(identifier: "geojsonCasingLayer", source: source)
            // Copy these attributes from the main line layer.
            casingLayer.lineJoin = polylineLayer.lineJoin
            casingLayer.lineCap = polylineLayer.lineCap
            // Line gap width represents the space before the outline begins, so should match the main line’s line width exactly.
            casingLayer.lineGapWidth = polylineLayer.lineWidth
            // Stroke color slightly darker than the line color.
            casingLayer.lineColor = NSExpression(forConstantValue: UIColor(red: 44/255, green: 129/255, blue: 199/255, alpha: 0.5))
            // Use `NSExpression` to gradually increase the stroke width between zoom levels 14 and 18.
            casingLayer.lineWidth = NSExpression(format: "mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)", [14: 2, 18: 4])
//                        casingLayer.lineWidth = NSExpression(forConstantValue: 4)

            style.addSource(source)
//                        style.addLayer(polylineLayer)
            
            if let activeFeaturesLayer = style.layer(withIdentifier: "activeContainersLayer") {
                style.insertLayer(polylineLayer, below: activeFeaturesLayer)
            } else {
                style.addLayer(polylineLayer)
            }
            style.insertLayer(casingLayer, below: polylineLayer)
        }
    }
    
    func drawIcons() {
        // @todo check if we need to remove layers/sources and add new ones so that icons are updated when waypoint status changes
        if let style = self.navViewController?.mapView?.style {
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

                    if (pointType == "container" || pointType == "inquiry") {
                        switch pointStatus {
                            // maybe keep all geoJsons in a single dict, and use status/type combo as a key?
                            case "completed":
                                completedFeatures.append(newFeature)

                            case "connected_to_route":
                                activeFeatures.append(newFeature)

                            case "skipped":
                                completedFeatures.append(newFeature)
//                                skippedFeatures.append(newFeature)

                            default:
                                completedFeatures.append(newFeature)
//                                skippedFeatures.append(newFeature)

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
            
            if (pointType == "container" || pointType == "inquiry") {
                switch pointStatus {
                    // maybe keep all geoJsons in a single dict, and use status/type combo as a key?
                    case "completed":
                        completedFeatures.append(newFeature)

                    case "connected_to_route":
                        activeFeatures.append(newFeature)

                    case "skipped":
                        completedFeatures.append(newFeature)
//                        skippedFeatures.append(newFeature)

                    default:
                        completedFeatures.append(newFeature)
//                        skippedFeatures.append(newFeature)

                }
            } else {
                if pointType == "depot" {
                    depotFeatures.append(newFeature)
                } else {
                    wasteStationFeatures.append(newFeature)
                }
            }

            let polylineLayer = style.layer(withIdentifier: "geojsonLayer")

            if !activeFeatures.isEmpty {
                style.setImage(UIImage(named: "SkippedContainerIcon")!, forName: "activeContainer")

                if let iconSource = style.source(withIdentifier: "activeContainersSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: activeFeatures)

                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "activeContainersSource", features: activeFeatures, options: nil)

                    let symbols = MGLSymbolStyleLayer(identifier: "activeContainersLayer", source: iconSource)
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)

                    symbols.iconImageName = NSExpression(forConstantValue: "activeContainer")

                    style.addSource(iconSource)

                    if polylineLayer != nil {
                        style.insertLayer(symbols, above: polylineLayer.unsafelyUnwrapped)
                    } else {
                        style.addLayer(symbols)
                    }
                }
            }

//            if !skippedFeatures.isEmpty {
//                style.setImage(UIImage(named: "SkippedContainerIcon")!, forName: "skippedContainer")
//
//                if let iconSource = style.source(withIdentifier: "skippedContainersSource") as? MGLShapeSource {
//                    let collection = MGLShapeCollectionFeature(shapes: skippedFeatures)
//
//                    iconSource.shape = collection
//                } else {
//                    let iconSource = MGLShapeSource(identifier: "skippedContainersSource", features: skippedFeatures, options: nil)
//
//                    let symbols = MGLSymbolStyleLayer(identifier: "skippedContainersLayer", source: iconSource)
//
//                    symbols.iconImageName = NSExpression(forConstantValue: "skippedContainer")
//                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)
//
//                    style.addSource(iconSource)
//
//                    if polylineLayer != nil {
//                        style.insertLayer(symbols, above: polylineLayer.unsafelyUnwrapped)
//                    } else {
//                        style.addLayer(symbols)
//                    }
//                }
//            }
            
            if !completedFeatures.isEmpty {
                style.setImage(UIImage(named: "CompletedContainerIcon")!, forName: "completedContainer")

                if let iconSource = style.source(withIdentifier: "completedContainersSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: completedFeatures)

                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "completedContainersSource", features: completedFeatures, options: nil)

                    let symbols = MGLSymbolStyleLayer(identifier: "completedContainersLayer", source: iconSource)

                    symbols.iconImageName = NSExpression(forConstantValue: "completedContainer")
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)

                    style.addSource(iconSource)

                    if polylineLayer != nil {
                        style.insertLayer(symbols, above: polylineLayer.unsafelyUnwrapped)
                    } else {
                        style.addLayer(symbols)
                    }
                }
            }

            if !depotFeatures.isEmpty {
                style.setImage(UIImage(named: "DepotIcon")!, forName: "depot")

                if let iconSource = style.source(withIdentifier: "depotsSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: depotFeatures)

                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "depotsSource", features: depotFeatures, options: nil)

                    let symbols = MGLSymbolStyleLayer(identifier: "depotsLayer", source: iconSource)
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)

                    symbols.iconImageName = NSExpression(forConstantValue: "depot")

                    style.addSource(iconSource)

                    if polylineLayer != nil {
                        style.insertLayer(symbols, above: polylineLayer.unsafelyUnwrapped)
                    } else {
                        style.addLayer(symbols)
                    }
                }
            }

            if !wasteStationFeatures.isEmpty {
                style.setImage(UIImage(named: "WasteStationIcon")!, forName: "wasteStation")

                if let iconSource = style.source(withIdentifier: "wasteStationsSource") as? MGLShapeSource {
                    let collection = MGLShapeCollectionFeature(shapes: wasteStationFeatures)

                    iconSource.shape = collection
                } else {
                    let iconSource = MGLShapeSource(identifier: "wasteStationsSource", features: wasteStationFeatures, options: nil)

                    let symbols = MGLSymbolStyleLayer(identifier: "wasteStationsLayer", source: iconSource)
                    symbols.iconAllowsOverlap = NSExpression(forConstantValue: true)

                    symbols.iconImageName = NSExpression(forConstantValue: "wasteStation")

                    style.addSource(iconSource)

                    if polylineLayer != nil {
                        style.insertLayer(symbols, above: polylineLayer.unsafelyUnwrapped)
                    } else {
                        style.addLayer(symbols)
                    }
                }
            }
        }
    }

    // MARK: - Feature interaction
    @objc @IBAction func handleMapTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            // Limit feature selection to just the following layer identifiers.
//            let layerIdentifiers: Set = ["completedContainersLayer", "skippedContainersLayer", "activeContainersLayer", "wasteStationsLayer", "depotsLayer"]
            let layerIdentifiers: Set = ["completedContainersLayer", "activeContainersLayer", "wasteStationsLayer", "depotsLayer"]
         
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
        onMarkerTap?(["id": feature.attributes["id"] as? String])
//        let point = MGLPointFeature()
//        point.title = feature.attributes["name"] as? String
//        point.coordinate = feature.coordinate
         
        // Selecting an feature that doesn’t already exist on the map will add a new annotation view.
        // We’ll need to use the map’s delegate methods to add an empty annotation view and remove it when we’re done selecting it.
        // mapView.selectAnnotation(point, animated: true, completionHandler: nil)
    }

  @objc
    func triggerReroute(newGeojson: NSString) {
    print("--reroute triggered--")
    self.geojson = newGeojson

    embed();

    print("--rerouteFinished--")
    onRerouteFinished?([:]);

//    print("--geojson-- triggering reroute")
//    drawRoutes()
//    drawIcons()
  }

    @objc func triggerOverview() {
        print("--overview triggered-- camera pitch (before) =", navViewController?.mapView?.camera.pitch)

        if let mapView = self.navViewController?.mapView {
//            let newCamera = mapView.camera
//
//            newCamera.pitch = 0
//
//            mapView.camera = newCamera

//            mapView.lockedPitch = 0
            mapView.tracksUserCourse = true

            print("--overview triggered-- camera pitch (after) =", mapView.camera.pitch)
        }
    }
}

class InvisibleBottomBarViewController: ContainerViewController {}

class DefaultStyle: DayStyle {
    required init() {
        super.init()
        mapStyleURL = MGLStyle.lightStyleURL
   }
}
