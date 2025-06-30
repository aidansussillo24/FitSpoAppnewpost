import SwiftUI
import FirebaseFirestore

struct HotPostsView: View {
    private let spacing: CGFloat = 2
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: spacing)]
    }

    @State private var posts: [Post] = []
    @State private var lastDoc: DocumentSnapshot?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(posts) { post in
                    NavigationLink { PostDetailView(post: post) } label: {
                        ImageTile(url: post.imageURL)
                    }
                    .onAppear {
                        if post.id == posts.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }
            }
            .padding(.horizontal, spacing / 2)
            .padding(.bottom, spacing)
        }
        .navigationTitle("Hot Posts")
        .refreshable { await reload(clear: true) }
        .task { await reload(clear: true) }
    }

    private func reload(clear: Bool) async {
        if isLoading { return }
        if clear { posts.removeAll(); lastDoc = nil }
        isLoading = true
        defer { isLoading = false }
        do {
            let bundle = try await NetworkService.shared.fetchHotPostsPage(startAfter: lastDoc, limit: 100)
            lastDoc = bundle.lastDoc
            posts.append(contentsOf: bundle.posts)
        } catch {
            print("HotPosts fetch error:", error.localizedDescription)
        }
    }

    private func loadMore() async {
        await reload(clear: false)
    }
}

// reuse from ExploreView
private struct ImageTile: View {
    let url: String
    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .empty:   Color.gray.opacity(0.12)
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color.gray.opacity(0.12)
                @unknown default: Color.gray.opacity(0.12)
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .cornerRadius(8)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
