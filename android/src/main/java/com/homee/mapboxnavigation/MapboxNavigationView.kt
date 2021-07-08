package com.homee.mapboxnavigation

import android.R.style
import android.graphics.Color
import android.location.Location
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.events.RCTEventEmitter
import com.google.gson.JsonObject
import com.mapbox.api.directions.v5.models.DirectionsRoute
import com.mapbox.api.directions.v5.models.RouteOptions
import com.mapbox.geojson.Feature
import com.mapbox.geojson.FeatureCollection
import com.mapbox.geojson.Point
import com.mapbox.mapboxsdk.Mapbox
import com.mapbox.mapboxsdk.camera.CameraPosition
import com.mapbox.mapboxsdk.geometry.LatLng
import com.mapbox.mapboxsdk.location.LocationComponentConstants
import com.mapbox.mapboxsdk.maps.MapView
import com.mapbox.mapboxsdk.maps.MapboxMap
import com.mapbox.mapboxsdk.style.layers.LineLayer
import com.mapbox.mapboxsdk.style.layers.Property
import com.mapbox.mapboxsdk.style.layers.PropertyFactory
import com.mapbox.mapboxsdk.style.layers.PropertyFactory.*
import com.mapbox.mapboxsdk.style.layers.SymbolLayer
import com.mapbox.mapboxsdk.style.sources.GeoJsonSource
import com.mapbox.navigation.base.internal.extensions.applyDefaultParams
import com.mapbox.navigation.base.internal.route.RouteUrl
import com.mapbox.navigation.base.trip.model.RouteProgress
import com.mapbox.navigation.core.MapboxNavigation
import com.mapbox.navigation.core.MapboxNavigationProvider
import com.mapbox.navigation.core.directions.session.RoutesRequestCallback
import com.mapbox.navigation.core.trip.session.LocationObserver
import com.mapbox.navigation.core.trip.session.RouteProgressObserver
import com.mapbox.navigation.ui.NavigationView
import com.mapbox.navigation.ui.NavigationViewOptions
import com.mapbox.navigation.ui.OnNavigationReadyCallback
import com.mapbox.navigation.ui.listeners.NavigationListener
import com.mapbox.navigation.ui.map.NavigationMapboxMap
import kotlin.math.sqrt


val locationLayers = setOf(
    LocationComponentConstants.ACCURACY_LAYER,
    LocationComponentConstants.BACKGROUND_LAYER,
    LocationComponentConstants.BEARING_LAYER,
    LocationComponentConstants.FOREGROUND_LAYER,
    LocationComponentConstants.PULSING_CIRCLE_LAYER,
    LocationComponentConstants.SHADOW_LAYER,
)


class MapboxNavigationView(private val context: ThemedReactContext) : NavigationView(context.baseContext), NavigationListener, OnNavigationReadyCallback, MapboxMap.OnMapClickListener {
    private var origin: Point? = null
    private var destination: PointWithProps? = null
    private var waypoints: List<PointWithProps?> = listOf()
    private var shouldSimulateRoute = false
    private var showsEndOfRouteFeedback = false
    private var language = "en"
    private var geojson = ""
    private lateinit var navigationMapboxMap: NavigationMapboxMap
    private lateinit var mapboxNavigation: MapboxNavigation

    private var mapboxMap: MapboxMap? = null

    init {
        onCreate(null)
        onResume()
        initialize(this, getInitialCameraPosition())
    }

    override fun requestLayout() {
        super.requestLayout()

        // This view relies on a measure + layout pass happening after it calls requestLayout().
        // https://github.com/facebook/react-native/issues/4990#issuecomment-180415510
        // https://stackoverflow.com/questions/39836356/react-native-resize-custom-ui-component
        post(measureAndLayout)
    }

    private val measureAndLayout = Runnable {
        measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
                MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
        layout(left, top, right, bottom)
    }

    private fun getInitialCameraPosition(): CameraPosition {
        return CameraPosition.Builder()
                .zoom(15.0)
                .build()
    }

