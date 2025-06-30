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
    func fetchHotPostsPage(startAfter last: DocumentSnapshot?,
                           limit: Int = 100) async throws -> HotPostsBundle {
        try await withCheckedThrowingContinuation { cont in
            fetchHotPostsPage(startAfter: last, limit: limit) { cont.resume(with: $0) }
        }
    }

    // MARK: – closure API
    func fetchHotPostsPage(startAfter last: DocumentSnapshot?,
                           limit: Int = 100,
                           completion: @escaping (Result<HotPostsBundle, Error>) -> Void) {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        var q: Query = db.collection("posts")
            .whereField("timestamp", isGreaterThan: Timestamp(date: startOfToday))
            .order(by: "timestamp", descending: true)
            .order(by: "likes", descending: true)
            .limit(to: limit)
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
        var hotPosts: [(Post, Int)] = []
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
            let commentCount = d["commentsCount"] as? Int ?? 0
            let shareCount   = d["sharesCount"]   as? Int ?? 0
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
            let rating = (likes ?? 0) + commentCount + shareCount
            hotPosts.append((post, rating))
            seenUsers.insert(uid)
        }
        hotPosts.sort { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.timestamp > rhs.0.timestamp
            } else {
                return lhs.1 > rhs.1
            }
        }
        completion(.success(.init(posts: hotPosts.map(\.0), lastDoc: snap.documents.last)))
    }
}
