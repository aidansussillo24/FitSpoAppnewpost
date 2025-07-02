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
            .onAppear(perform: attach)
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

    private var message: String {
        switch note.kind {
        case .mention: return "mentioned you"
        case .comment: return "commented on your post"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: note.fromAvatarURL ?? "")) { phase in
                if let img = phase.image { img.resizable() } else { Color.gray.opacity(0.3) }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("\(note.fromUsername) \(message)")
                    .font(.subheadline)
                Text(note.text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView()
    }
}
