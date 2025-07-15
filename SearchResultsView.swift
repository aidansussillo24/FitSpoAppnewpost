//
//  SearchResultsView.swift
//  FitSpo
//

import SwiftUI
import AlgoliaSearchClient

/// Stand-alone screen shown when user taps a username / hashtag result.
struct SearchResultsView: View {
    let query: String                 // either "@sofia" or "#beach"
    @State private var users: [UserLite] = []
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    // Masonry split columns like HomeView
    private var leftColumn: [Post] {
        posts.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
    }
    private var rightColumn: [Post] {
        posts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.first == "#" {
                    List {
                        // TODO: hashtag deep-dive (Phase 2.3)
                        Text("Hashtag search coming next…")
                            .foregroundColor(.secondary)
                    }
                } else if query.first == "@" {
                    List {
                        ForEach(users) { u in
                            NavigationLink(destination: ProfileView(userId: u.id)) {
                                AccountRow(user: u)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        if isLoading {
                            ProgressView().padding(.top, 40)
                        } else if posts.isEmpty {
                            Text("No results found")
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                        } else {
                            HStack(alignment: .top, spacing: 8) {
                                column(for: leftColumn)
                                column(for: rightColumn)
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .navigationTitle(query)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
            }}
            .task { await runSearch() }
        }
    }

    @MainActor
    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }

        if query.first == "@" {
            do {
                users = try await NetworkService.shared.searchUsers(prefix: query)
            } catch {
                print("User search error:", error.localizedDescription)
            }
        } else {
            await searchPosts()
        }
    }

    @MainActor
    private func searchPosts() async {
        do {
            let client  = SearchClient(appID: "6WFE31B7U3",
                                       apiKey: "2b7e223b3ca3c31fc6aaea704b80ca8c")
            let index   = client.index(withName: "posts")
            // `SearchResponse` from the Algolia client is not generic in the
            // version bundled with this project.  Attempt the search and then
            // decode the returned hits into our `Post` model manually.
            let response = try await index.search(
                query: Query(query).set(\.hitsPerPage, to: 40)
            )

            posts = response.hits.compactMap { hit in
                // Convert each hit's JSON payload into `Data` so that we can
                // use `JSONDecoder` to build a `Post` instance.  If decoding
                // fails we simply skip that entry.
                guard
                    let data = try? JSONSerialization.data(withJSONObject: hit, options: []),
                    var post = try? JSONDecoder().decode(Post.self, from: data)
                else { return nil }

                // Algolia stores the object identifier separately; keep it
                // around on the decoded post for later use.
                if let id = hit["objectID"] as? String {
                    post.objectID = id
                }
                return post
            }
        } catch {
            print("Algolia search error:", error.localizedDescription)
            posts = []
        }
    }

    @ViewBuilder
    private func column(for list: [Post]) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(list) { post in
                PostCardView(post: post, onLike: {})
            }
        }
    }
}
