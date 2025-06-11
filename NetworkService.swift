//  Replace file: NetworkService.swift
//  FitSpo
//
//  COMPLETE, up-to-date implementation.
//
//  • Adds lowercase helper fields (`username_lc`, `displayName_lc`) when a
//    profile is first created so search remains fast once you switch back to
//    server-side prefix queries.
//  • Introduces simple reachability with `NWPathMonitor` and the static
//    flag `isOnline`, which `ExploreView` waits on during cold-start.
//  • Preserves ALL of your existing post / follow / helper methods.
//
//  Copy-and-paste this ENTIRE file over the old NetworkService.swift.

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Network            // ← reachability
import UIKit

/// Central Firebase + Storage + network helper
final class NetworkService {

    // MARK: – Shared instance & reachability -----------------------------
    static let shared = NetworkService()
    private init() { startPathMonitor() }

    private let monitor = NWPathMonitor()
    private let queue   = DispatchQueue(label: "FitSpo.NetMonitor")
    private var pathStatus: NWPath.Status = .satisfied

    /// True when the device currently has an internet path.
    static var isOnline: Bool { shared.pathStatus == .satisfied }

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathStatus = path.status
        }
        monitor.start(queue: queue)
    }

    // MARK: – Firebase handles ------------------------------------------
    let db      = Firestore.firestore()
    private let storage = Storage.storage().reference()

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Create User Profile
    // ────────────────────────────────────────────────────────────────────
    /// Persists a new user doc and writes lowercase helper fields.
    func createUserProfile(userId: String,
                           data: [String: Any]) async throws {

        var d = data
        if let username = data["username"] as? String {
            d["username_lc"] = username.lowercased()
        }
        if let name = data["displayName"] as? String {
            d["displayName_lc"] = name.lowercased()
        }

        try await db.collection("users")
            .document(userId)
            .setData(d)
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Upload Post (stores hashtags[])
    // ────────────────────────────────────────────────────────────────────
    func uploadPost(
        image: UIImage,
        caption: String,
        latitude: Double?,
        longitude: Double?,
        completion: @escaping (Result<Void,Error>) -> Void
    ) {
        guard let me = Auth.auth().currentUser else {
            return completion(.failure(Self.authError()))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else {
            return completion(.failure(Self.imageError()))
        }

        let imgID = UUID().uuidString
        let ref   = storage.child("post_images/\(imgID).jpg")

        ref.putData(jpeg, metadata: nil) { [weak self] _, err in
            if let err { return completion(.failure(err)) }

            ref.downloadURL { url, err in
                if let err { return completion(.failure(err)) }
                guard let url else {
                    return completion(.failure(Self.storageURLError()))
                }

                var post: [String:Any] = [
                    "userId"   : me.uid,
                    "imageURL" : url.absoluteString,
                    "caption"  : caption,
                    "timestamp": Timestamp(date: Date()),
                    "likes"    : 0,
                    "isLiked"  : false,
                    "hashtags" : Self.extractHashtags(from: caption)
                ]
                if let latitude  { post["latitude"]  = latitude  }
                if let longitude { post["longitude"] = longitude }

                self?.db.collection("posts")
                    .addDocument(data: post) { err in
                        err == nil ? completion(.success(()))
                                   : completion(.failure(err!))
                    }
            }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Fetch Posts (home feed)
    // ────────────────────────────────────────────────────────────────────
    func fetchPosts(completion: @escaping (Result<[Post],Error>) -> Void) {
        db.collection("posts")
          .order(by: "timestamp", descending: true)
          .getDocuments { snap, err in
              if let err { completion(.failure(err)); return }
              let posts = snap?.documents.compactMap(Self.decodePost) ?? []
              completion(.success(posts))
          }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Toggle Like
    // ────────────────────────────────────────────────────────────────────
    func toggleLike(post: Post,
                    completion: @escaping (Result<Post,Error>) -> Void) {
        let ref      = db.collection("posts").document(post.id)
        let delta    = post.isLiked ? -1 : 1
        let newLikes = post.likes + delta
        let newLiked = !post.isLiked

        ref.updateData([
            "likes"  : newLikes,
            "isLiked": newLiked
        ]) { err in
            if let err { completion(.failure(err)); return }
            var updated = post
            updated.likes   = newLikes
            updated.isLiked = newLiked
            completion(.success(updated))
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Delete Post (Firestore doc + Storage asset)
    // ────────────────────────────────────────────────────────────────────
    func deletePost(id: String,
                    completion: @escaping (Result<Void,Error>) -> Void) {
        let ref = db.collection("posts").document(id)
        ref.getDocument { snap, err in
            if let err { return completion(.failure(err)) }

            guard let d  = snap?.data(),
                  let str = d["imageURL"] as? String,
                  let url = URL(string: str)
            else {                                  // no image URL → delete doc only
                ref.delete { err in
                    err == nil ? completion(.success(()))
                               : completion(.failure(err!))
                }
                return
            }

            Storage.storage()
                .reference(withPath: url.path.dropFirst().description)
                .delete { _ in
                    ref.delete { err in
                        err == nil ? completion(.success(()))
                                   : completion(.failure(err!))
                    }
                }
        }
    }

    // ────────────────────────────────────────────────────────────────────
    // MARK:  Follow / Unfollow / Counts
    // ────────────────────────────────────────────────────────────────────
    func follow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        let follower  = db.collection("users").document(userId)
                          .collection("followers").document(me)
        let following = db.collection("users").document(me)
                          .collection("following").document(userId)
        batch.setData([:], forDocument: follower)
        batch.setData([:], forDocument: following)
        batch.commit(completion: completion)
    }

    func unfollow(userId: String, completion: @escaping (Error?) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(Self.authError())
        }
        let batch = db.batch()
        let follower  = db.collection("users").document(userId)
                          .collection("followers").document(me)
        let following = db.collection("users").document(me)
                          .collection("following").document(userId)
        batch.deleteDocument(follower)
        batch.deleteDocument(following)
        batch.commit(completion: completion)
    }

    func isFollowing(userId: String,
                     completion: @escaping (Result<Bool,Error>) -> Void) {
        guard let me = Auth.auth().currentUser?.uid else {
            return completion(.failure(Self.authError()))
        }
        db.collection("users").document(userId)
          .collection("followers").document(me)
          .getDocument { snap, err in
              if let err { completion(.failure(err)); return }
              completion(.success(snap?.exists == true))
          }
    }

    func fetchFollowCount(userId: String,
                          type: String,
                          completion: @escaping (Result<Int,Error>) -> Void) {
        db.collection("users").document(userId)
          .collection(type)
          .getDocuments { snap, err in
              if let err { completion(.failure(err)); return }
              completion(.success(snap?.documents.count ?? 0))
          }
    }

    // ==================================================================
    // MARK:  Private helpers
    // ==================================================================

    /// `#hashtag` extractor (case-insensitive, deduped, lower-cased)
    private static func extractHashtags(from caption: String) -> [String] {
        let pattern = "(?:\\s|^)#(\\w+)"
        guard let rx = try? NSRegularExpression(pattern: pattern,
                                                options: .caseInsensitive)
        else { return [] }

        let nsRange = NSRange(caption.startIndex..., in: caption)
        let matches = rx.matches(in: caption, range: nsRange)
        let tags = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: caption) else { return nil }
            return caption[r].lowercased()
        }
        return Array(Set(tags))
    }

    // Quick NSError helpers
    private static func authError() -> NSError {
        NSError(domain: "Auth", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
    }
    private static func imageError() -> NSError {
        NSError(domain: "Image", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Image conversion failed"])
    }
    private static func storageURLError() -> NSError {
        NSError(domain: "Storage", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No download URL"])
    }

    /// Shared doc→Post mapping used by both home-feed and Explore queries
    fileprivate static func decodePost(doc: QueryDocumentSnapshot) -> Post? {
        let d = doc.data()
        guard
            let uid       = d["userId"]    as? String,
            let imageURL  = d["imageURL"]  as? String,
            let caption   = d["caption"]   as? String,
            let ts        = d["timestamp"] as? Timestamp,
            let likes     = d["likes"]     as? Int,
            let isLiked   = d["isLiked"]   as? Bool
        else { return nil }

        return Post(
            id:        doc.documentID,
            userId:    uid,
            imageURL:  imageURL,
            caption:   caption,
            timestamp: ts.dateValue(),
            likes:     likes,
            isLiked:   isLiked,
            latitude:  d["latitude"]  as? Double,
            longitude: d["longitude"] as? Double,
            temp:      d["temp"]      as? Double,
            hashtags:  d["hashtags"]  as? [String] ?? []
        )
    }
}
