//
//  Post.swift
//  FitSpo
//

import Foundation
import CoreLocation

struct Post: Identifiable, Codable {

    // ── Core fields ─────────────────────────────────────────────
    let id:        String
    let userId:    String
    let imageURL:  String
    let caption:   String
    let timestamp: Date
    var likes:     Int
    var isLiked:   Bool

    // ── Optional geo / weather ─────────────────────────────────
    let latitude:  Double?
    let longitude: Double?
    var  temp:     Double?

    // ── NEW 2.3 — hashtags array (lower-cased, no “#”) ─────────
    var hashtags: [String]

    // Convenience for MapKit
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, imageURL, caption, timestamp, likes, isLiked
        case latitude, longitude, temp, hashtags
    }
}
