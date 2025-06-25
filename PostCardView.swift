//
//  PostCardView.swift
//  FitSpo
//
//  Feed card now uses RemoteImage with automatic retry & caching.
//

import SwiftUI
import FirebaseFirestore

struct PostCardView: View {
    let post: Post
    let onLike: () -> Void

    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    var body: some View {
        VStack(spacing: 0) {

            // ── Tap image → PostDetail ─────────────────────────────
            NavigationLink(destination: PostDetailView(post: post)) {
                RemoteImage(url: post.imageURL, contentMode: .fit)
            }
            .buttonStyle(.plain)

            // ── Footer (avatar, name, like button) ─────────────────
            HStack(spacing: 8) {

                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    HStack(spacing: 8) {
                        avatarThumb
                        Text(isLoadingAuthor ? "Loading…" : authorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                        Text("\(post.likes)")
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.white)
        }
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05),
                radius: 4, x: 0, y: 2)
        .onAppear(perform: fetchAuthor)
    }

    // MARK: – avatar helper
    @ViewBuilder private var avatarThumb: some View {
        if let url = URL(string: authorAvatarURL),
           !authorAvatarURL.isEmpty {
            RemoteImage(url: url.absoluteString, contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundColor(.gray)
        }
    }

    // MARK: – Author fetch
    private func fetchAuthor() {
        Firestore.firestore()
            .collection("users")
            .document(post.userId)
            .getDocument { snap, err in
                isLoadingAuthor = false
                guard err == nil, let d = snap?.data() else {
                    authorName = "Unknown"; return
                }
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }
}

#if DEBUG
struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        PostCardView(
            post: Post(
                id:        "1",
                userId:    "alice",
                imageURL:  "https://via.placeholder.com/400x600",
                caption:   "Preview card",
                timestamp: Date(),
                likes:     42,
                isLiked:   false,
                latitude:  nil,
                longitude: nil,
                temp:      nil,
                hashtags:  []
            )
        ) { }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
