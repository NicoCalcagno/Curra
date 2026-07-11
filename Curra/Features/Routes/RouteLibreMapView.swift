import MapLibre
import SwiftUI

/// MapLibre-backed route map (OpenFreeMap style). Once a route's tile pack is
/// downloaded, the same view renders it with no network — MapKit is not used
/// here because it exposes no offline API.
struct RouteLibreMapView: UIViewRepresentable {
    let coordinates: [Coordinate]

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: OfflineMapService.styleURL)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = false
        mapView.attributionButton.isHidden = false

        if coordinates.count > 1 {
            var clCoordinates = coordinates.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            let polyline = MLNPolyline(coordinates: &clCoordinates, count: UInt(clCoordinates.count))
            mapView.addAnnotation(polyline)

            let bounds = OfflineMapService.boundingBox(of: coordinates, bufferDegrees: 0.002)
            mapView.setVisibleCoordinateBounds(
                bounds,
                edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                animated: false,
                completionHandler: nil
            )
        }
        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            .systemOrange
        }

        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            4
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            0.9
        }
    }
}