    override fun onNavigationReady(isRunning: Boolean) {
        try {
            val accessToken = Mapbox.getAccessToken()
            if (accessToken == null) {
                sendErrorToReact("Mapbox access token is not set")
                return
            }

            if (origin == null || destination == null) {
                sendErrorToReact("origin and destination are required")
                return
            }

            if (::navigationMapboxMap.isInitialized) {
                return
            }

            if (this.retrieveNavigationMapboxMap() == null) {
                sendErrorToReact("retrieveNavigationMapboxMap() is null")
                return
            }

            this.navigationMapboxMap = this.retrieveNavigationMapboxMap()!!

            //this.retrieveMapboxNavigation()?.let { this.mapboxNavigation = it } // this does not work

            // fetch the route
            val navigationOptions = MapboxNavigation
                    .defaultNavigationOptionsBuilder(context, accessToken)
                    .isFromNavigationUi(true)
                    .build()
            this.mapboxNavigation = MapboxNavigationProvider.create(navigationOptions)
            this.mapboxNavigation.requestRoutes(RouteOptions.builder()
                    .applyDefaultParams()
                    .accessToken(accessToken)
                    .coordinates(mutableListOf(origin, destination!!.point))
                    .profile(RouteUrl.PROFILE_DRIVING)
                    .steps(true)
                    .language(this.language)
                    .voiceInstructions(true)
                    .build(), routesReqCallback)

            this.mapboxMap = this.navigationMapboxMap.retrieveMap()

//            val mapView = findViewById<MapView>(R.id.navigationMapView)
//
//            Log.d("MAPS", mapView.toString())

            if (mapboxMap!!.style != null) {
                val containerCompletedIconId = this.context.resources.getIdentifier(
                    "container_completed_icon",
                    "drawable",
                    this.context.packageName,
                )
                val containerSkippedIconId = this.context.resources.getIdentifier(
                    "container_skipped_icon",
                    "drawable",
                    this.context.packageName,
                )
                val wasteStationIconId = this.context.resources.getIdentifier(
                    "waste_station_icon",
                    "drawable",
                    this.context.packageName,
                )
                val depotIconId = this.context.resources.getIdentifier(
                    "depot_icon",
                    "drawable",
                    this.context.packageName,
                )

                val containerCompletedIconDrawable = this.context.resources.getDrawable(
                    containerCompletedIconId,
                    null,
                )
                val containerSkippedIconDrawable = this.context.resources.getDrawable(
                    containerSkippedIconId,
                    null,
                )
                val wasteStationIconDrawable = this.context.resources.getDrawable(
                    wasteStationIconId,
                    null,
                )
                val depotIconDrawable = this.context.resources.getDrawable(
                    depotIconId,
                    null,
                )

                mapboxMap!!.style!!.addImage("container_connected_to_route_icon", containerSkippedIconDrawable)
                mapboxMap!!.style!!.addImage("container_completed_icon", containerCompletedIconDrawable)
                mapboxMap!!.style!!.addImage("container_skipped_icon", containerCompletedIconDrawable)
                mapboxMap!!.style!!.addImage("waste_station_icon", wasteStationIconDrawable)
                mapboxMap!!.style!!.addImage("depot_icon", depotIconDrawable)

                val iconFeatureList: MutableList<Feature> = ArrayList()

                for (waypoint in this.waypoints) {
                    val properties = JsonObject()
                    var iconName = "${waypoint!!.type}_icon"

                    if (waypoint!!.type == "container" || waypoint!!.type == "inquiry") {
                        iconName = "container_${waypoint!!.status}_icon"
                    }

                    properties.addProperty("id", waypoint!!.id)
                    properties.addProperty("iconName", iconName)

                    iconFeatureList.add(Feature.fromGeometry(
                        waypoint!!.point,
                        properties,
                    ))
                }

                val iconsSource = GeoJsonSource("icons_source", FeatureCollection.fromFeatures(iconFeatureList))
                mapboxMap!!.style!!.addSource(iconsSource)

                val iconsLayer = SymbolLayer("icons_layer", "icons_source")
                    .withProperties(
                        iconImage("{iconName}"),
                        iconAllowOverlap(true),
                        iconIgnorePlacement(true)
                    )

                var found = false
                for (layer in mapboxMap!!.style!!.layers) {
                    if (locationLayers.contains(layer.id)) {
                        found = true
                        mapboxMap!!.style!!.addLayerBelow(iconsLayer, layer.id)

                        break
                    }
                }

                if (!found) {
                    mapboxMap!!.style!!.addLayer(iconsLayer)
                }

                val geoJsonFeatureCollection = FeatureCollection.fromJson(this.geojson)
                val geojsonSource = GeoJsonSource("geojson_source", geoJsonFeatureCollection)
                mapboxMap!!.style!!.addSource(geojsonSource)

                val geojsonLayer = LineLayer("geojson_layer", "geojson_source")
                    .withProperties(PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                        PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                        PropertyFactory.lineOpacity(.3f),
                        PropertyFactory.lineWidth(6f),
                        PropertyFactory.lineColor(Color.parseColor("#58a8fc")))

                val geojsonCasingLayer = LineLayer("geojson_casing_layer", "geojson_source")
                    .withProperties(PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                        PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                        PropertyFactory.lineOpacity(.5f),
                        PropertyFactory.lineGapWidth(6f),
                        PropertyFactory.lineColor(Color.parseColor("#2c81c7")))
                mapboxMap!!.style!!.addLayerBelow(geojsonLayer, "icons_layer")
                mapboxMap!!.style!!.addLayerBelow(geojsonCasingLayer, "icons_layer")

                mapboxMap!!.addOnMapClickListener(this)
            }
        } catch (ex: Exception) {
            sendErrorToReact(ex.toString())
        }
    }

