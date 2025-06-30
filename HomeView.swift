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

    private let PAGE_SIZE      = 12           // full page size
    private let FIRST_BATCH    = 4            // show first two rows fast
    private let PREFETCH_AHEAD = 4            // when ≤4 remain → fetch
    @State private var lastPrefetchIndex = -1 // prevents duplicate calls

    // Hot posts row
    @State private var hotPosts: [Post] = []
    @State private var hotRowOffset: CGFloat = -20

    // Split into two columns
    private var leftColumn:  [Post] { posts.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) }
    private var rightColumn: [Post] { posts.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element) }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    hotCircleRow

                    // ── Masonry grid
                    if posts.isEmpty && isLoadingPage {
                        skeletonGrid
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            column(for: leftColumn)
                            column(for: rightColumn)
                        }
                        .padding(.horizontal, 12)
                    }

                    if isLoadingPage && !posts.isEmpty {
                        ProgressView()
                            .padding(.vertical, 32)
                    }

                    if reachedEnd, !posts.isEmpty {
                        Text("No more posts")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 32)
                            .padding(.top, 16)
                    }
                }
            }
            .refreshable { await refresh() }
            .onAppear(perform: initialLoad)
            .task { await loadHotPosts() }
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
        .padding(.top, 24)
        .padding(.bottom, 8)
    }

    // MARK: hot row
    private var hotCircleRow: some View {
        Group {
            if !hotPosts.isEmpty {
                NavigationLink {
                    HotPostsView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                            Text("Hot Today")
                                .font(.headline)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(hotPosts) { post in
                                    RemoteImage(url: post.imageURL)
                                        .frame(width: 64, height: 64)
                                        .clipShape(Circle())
                                }
                            }
                            .padding(.horizontal, 6)
                            .offset(x: hotRowOffset)
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 8)
                                        .repeatForever(autoreverses: true)
                                ) {
                                    hotRowOffset = 20
                                }
                            }
                        }
                        .frame(height: 72)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }

    // MARK: skeleton grid
    private var skeletonGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            LazyVStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    PostCardSkeleton()
                }
            }
            LazyVStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    PostCardSkeleton()
                }
            }
        }
        .padding(.horizontal, 12)
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
        NetworkService.shared.fetchPostsPage(pageSize: FIRST_BATCH, after: nil) { res in
            DispatchQueue.main.async {
                switch res {
                case .success(let tuple):
                    posts      = tuple.0
                    cursor     = tuple.1
                    reachedEnd = tuple.1 == nil
                    isLoadingPage = false
                    // Fetch rest of first page in background
                    if !reachedEnd {
                        loadAdditionalForFirstPage()
                    }
                case .failure(let err):
                    isLoadingPage = false
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

    // Fetch remaining posts for first page after initial batch
    private func loadAdditionalForFirstPage() {
        NetworkService.shared.fetchPostsPage(pageSize: PAGE_SIZE - FIRST_BATCH,
                                            after: cursor) { res in
            DispatchQueue.main.async {
                switch res {
                case .success(let tuple):
                    let newOnes = tuple.0.filter { p in !posts.contains(where: { $0.id == p.id }) }
                    withAnimation(.easeIn) {
                        posts.append(contentsOf: newOnes)
                    }
                    cursor     = tuple.1
                    reachedEnd = tuple.1 == nil
                case .failure(let err):
                    print("Initial page extend error:", err)
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

    // MARK: load hot posts
    private func loadHotPosts() async {
        do {
            let bundle = try await NetworkService.shared.fetchHotPostsPage(startAfter: nil, limit: 100)
            await MainActor.run { hotPosts = Array(bundle.posts.prefix(10)) }
        } catch {
            print("Hot posts error:", error.localizedDescription)
        }
    }
}

#if DEBUG
struct HomeView_Previews: PreviewProvider {
    static var previews: some View { HomeView() }
}
#endif
