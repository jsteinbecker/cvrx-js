//
//  FacilityOverviewScene.swift
//  cvrx
//
//  Created by Josh Steinbecker on 6/22/26.
//

import SwiftUI
import SwiftData


extension OccupancyStatus {
    var color: Color {
        switch self {
        case .occupied:    .blue
        case .vacant:      .primary
        case .reserved:    .orange
        case .unavailable: .secondary
        }
    }

    var fillColor: Color {
        switch self {
        case .occupied:    Color.blue.opacity(0.15)
        case .vacant:      Color.secondary.opacity(0.08)
        case .reserved:    Color.orange.opacity(0.15)
        case .unavailable: Color.secondary.opacity(0.2)
        }
    }

    var strokeColor: Color {
        switch self {
        case .occupied:    .blue.opacity(0.5)
        case .vacant:      .secondary
        case .reserved:    .orange.opacity(0.5)
        case .unavailable: .clear
        }
    }

    var textColor: Color {
        switch self {
        case .occupied:    .blue
        case .vacant:      .secondary
        case .reserved:    .orange
        case .unavailable: .red
        }
    }
}


// MARK: - Scene

struct FacilityOverviewScene: View {
    @Environment(\.modelContext) private var context
    @Query private var facilities: [Facility]

    @State private var selectedFacility: Facility?
    @State private var selectedFloorType: FloorType?

    var body: some View {
        NavigationSplitView {
            List(facilities, selection: $selectedFacility) { facility in
                Text(facility.name)
                    .tag(facility)
            }
            .navigationTitle("Facilities")
        } detail: {
            if let facility = selectedFacility {
                FacilityMapView(facility: facility, selectedFloorType: $selectedFloorType)
            } else {
                ContentUnavailableView("Select a facility", systemImage: "building.2")
            }
        }
    }
}


// MARK: - Facility map

struct FacilityMapView: View {
    let facility: Facility
    @Binding var selectedFloorType: FloorType?

    @Query private var allFloors: [FloorUnit]

    private var floors: [FloorUnit] {
        let facilityFloors = allFloors.filter { $0.facility.id == facility.id }
        guard let filter = selectedFloorType else { return facilityFloors }
        return facilityFloors.filter { $0.floorType == filter }
    }

    private var census: CensusSummary {
        CensusSummary(floors: floors)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CensusBanner(summary: census)
                FloorTypeFilterBar(selected: $selectedFloorType)
                ForEach(floors) { floor in
                    FloorMapCard(floor: floor, namingRule: facility.bedNamingRule)
                }
            }
            .padding()
        }
        .navigationTitle(facility.name)
        .navigationSubtitle(facility.abv)
    }
}


// MARK: - Census summary

struct CensusSummary {
    let total: Int
    let occupied: Int
    let vacant: Int
    let reserved: Int

    var occupancyPct: Double {
        guard total > 0 else { return 0 }
        return Double(occupied) / Double(total)
    }

    init(floors: [FloorUnit]) {
        var t = 0, o = 0, v = 0, r = 0
        for floor in floors {
            for room in floor.rooms {
                for bed in room.beds {
                    t += 1
                    switch bed.occupancyStatus {
                    case .occupied:   o += 1
                    case .vacant:     v += 1
                    case .reserved:   r += 1
                    case .unavailable: break
                    }
                }
            }
        }
        total = t; occupied = o; vacant = v; reserved = r
    }
}

struct CensusBanner: View {
    let summary: CensusSummary

    var body: some View {
        HStack(spacing: 12) {
            CensusStatCell(label: "Total", value: "\(summary.total)", color: .primary)
            Divider().frame(maxHeight: 44)
            CensusStatCell(
                label: "Occupied",
                value: "\(summary.occupied)",
                sub: "\(Int(summary.occupancyPct * 100))%",
                color: OccupancyStatus.occupied.color
            )
            Divider().frame(maxHeight: 44)
            CensusStatCell(label: "Vacant", value: "\(summary.vacant)", color: OccupancyStatus.vacant.color)
            Divider().frame(maxHeight: 44)
            CensusStatCell(label: "Reserved", value: "\(summary.reserved)", color: OccupancyStatus.reserved.color)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CensusStatCell: View {
    let label: String
    let value: String
    var sub: String? = nil
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
                .foregroundStyle(color)
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


// MARK: - Floor type filter

struct FloorTypeFilterBar: View {
    @Binding var selected: FloorType?

    private let types: [(FloorType, String)] = [
        (.ms, "Med/Surg"), (.pc, "Prog. Care"),
        (.ic, "ICU"), (.ob, "OB"), (.op, "Outpatient")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isSelected: selected == nil) { selected = nil }
                ForEach(types, id: \.0) { type, label in
                    FilterChip(label: label, isSelected: selected == type) { selected = type }
                }
            }
        }
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Floor map card

struct FloorMapCard: View {
    let floor: FloorUnit
    let namingRule: BedNamingRule
    @State private var isExpanded = true

    private var floorCensus: (occupied: Int, total: Int) {
        var o = 0, t = 0
        for room in floor.rooms {
            for bed in room.beds { t += 1; if bed.occupancyStatus == .occupied { o += 1 } }
        }
        return (o, t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    FloorTypeBadge(type: floor.floorType)
                    Text(floor.name)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    let c = floorCensus
                    Text("\(c.occupied)/\(c.total) beds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                // Rooms grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(floor.rooms) { room in
                        RoomCell(room: room, namingRule: namingRule)
                    }
                }
                .padding(12)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }
}


// MARK: - Room cell

struct RoomCell: View {
    let room: Room
    let namingRule: BedNamingRule

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Rm \(room.name)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(room.beds.enumerated()), id: \.offset) { index, bed in
                    BedCell(bed: bed, label: namingRule.label(for: index))
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}


// MARK: - Bed cell

struct BedCell: View {
    let bed: Bed
    let label: String
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(bed.occupancyStatus.fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(bed.occupancyStatus.strokeColor, lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(bed.occupancyStatus.textColor)
        }
        .frame(width: 26, height: 26)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .help(bedTooltip)
    }

    private var bedTooltip: String {
        let base = "Bed \(label) · \(bed.occupancyStatus.displayName)"
        if let patient = bed.patient {
            return "\(base) — \(patient.name)"
        }
        return base
    }
}


// MARK: - Floor type badge

struct FloorTypeBadge: View {
    let type: FloorType

    var label: String {
        switch type {
        case .ms: "Med/Surg"
        case .pc: "Prog. Care"
        case .ic: "ICU"
        case .ob: "OB"
        case .op: "Outpatient"
        }
    }

    var color: Color {
        switch type {
        case .ms: .blue
        case .pc: .purple
        case .ic: .red
        case .ob: .pink
        case .op: .green
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Preview

#Preview {
    FacilityOverviewScene()
        .modelContainer(for: [Facility.self, FloorUnit.self, Room.self, Bed.self])
}
