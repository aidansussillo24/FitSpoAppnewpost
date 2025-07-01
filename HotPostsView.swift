import SwiftUI
import FirebaseFirestore

/// Displays the daily top posts in a simple vertical feed.
/// Swiping through shows each post with the regular detail layout.
struct HotPostsView: View {

    @State private var posts: [Post] = []
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(posts) { post in
                    PostDetailView(post: post)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                }
            }
            .padding(.vertical)
            .padding(.horizontal, 16)
        }
        .navigationTitle("Hot Today")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let bundle = try await NetworkService.shared
                .fetchHotPostsPage(startAfter: nil, limit: 10)
            posts = bundle.posts
        } catch {
            print("HotPosts fetch error:", error.localizedDescription)
        }
    }
}
