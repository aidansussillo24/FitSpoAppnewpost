//
//  Post.swift
//  FitSpo
//

import Foundation
import CoreLocation

struct Post: Identifiable, Codable {

    // core
    let id:        String
    let userId:    String
    let imageURL:  String
    let caption:   String
    let timestamp: Date
    var likes:     Int
    var isLiked:   Bool

    // geo / weather
    let latitude:    Double?
    let longitude:   Double?
    var  temp:       Double?
    var  weatherIcon: String?

    // outfit
    var outfitItems: [OutfitItem]? = nil
    var outfitTags : [OutfitTag]?  = nil        // ← NEW

    // hashtags
    var hashtags: [String]

    // convenience
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Map OpenWeather icon → SF Symbol name
    var weatherSymbolName: String? {
        guard let icon = weatherIcon else { return nil }
        let day = icon.hasSuffix("d")
        switch String(icon.prefix(2)) {
        case "01": return day ? "sun.max" : "moon"
        case "02": return day ? "cloud.sun" : "cloud.moon"
        case "03", "04": return "cloud"
        case "09": return "cloud.drizzle"
        case "10": return "cloud.rain"
        case "11": return "cloud.bolt"
        case "13": return "snow"
        case "50": return "cloud.fog"
        default: return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, userId, imageURL, caption, timestamp, likes, isLiked
        case latitude, longitude, temp, weatherIcon, hashtags
        case outfitItems, outfitTags
    }
}
