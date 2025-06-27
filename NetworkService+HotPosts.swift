//
//  NetworkService+HotPosts.swift
//  FitSpo
//

import FirebaseAuth
import FirebaseFirestore

extension NetworkService {
    struct HotPostsBundle {
        let posts: [Post]
        let lastDoc: DocumentSnapshot?
    }

    // MARK: – async API
    func fetchHotPostsPage(startAfter last: DocumentSnapshot?) async throws -> HotPostsBundle {
        try await withCheckedThrowingContinuation { cont in
            fetchHotPostsPage(startAfter: last) { cont.resume(with: $0) }
        }
    }

    // MARK: – closure API
    func fetchHotPostsPage(startAfter last: DocumentSnapshot?,
                           completion: @escaping (Result<HotPostsBundle, Error>) -> Void) {
        let twelveHoursAgo = Date().addingTimeInterval(-12 * 60 * 60)
        var q: Query = db.collection("posts")
            .whereField("timestamp", isGreaterThan: Timestamp(date: twelveHoursAgo))
            .order(by: "timestamp", descending: true)
            .limit(to: 50)
        if let last { q = q.start(afterDocument: last) }
        q.getDocuments { [weak self] snap, err in
            self?.mapHotSnapshot(snapshot: snap, error: err, completion: completion)
        }
    }

    private func mapHotSnapshot(snapshot snap: QuerySnapshot?,
                                error err: Error?,
                                completion: (Result<HotPostsBundle, Error>) -> Void) {
        if let err { completion(.failure(err)); return }
        guard let snap else {
            completion(.failure(NSError(domain: "HotPosts", code: 0,
                                        userInfo: [NSLocalizedDescriptionKey: "No snapshot"])))
            return
        }
        let me = Auth.auth().currentUser?.uid
        var seenUsers: Set<String> = []
        var hotPosts: [Post] = []
        for doc in snap.documents {
            let d = doc.data()
            guard
                let uid   = d["userId"]    as? String,
                let url   = d["imageURL"]  as? String,
                let cap   = d["caption"]   as? String,
                let ts    = d["timestamp"] as? Timestamp,
                let likes = d["likes"]     as? Int?
            else { continue }
            if seenUsers.contains(uid) { continue }
            let likedBy = d["likedBy"] as? [String] ?? []
            let post = Post(
                id:        doc.documentID,
                userId:    uid,
                imageURL:  url,
                caption:   cap,
                timestamp: ts.dateValue(),
                likes:     likes ?? 0,
                isLiked:   me.map { likedBy.contains($0) } ?? false,
                latitude:  d["latitude"]  as? Double,
                longitude: d["longitude"] as? Double,
                temp:      d["temp"]      as? Double,
                weatherIcon: d["weatherIcon"] as? String,
                hashtags:  d["hashtags"]  as? [String] ?? []
            )
            hotPosts.append(post)
            seenUsers.insert(uid)
        }
        hotPosts.sort {
            if $0.likes == $1.likes {
                return $0.timestamp > $1.timestamp
            } else {
                return $0.likes > $1.likes
            }
        }
        hotPosts = Array(hotPosts.prefix(10))
        completion(.success(.init(posts: hotPosts, lastDoc: snap.documents.last)))
    }
}
