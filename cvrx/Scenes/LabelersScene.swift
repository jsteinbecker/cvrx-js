import SwiftUI
import SwiftData

struct LabelersScene: View {
    @Environment(\.currentUser) var user
    @Environment(\.modelContext) var modelContext

    @Query(sort: \Labeler.name) private var labelers: [Labeler]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Labelers")
                .font(.title)
                .fontWeight(.bold)
            Text("\(labelers.count) records")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }.padding(16)
        
        List(labelers) { labeler in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(labeler.name)
                    Text(labeler.labelerCode)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength:5)
                Text(labeler.fullName)
            }
        }
        .overlay {
            if labelers.isEmpty {
                ContentUnavailableView(
                    "No Labelers",
                    systemImage: "building.2",
                    description: Text("No manufacturers imported yet.")
                )
            }
        }
        .navigationTitle("Labelers")
    }
}
