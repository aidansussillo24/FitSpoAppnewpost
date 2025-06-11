//  Replace file: PostCaptionView.swift
//  FitSpo

import SwiftUI
import CoreLocation

struct PostCaptionView: View {

    let image: UIImage

    @State private var caption   = ""
    @State private var isPosting = false
    @State private var errorMsg: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)

            TextField("Enter a caption…", text: $caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

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
    }

    private func upload() {
        isPosting = true
        errorMsg  = nil

        // Latest location from singleton
        let loc = LocationManager.shared.location
        let lat = loc?.coordinate.latitude
        let lon = loc?.coordinate.longitude

        NetworkService.shared.uploadPost(
            image: image,
            caption: caption,
            latitude: lat,
            longitude: lon
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
