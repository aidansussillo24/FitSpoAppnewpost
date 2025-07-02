import SwiftUI

struct ActivityView: View {
    var body: some View {
        NavigationView {
            Text("No activity yet")
                .foregroundColor(.secondary)
                .navigationTitle("Activity")
        }
    }
}

struct ActivityView_Previews: PreviewProvider {
    static var previews: some View {
        ActivityView()
    }
}
