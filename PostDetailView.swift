//
//  PostDetailView.swift
//  FitSpo
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import UIKit

// ─────────────────────────────────────────────────────────────
struct PostDetailView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // ── Author info ─────────────────────────
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ── Location ───────────────────────────
    @State private var locationName    = ""

    // ── Like state ─────────────────────────
    @State private var isLiked    : Bool
    @State private var likesCount : Int
    @State private var showHeartBurst = false

    // ── Comment state ──────────────────────
    @State private var commentCount : Int = 0
    @State private var showComments = false

    // ── Misc. ──────────────────────────────
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false
    @State private var showShareSheet    = false
    @State private var shareChat: Chat?
    @State private var navigateToChat = false

    // live doc listener
    @State private var postListener: ListenerRegistration?

    // image aspect-ratio (h ÷ w) – updated once the file is downloaded
    @State private var imgRatio: CGFloat? = nil   // ← key for variable height

    init(post: Post) {
        self.post = post
        _isLiked    = State(initialValue: post.isLiked)
        _likesCount = State(initialValue: post.likes)
    }

    // MARK: — Body ----------------------------------------------------------
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    postImage
                    actionRow
                    captionRow
                    timestampRow
                    Spacer(minLength: 32)
                }
                .padding(.top)
            }

            // ── Comments overlay ──
            if showComments {
                CommentsOverlay(
                    post: post,
                    isPresented: $showComments,
                    onCommentCountChange: { commentCount = $0 }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)

        // delete button for owner
        .toolbar {
            if post.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
            }
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareToUserView { selectedUserId in
                showShareSheet = false
                sharePost(to: selectedUserId)
            }
        }
        .background(
            Group {
                if let chat = shareChat {
                    NavigationLink(
                        destination: ChatDetailView(chat: chat),
                        isActive: $navigateToChat
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .onAppear {
            attachPostListener()
            fetchAuthor()
            fetchLocationName()
            fetchCommentCount()
        }
        .onDisappear { postListener?.remove() }
    }

    // MARK: — Subviews ------------------------------------------------------

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    Text(isLoadingAuthor ? "Loading…" : authorName).font(.headline)
                }
                if !locationName.isEmpty {
                    Text(locationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    // ─────────────────────────────────────────────────────────────
    // MARK: Zoomable image keeping original aspect-ratio
    // ─────────────────────────────────────────────────────────────
    private var postImage: some View {
        GeometryReader { geo in
            if let url = URL(string: post.imageURL) {
                ZoomableAsyncImage(url: url, aspectRatio: $imgRatio)
                    .frame(
                        width: geo.size.width,
                        height: (imgRatio ?? 1) * geo.size.width
                    )
                    .clipped()
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { handleDoubleTapLike() }
                    )
            } else {
                // fallback
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        // give the GeometryReader itself a matching height so
        // the VStack/ScrollView knows the correct size
        .frame(height: UIScreen.main.bounds.width * (imgRatio ?? 1))
        .overlay(
            HeartBurstView(trigger: $showHeartBurst)      // ← NEW
        )
    }

    private var actionRow: some View {
        HStack(spacing: 24) {
            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isLiked ? .red : .primary)
            }
            Text("\(likesCount)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Button { showComments = true } label: {
                Image(systemName: "bubble.right").font(.title2)
            }
            Text("\(commentCount)")
                .font(.subheadline)
                .fontWeight(.semibold)

            Button { showShareSheet = true } label: {
                Image(systemName: "paperplane").font(.title2)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private var captionRow: some View {
        HStack(alignment: .top, spacing: 4) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                Text(isLoadingAuthor ? "Loading…" : authorName)
                    .fontWeight(.semibold)
            }
            Text(post.caption)
        }
        .padding(.horizontal)
    }

    private var timestampRow: some View {
        Text(post.timestamp, style: .time)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal)
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let url = URL(string: authorAvatarURL), !authorAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Image(systemName: "person.crop.circle.fill").resizable()
                    @unknown default: EmptyView()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // MARK: — Firestore listener & helpers ---------------------------------

    private func attachPostListener() {
        guard postListener == nil else { return }
        let doc = Firestore.firestore().collection("posts").document(post.id)
        postListener = doc.addSnapshotListener { snap, _ in
            guard let d = snap?.data() else { return }
            likesCount   = d["likes"] as? Int ?? likesCount
            commentCount = d["commentsCount"] as? Int ?? commentCount
            if let likedBy = d["likedBy"] as? [String],
               let uid = Auth.auth().currentUser?.uid {
                isLiked = likedBy.contains(uid)
            }
        }
    }

    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        showHeartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showHeartBurst = false }
        if !isLiked { toggleLike() }
    }

    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { result in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = result { dismiss() }
            }
        }
    }

    private func fetchAuthor() {
        Firestore.firestore()
            .collection("users").document(post.userId)
            .getDocument { snap, _ in
                isLoadingAuthor = false
                let d = snap?.data() ?? [:]
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }

    private func fetchLocationName() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        let loc = CLLocation(latitude: lat, longitude: lon)
        CLGeocoder().reverseGeocodeLocation(loc) { places, _ in
            guard let p = places?.first else { return }
            var parts = [String]()
            if let city   = p.locality             { parts.append(city) }
            if let region = p.administrativeArea   { parts.append(region) }
            if parts.isEmpty, let country = p.country { parts.append(country) }
            locationName = parts.joined(separator: ", ")
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { res in
            if case .success(let list) = res { commentCount = list.count }
        }
    }

    private func sharePost(to userId: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, userId].sorted()
        NetworkService.shared.createChat(participants: pair) { res in
            switch res {
            case .success(let chat):
                NetworkService.shared.sendPost(chatId: chat.id, postId: post.id) { _ in }
                DispatchQueue.main.async { shareChat = chat; navigateToChat = true }
            case .failure(let err):
                print("Chat creation error:", err)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: ZoomableAsyncImage  (UIKit wrapper)
// ─────────────────────────────────────────────────────────────
fileprivate struct ZoomableAsyncImage: UIViewRepresentable {
    let url: URL
    @Binding var aspectRatio: CGFloat?     // updated once we know it

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.maximumZoomScale = 4
        scroll.minimumZoomScale = 1
        scroll.bouncesZoom      = true
        scroll.showsVerticalScrollIndicator   = false
        scroll.showsHorizontalScrollIndicator = false

        // host SwiftUI AsyncImage
        let hosted = UIHostingController(
            rootView: AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ZStack { Color.gray.opacity(0.2); ProgressView() }
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    ZStack {
                        Color.gray.opacity(0.2)
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.white.opacity(0.7))
                    }
                @unknown default: EmptyView()
                }
            }
        )
        hosted.view.backgroundColor = .clear
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(hosted.view)

        // width = scroll width  |  height = width * ratio  (ratio defaults to 1)
        context.coordinator.heightConstraint =
            hosted.view.heightAnchor.constraint(equalTo: hosted.view.widthAnchor, multiplier: 1)

        NSLayoutConstraint.activate([
            hosted.view.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            hosted.view.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            hosted.view.topAnchor.constraint(equalTo: scroll.topAnchor),
            hosted.view.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            hosted.view.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            context.coordinator.heightConstraint!
        ])

        // load image once in the background to get its size
        context.coordinator.computeAspectRatioIfNeeded()

        context.coordinator.zoomView = hosted.view
        return scroll
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // nothing else to update
    }

    // ── Coordinator (delegate + helper) ──
    class Coordinator: NSObject, UIScrollViewDelegate {
        private let parent: ZoomableAsyncImage
        weak   var zoomView: UIView?
        var    heightConstraint: NSLayoutConstraint?
        var    alreadyFetched = false

        init(_ parent: ZoomableAsyncImage) { self.parent = parent }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let v = zoomView else { return }
            let boundsSize = scrollView.bounds.size
            var frame = v.frame

            // centre when smaller than viewport
            frame.origin.x = frame.size.width  < boundsSize.width  ? (boundsSize.width  - frame.size.width ) / 2 : 0
            frame.origin.y = frame.size.height < boundsSize.height ? (boundsSize.height - frame.size.height) / 2 : 0
            v.frame = frame
        }

        /// Downloads just the header of the image file → creates UIImage → updates ratio
        func computeAspectRatioIfNeeded() {
            guard !alreadyFetched else { return }
            alreadyFetched = true

            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: self.parent.url, options: .mappedIfSafe),
                      let ui = UIImage(data: data) else { return }
                let ratio = ui.size.height / ui.size.width
                DispatchQueue.main.async {
                    // update binding to SwiftUI
                    self.parent.aspectRatio = ratio
                    // update UIKit constraint
                    self.heightConstraint?.isActive = false
                    if let view = self.zoomView {
                        self.heightConstraint =
                            view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: ratio)
                        self.heightConstraint?.isActive = true
                        view.setNeedsLayout()
                        view.layoutIfNeeded()
                    }
                }
            }
        }
    }
}
