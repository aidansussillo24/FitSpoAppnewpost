//
//  TagOverlayView.swift
//  FitSpo
//
//  Full-screen editor for tagging users on a photo.
//  • Single tap on the image → opens username search sheet
//  • Select a user to place a draggable label
//

import SwiftUI
import FirebaseFirestore

struct TagOverlayView: View {
    
    let baseImage: UIImage
    @State private var imgSize: CGSize = .zero
    
    // Current tags
    @State private var tags: [UserTag]
    
    // Search state
    @State private var query   = ""
    @State private var results: [(id:String,name:String)] = []
    
    // Callback
    var onDone: ([UserTag]) -> Void
    
    // Point waiting for a username
    @State private var pendingPoint: (CGFloat,CGFloat)? = nil
    
    // ── init ─────────────────────────────────────────────────────────
    init(baseImage: UIImage,
         existing: [UserTag],
         onDone: @escaping ([UserTag]) -> Void) {
        self.baseImage = baseImage
        _tags  = State(initialValue: existing)
        self.onDone = onDone
    }
    
    // ── UI ───────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ZStack {
                GeometryReader { geo in
                    Image(uiImage: baseImage)
                        .resizable()
                        .scaledToFit()
                        .onAppear { imgSize = geo.size }
                        // zero-distance drag gives us a CGPoint
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    startSearch(at: value.location, in: geo.size)
                                }
                        )
                }
                .ignoresSafeArea()
                
                ForEach(tags.indices, id:\.self) { idx in
                    TagLabelView(tag: $tags[idx], parentSize: imgSize)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onDone(tags) }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDone(tags) }
                        .fontWeight(.bold)
                }
            }
            // Username search sheet
            .sheet(isPresented: Binding(
                get: { !query.isEmpty },
                set: { if !$0 { query = "" }})
            ) {
                SearchUserSheet(
                    query: $query,
                    results: $results,
                    onSelect: { uid, name in
                        addTag(uid: uid, name: name)
                        query = ""
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    // ── Helpers ──────────────────────────────────────────────────────
    private func startSearch(at location: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        pendingPoint = (location.x / size.width,
                        location.y / size.height)
        query = "@"    // open sheet
    }
    
    private func addTag(uid: String, name: String) {
        guard let pt = pendingPoint else { return }
        tags.append(UserTag(id: uid,
                            xNorm: pt.0,
                            yNorm: pt.1,
                            displayName: name))
        pendingPoint = nil
    }
}

// ─────────────────────────────────────────────────────────────────────
// MARK: Draggable label
// ─────────────────────────────────────────────────────────────────────
private struct TagLabelView: View {
    @Binding var tag: UserTag
    var parentSize: CGSize
    
    @State private var offset: CGSize = .zero
    
    var body: some View {
        Text(tag.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .offset(offset)
            .position(
                x: tag.xNorm * parentSize.width,
                y: tag.yNorm * parentSize.height
            )
            .gesture(
                DragGesture()
                    .onChanged { g in offset = g.translation }
                    .onEnded   { _ in
                        let newX = (tag.xNorm * parentSize.width  + offset.width)
                                   / parentSize.width
                        let newY = (tag.yNorm * parentSize.height + offset.height)
                                   / parentSize.height
                        tag.xNorm = min(max(newX, 0), 1)
                        tag.yNorm = min(max(newY, 0), 1)
                        offset = .zero
                    }
            )
    }
}

// ─────────────────────────────────────────────────────────────────────
// MARK: Username search sheet
// ─────────────────────────────────────────────────────────────────────
private struct SearchUserSheet: View {
    @Binding var query: String
    @Binding var results: [(id:String,name:String)]
    var onSelect: (String,String) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(results, id:\.id) { r in
                    Button {
                        onSelect(r.id, r.name)
                    } label: {
                        Text(r.name)
                    }
                }
            }
            .navigationTitle("Tag someone")
            .searchable(text: $query, prompt: "username")
            .onChange(of: query) { _ in fetch() }
        }
    }
    
    private func fetch() {
        guard query.count >= 2 else { results = []; return }
        let q = query.lowercased()
        Firestore.firestore().collection("users")
            .whereField("username_lc", isGreaterThanOrEqualTo: q)
            .whereField("username_lc", isLessThan: q + "\u{f8ff}")
            .limit(to: 10)
            .getDocuments { snap, _ in
                results = snap?.documents.compactMap { d in
                    let id   = d.documentID
                    let name = d["displayName"] as? String ?? "user"
                    return (id,name)
                } ?? []
            }
    }
}