    override fun onMapClick(point: LatLng): Boolean {
        val nearestMarker = this.waypoints.sortedBy {
            distance(point, it!!.point)
        }.take(1)[0]

        if (nearestMarker != null) {
            val event = Arguments.createMap()
            event.putString("id", nearestMarker.id)
            context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onMarkerTap", event)
        }

        return true
    }

    private fun distance(tapLocation: LatLng, waypoint: Point): Double {
        val distanceX = tapLocation.latitude - waypoint.latitude()
        val distanceY = tapLocation.longitude - waypoint.longitude()

        return sqrt(distanceX * distanceX + distanceY * distanceY)
    }

    private val routesReqCallback = object : RoutesRequestCallback {
        override fun onRoutesReady(routes: List<DirectionsRoute>) {
            if (routes.isEmpty()) {
                sendErrorToReact("No route found")
                return;
            }

            startNav(routes[0])
        }

        override fun onRoutesRequestFailure(throwable: Throwable, routeOptions: RouteOptions) {


        }

        override fun onRoutesRequestCanceled(routeOptions: RouteOptions) {

        }
    }

    private fun startNav(route: DirectionsRoute) {
        val optionsBuilder = NavigationViewOptions.builder(this.getContext())
        optionsBuilder.navigationListener(this)
        optionsBuilder.locationObserver(locationObserver)
        optionsBuilder.routeProgressObserver(routeProgressObserver)
        optionsBuilder.directionsRoute(route)
        optionsBuilder.shouldSimulateRoute(this.shouldSimulateRoute)
        optionsBuilder.waynameChipEnabled(true)
        this.startNavigation(optionsBuilder.build())
    }

    private val locationObserver = object : LocationObserver {
        override fun onRawLocationChanged(rawLocation: Location) {

        }

        override fun onEnhancedLocationChanged(
                enhancedLocation: Location,
                keyPoints: List<Location>
        ) {
            val event = Arguments.createMap()
            event.putDouble("longitude", enhancedLocation.longitude)
            event.putDouble("latitude", enhancedLocation.latitude)
            context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onLocationChange", event)
        }
    }


    private val routeProgressObserver = object : RouteProgressObserver {
        override fun onRouteProgressChanged(routeProgress: RouteProgress) {
            val event = Arguments.createMap()
            event.putDouble("distanceTraveled", routeProgress.distanceTraveled.toDouble())
            event.putDouble("durationRemaining", routeProgress.durationRemaining.toDouble())
            event.putDouble("fractionTraveled", routeProgress.fractionTraveled.toDouble())
            event.putDouble("distanceRemaining", routeProgress.distanceRemaining.toDouble())
            context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onRouteProgressChange", event)
        }
    }


    private fun sendErrorToReact(error: String?) {
        val event = Arguments.createMap()
        event.putString("error", error)
        context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onError", event)
    }

    override fun onNavigationRunning() {

    }

    override fun onFinalDestinationArrival(enableDetailedFeedbackFlowAfterTbt: Boolean, enableArrivalExperienceFeedback: Boolean) {
        super.onFinalDestinationArrival(this.showsEndOfRouteFeedback, this.showsEndOfRouteFeedback)
        val event = Arguments.createMap()
        event.putString("onArrive", "")
        context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onArrive", event)
    }

    override fun onNavigationFinished() {

    }

    override fun onCancelNavigation() {
        val event = Arguments.createMap()
        event.putString("onCancelNavigation", "Navigation Closed")
        context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onCancelNavigation", event)
    }

    override fun onDestroy() {
        this.stopNavigation()
        this.mapboxNavigation?.onDestroy()
        super.onDestroy()
    }

    override fun onStop() {
        super.onStop()
        this.mapboxNavigation?.unregisterLocationObserver(locationObserver)
    }

    fun setOrigin(origin: Point?) {
        this.origin = origin
    }

    fun setDestination(destination: PointWithProps?) {
        this.destination = destination
    }

    fun setShouldSimulateRoute(shouldSimulateRoute: Boolean) {
        this.shouldSimulateRoute = shouldSimulateRoute
    }

