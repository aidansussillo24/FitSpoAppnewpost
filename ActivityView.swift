import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ActivityView: View {
    @State private var notes: [UserNotification] = []
    @State private var listener: ListenerRegistration?

    var body: some View {
        NavigationView {
            List {
                if notes.isEmpty {
                    Text("No activity yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(notes) { n in NotificationRow(note: n) }
                }
            }
            .navigationTitle("Activity")
            .onAppear(attach)
            .onDisappear { listener?.remove(); listener = nil }
        }
    }

    private func attach() {
        guard listener == nil, let uid = Auth.auth().currentUser?.uid else { return }
        listener = NetworkService.shared.observeNotifications(for: uid) { list in
            notes = list
        }
    }
}

private struct NotificationRow: View {
    let note: UserNotification

    @State private var post: Post? = nil
    @State private var isLoadingPost = false

    private var message: String {
        switch note.kind {
        case .mention: return "mentioned you"
        case .comment: return "commented on your post"
        case .like:    return "liked your post"
        case .tag:     return "tagged you in a post"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink(destination: ProfileView(userId: note.fromUserId)) {
                AsyncImage(url: URL(string: note.fromAvatarURL ?? "")) { phase in
                    if let img = phase.image { img.resizable() } else { Color.gray.opacity(0.3) }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(note.fromUsername) \(message)")
                    .font(.subheadline)
                if note.kind != .like {
                    Text(note.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)

            if let post = post {
                NavigationLink(destination: PostDetailView(post: post)) {
                    PostCell(post: post)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else if isLoadingPost {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .onAppear(perform: fetchPost)
            }
        }
    }

    private func fetchPost() {
        guard !isLoadingPost else { return }
        isLoadingPost = true
        NetworkService.shared.fetchPost(id: note.postId) { result in
            if case .success(let p) = result {
                DispatchQueue.main.async {
                    post = p
                }
            }
            isLoadingPost = false
        }
    }
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView()
    }
}
