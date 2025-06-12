//
//  PostCaptionView.swift
//  FitSpo
//

import SwiftUI
import CoreLocation

struct PostCaptionView: View {
    
    let image: UIImage
    
    // ── UI state ───────────────────────────────────────────
    @State private var caption   = ""
    @State private var isPosting = false
    @State private var errorMsg: String?
    
    // ── Tagging state ──────────────────────────────────────
    @State private var tags: [UserTag] = []
    @State private var showTagOverlay  = false
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)
            
            // Caption + Tag pill -----------------------------------------
            HStack {
                TextField("Enter a caption…", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                
                Button {
                    showTagOverlay = true
                } label: {
                    Label("Tag", systemImage: "tag")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6), in: Capsule())
                }
            }
            
            // Tag count feedback
            if !tags.isEmpty {
                Text("\(tags.count) people tagged")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let err = errorMsg {
                Text(err).foregroundColor(.red)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("New Post")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { dismissToRoot() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Post") { upload() }
                    .disabled(isPosting)
            }
        }
        // Tagging overlay sheet -----------------------------------------
        .fullScreenCover(isPresented: $showTagOverlay) {
            TagOverlayView(
                baseImage: image,
                existing: tags,
                onDone: { tags = $0; showTagOverlay = false }
            )
        }
    }
    
    // MARK: – Upload ------------------------------------------------------
    private func upload() {
        isPosting = true
        errorMsg  = nil
        
        let loc = LocationManager.shared.location
        let lat = loc?.coordinate.latitude
        let lon = loc?.coordinate.longitude
        
        NetworkService.shared.uploadPost(
            image: image,
            caption: caption,
            latitude: lat,
            longitude: lon,
            tags: tags                                  // ← NEW
        ) { result in
            isPosting = false
            switch result {
            case .success: dismissToRoot()
            case .failure(let err): errorMsg = err.localizedDescription
            }
        }
    }
    
    private func dismissToRoot() {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dismiss() }
    }
}