    fun setShowsEndOfRouteFeedback(showsEndOfRouteFeedback: Boolean) {
        this.showsEndOfRouteFeedback = showsEndOfRouteFeedback
    }

    fun setLanguage(language: String) {
        this.language = language
    }

    fun setGeojson(geojson: String) {
        this.geojson = geojson
    }

    fun setWaypoints(waypoints: List<PointWithProps?>) {
        this.waypoints = waypoints
    }

    fun triggerReroute() {
        try {
            val accessToken = Mapbox.getAccessToken()
            if (accessToken == null) {
                sendErrorToReact("Mapbox access token is not set")
                return
            }

            if (origin == null || destination == null) {
                sendErrorToReact("origin and destination are required")
                return
            }

            // fetch the route
            this.mapboxNavigation.requestRoutes(RouteOptions.builder()
                    .applyDefaultParams()
                    .accessToken(accessToken)
                    .coordinates(mutableListOf(origin, destination!!.point))
                    .profile(RouteUrl.PROFILE_DRIVING)
                    .steps(true)
                    .language(this.language)
                    .voiceInstructions(true)
                    .build(), routesReqCallback)

            val iconFeatureList: MutableList<Feature> = ArrayList()

            for (waypoint in this.waypoints) {
                val properties = JsonObject()
                var iconName = "${waypoint!!.type}_icon"

                if (waypoint!!.type == "container" || waypoint!!.type == "inquiry") {
                    iconName = "container_${waypoint!!.status}_icon"
                }

                properties.addProperty("id", waypoint!!.id)
                properties.addProperty("iconName", iconName)

                iconFeatureList.add(Feature.fromGeometry(
                        waypoint!!.point,
                        properties,
                ))
            }

            // cleanup
            mapboxMap!!.style!!.removeLayer("icons_layer")
            mapboxMap!!.style!!.removeSource("icons_source")

            val iconsSource = GeoJsonSource("icons_source", FeatureCollection.fromFeatures(iconFeatureList))
            val iconsLayer = SymbolLayer("icons_layer", "icons_source")
                .withProperties(
                    iconImage("{iconName}"),
                    iconAllowOverlap(true),
                    iconIgnorePlacement(true)
                )

            mapboxMap!!.style!!.addSource(iconsSource)
            var found = false
            for (layer in mapboxMap!!.style!!.layers) {
                if (locationLayers.contains(layer.id)) {
                    found = true
                    mapboxMap!!.style!!.addLayerBelow(iconsLayer, layer.id)

                    break
                }
            }

            if (!found) {
                mapboxMap!!.style!!.addLayer(iconsLayer)
            }

            mapboxMap!!.style!!.removeLayer("geojson_layer")
            mapboxMap!!.style!!.removeLayer("geojson_casing_layer")
            mapboxMap!!.style!!.removeSource("geojson_source")

            val geoJsonFeatureCollection = FeatureCollection.fromJson(this.geojson)
            val geojsonSource = GeoJsonSource("geojson_source", geoJsonFeatureCollection)
            val geojsonLayer = LineLayer("geojson_layer", "geojson_source")
                .withProperties(PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                    PropertyFactory.lineOpacity(.3f),
                    PropertyFactory.lineWidth(6f),
                    PropertyFactory.lineColor(Color.parseColor("#58a8fc")))

            val geojsonCasingLayer = LineLayer("geojson_casing_layer", "geojson_source")
                .withProperties(PropertyFactory.lineCap(Property.LINE_CAP_ROUND),
                    PropertyFactory.lineJoin(Property.LINE_JOIN_ROUND),
                    PropertyFactory.lineOpacity(.5f),
                    PropertyFactory.lineGapWidth(6f),
                    PropertyFactory.lineColor(Color.parseColor("#2c81c7")))

            mapboxMap!!.style!!.addSource(geojsonSource)
            mapboxMap!!.style!!.addLayerBelow(geojsonLayer, "icons_layer")
            mapboxMap!!.style!!.addLayerBelow(geojsonCasingLayer, "icons_layer")
        } catch (ex: Exception) {
            sendErrorToReact(ex.toString())
        } finally {
            val event = Arguments.createMap()
            context.getJSModule(RCTEventEmitter::class.java).receiveEvent(id, "onRerouteFinished", event)
        }
    }

    fun onDropViewInstance() {
        this.onDestroy()
    }
}

class PointWithProps {
    var point: Point
    var id: String
    var type: String
    var status: String

    constructor(point: Point, type: String, status: String, id: String) {
        this.point = point
        this.id = id
        this.type = type
        this.status = status
    }
}
