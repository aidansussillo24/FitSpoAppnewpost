//
//  HomeView.swift
//  FitSpo
//
//  Masonry feed with pull‑to‑refresh + endless scroll.
//  Updated 2025‑06‑26:
//  • Switched column stacks to LazyVStack so off‑screen cards are not built.
//  • Added lastPrefetchIndex guard to avoid duplicate triggers.
//

import SwiftUI
import FirebaseFirestore

struct HomeView: View {

    // ───────── state ─────────────────────────────────────────
    @State private var posts:   [Post]            = []
    @State private var cursor:  DocumentSnapshot? = nil      // Firestore paging cursor

    @State private var reachedEnd    = false
    @State private var isLoadingPage = false
    @State private var isRefreshing  = false

    private let PAGE_SIZE      = 12           // first load ≈10‑15 posts
    private let PREFETCH_AHEAD = 4            // when ≤4 remain → fetch
    @State private var lastPrefetchIndex = -1 // prevents duplicate calls

    // Split into two columns
    private var leftColumn:  [Post] { posts.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) }
    private var rightColumn: [Post] { posts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element) }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    // ── Masonry grid
                    HStack(alignment: .top, spacing: 8) {
                        column(for: leftColumn)
                        column(for: rightColumn)
                    }
                    .padding(.horizontal, 12)

                    if isLoadingPage {
                        ProgressView()
                            .padding(.vertical, 32)
                    }

                    if reachedEnd, !posts.isEmpty {
                        Text("No more posts")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 32)
                    }
                }
            }
            .refreshable { await refresh() }
            .onAppear(perform: initialLoad)
            .onReceive(NotificationCenter.default.publisher(for: .didUploadPost)) { _ in
                Task { await refresh() }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: header
    private var header: some View {
        ZStack {
            Text("FitSpo").font(.largeTitle).fontWeight(.black)
            HStack {
                Spacer()
                NavigationLink(destination: MessagesView()) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: masonry column
    @ViewBuilder
    private func column(for list: [Post]) -> some View {
        LazyVStack(spacing: 8) {                 // ← now lazy!
            ForEach(list) { post in
                PostCardView(post: post) { toggleLike(post) }
                    .onAppear { maybePrefetch(after: post) }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: paging trigger
    // ─────────────────────────────────────────────────────────
    private func maybePrefetch(after post: Post) {
        guard let idx = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let remaining = posts.count - idx - 1
        guard remaining <= PREFETCH_AHEAD else { return }

        // Only trigger once per index to avoid race conditions
        guard idx != lastPrefetchIndex else { return }
        lastPrefetchIndex = idx
        loadNextPage()
    }

    // MARK: initial fetch
    private func initialLoad() {
        guard posts.isEmpty, !isLoadingPage else { return }
        isLoadingPage = true
        NetworkService.shared.fetchPostsPage(pageSize: PAGE_SIZE, after: nil) { res in
            DispatchQueue.main.async {
                isLoadingPage = false
                switch res {
                case .success(let tuple):
                    posts      = tuple.0
                    cursor     = tuple.1
                    reachedEnd = tuple.1 == nil
                case .failure(let err):
                    print("Initial load error:", err)
                }
            }
        }
    }

    // MARK: next page
    private func loadNextPage() {
        guard !isLoadingPage, !reachedEnd else { return }
        isLoadingPage = true
        NetworkService.shared.fetchPostsPage(pageSize: PAGE_SIZE, after: cursor) { res in
            DispatchQueue.main.async {
                isLoadingPage = false
                switch res {
                case .success(let tuple):
                    let newOnes = tuple.0.filter { p in !posts.contains(where: { $0.id == p.id }) }
                    withAnimation(.easeIn) {
                        posts.append(contentsOf: newOnes)
                    }
                    cursor     = tuple.1
                    reachedEnd = tuple.1 == nil
                case .failure(let err):
                    print("Next page error:", err)
                }
            }
        }
    }

    // MARK: pull‑to‑refresh
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        reachedEnd = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            NetworkService.shared.fetchPostsPage(pageSize: PAGE_SIZE, after: nil) { res in
                DispatchQueue.main.async {
                    switch res {
                    case .success(let tuple):
                        withAnimation(.easeIn) { posts = tuple.0 }
                        cursor     = tuple.1
                        reachedEnd = tuple.1 == nil
                        lastPrefetchIndex = -1          // reset for fresh paging
                    case .failure(let err):
                        print("Refresh error:", err)
                    }
                    cont.resume()
                }
            }
        }
    }

    // MARK: like handling
    private func toggleLike(_ post: Post) {
        NetworkService.shared.toggleLike(post: post) { result in
            DispatchQueue.main.async {
                if case .success(let updated) = result,
                   let idx = posts.firstIndex(where: { $0.id == updated.id }) {
                    posts[idx] = updated
                }
            }
        }
    }
}

#if DEBUG
struct HomeView_Previews: PreviewProvider {
    static var previews: some View { HomeView() }
}
#endif
