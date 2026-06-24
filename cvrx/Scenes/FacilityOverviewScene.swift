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
        case .vacant:      .secondary.opacity(0.75)
        case .reserved:    .orange
        case .unavailable: .red
        }
    }
}


// MARK: - Scene

struct FacilityOverviewScene: View {
    @Query private var facilities: [Facility]
    @State private var selectedFacility: Facility?
    @State private var selectedFloorType: FloorType?

    var body: some View {
        NavigationStack {
            Group {
                if let facility = selectedFacility ?? facilities.first {
                    FacilityMapView(facility: facility, selectedFloorType: $selectedFloorType)
                } else {
                    ContentUnavailableView("No facilities", systemImage: "building.2")
                }
            }
            .navigationTitle("Facilities")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) { facilityPicker }
                #else
                ToolbarItem() { facilityPicker }
                #endif
            }
        }
    }

    @ViewBuilder
    private var facilityPicker: some View {
        if facilities.count > 1 {
            Menu {
                Picker("Facility", selection: facilityBinding) {
                    ForEach(facilities) { facility in
                        Text(facility.name).tag(Optional(facility))
                    }
                }
            } label: {
                Label("Switch Facility", systemImage: "building.2")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
        }
    }

    private var facilityBinding: Binding<Facility?> {
        Binding(
            get: { selectedFacility ?? facilities.first },
            set: { selectedFacility = $0 }
        )
    }
}


// MARK: - Facility map

struct FacilityMapView: View {
    let facility: Facility
    @Binding var selectedFloorType: FloorType?

    @Environment(\.modelContext) private var context

    @Query private var allFloors: [FloorUnit]

    // Census simulation state
    @State private var censusEvents: [MockData.CensusEvent] = []
    @State private var showEventLog = false
    @State private var isSimulating = false
    @State private var currentTick = 0
    @State private var simParams = MockData.CensusParams()

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
            VStack(alignment: .leading, spacing: 16) {
                CensusBanner(summary: census)
                if (isSimulating) {
                    SimInProgressIndicator()
                        .padding()
                } else { Spacer().padding() }
                FloorTypeFilterBar(selected: $selectedFloorType)
                ForEach(floors) { floor in
                    FloorMapCard(floor: floor, namingRule: facility.bedNamingRule)
                }
            }
            .padding()
        }
        .background(.background.secondary)
        .navigationTitle(facility.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                censusSimMenu
            }
        }
        .sheet(isPresented: $showEventLog) {
            CensusEventLogSheet(events: censusEvents)
        }
    }

    // MARK: - Census sim toolbar menu

    @ViewBuilder
    private var censusSimMenu: some View {
        Menu {
            Button {
                runFullSimulation()
            } label: {
                Label("Run Simulation", systemImage: "play.fill")
                }.disabled(isSimulating)
            Button {
                stepOneTick()
            } label: {
                Label("Step One Tick", systemImage: "forward.frame.fill")
                }.disabled(isSimulating)
            Divider()
            Button {
                showEventLog = true
            } label: {
                Label(
                    censusEvents.isEmpty ? "Event Log" : "Event Log (\(censusEvents.count))",
                    systemImage: "list.bullet.clipboard"
                )}.disabled(censusEvents.isEmpty)
            Divider()
            Button(role: .destructive) {
                resetSimulation()
            } label: {
                Label("Reset Census", systemImage: "arrow.counterclockwise")
                }.disabled(isSimulating)
        } label: {
            Label("Census Sim", systemImage: isSimulating ? "clock.arrow.2.circlepath" : "person.badge.clock")
                .symbolEffect(.pulse, isActive: isSimulating)
        }
    }

    // MARK: - Simulation actions

    /// Seeds occupancy (tick 0) then steps through all ticks at once.
    private func runFullSimulation() {
        isSimulating = true
        MockData.resetCensus(in: context)
        censusEvents = []
        currentTick = 0

        let events = MockData.simulateCensus(
            in: context,
            ticks: 12,
            params: simParams
        )
        censusEvents = events
        currentTick = events.map(\.tick).max() ?? 0
        isSimulating = false
    }

    /// Applies one additional tick to the current census state.
    /// Events from the step are appended to the log.
    private func stepOneTick() {
        isSimulating = true

        // If no simulation has been seeded yet, run tick 0 first.
        if censusEvents.isEmpty {
            let snapshot = MockData.simulateCensus(in: context, ticks: 0, params: simParams)
            censusEvents = snapshot
            currentTick = 0
            isSimulating = false
            return
        }

        let nextTick = currentTick + 1
        // simulateCensus always starts from the current store state, so running
        // with ticks: 1 and initialOccupancy: 0 (skip the snapshot) gives us
        // exactly one step. We achieve "skip snapshot" by passing a params copy
        // with initialOccupancy: 0 so tick-0 admits nothing, then strip tick-0
        // events from the result.
        var stepParams = simParams
        stepParams.initialOccupancy = 0
        let stepEvents = MockData.simulateCensus(in: context, ticks: 1, params: stepParams)
            .filter { $0.tick == 1 }
            .map { event -> MockData.CensusEvent in
                // Re-label the tick number to match our running counter.
                var e = event
                e.tick = nextTick
                return e
            }

        censusEvents.append(contentsOf: stepEvents)
        currentTick = nextTick
        isSimulating = false
    }

    private func resetSimulation() {
        MockData.resetCensus(in: context)
        censusEvents = []
        currentTick = 0
    }
}


struct SimInProgressIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(.yellow, lineWidth: 1)
            .backgroundStyle(.yellow.opacity(0.3))
            .overlay {
                HStack {
                    Image(systemName:"clock").foregroundStyle(.yellow.opacity(0.9))
                    Text("Simulation in Progress...").foregroundStyle(.yellow)
                }
            }
    }
}


struct CensusEventLogSheet: View {
    let events: [MockData.CensusEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var kindFilter: MockData.CensusEventKind? = nil

    private var filtered: [MockData.CensusEvent] {
        guard let f = kindFilter else { return events }
        return events.filter { $0.kind == f }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { event in
                CensusEventRow(event: event)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .navigationTitle("Census Events")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    kindFilterMenu
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Events",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Run a simulation to generate census events.")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var kindFilterMenu: some View {
        Menu {
            Button { kindFilter = nil } label: {
                Label("All", systemImage: kindFilter == nil ? "checkmark" : "line.3.horizontal.decrease")
            }
            Divider()
            ForEach([MockData.CensusEventKind.admit, .discharge, .transfer], id: \.self) { kind in
                Button { kindFilter = kind } label: {
                    Label(kind.displayName, systemImage: kindFilter == kind ? "checkmark" : kind.icon)
                }
            }
        } label: {
            Label(
                kindFilter.map { "Filter: \($0.displayName)" } ?? "Filter",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }
}

struct CensusEventRow: View {
    let event: MockData.CensusEvent

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Kind badge
            Image(systemName: event.kind.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(event.kind.color)
                .frame(width: 28, height: 28)
                .background(event.kind.color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(event.patientName)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("T\(event.tick)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(event.bedLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let from = event.fromBedLabel {
                    Text("from \(from)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(Self.timeFormatter.string(from: event.time))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - CensusEventKind display helpers

extension MockData.CensusEventKind {
    var displayName: String {
        switch self {
        case .admit:     "Admit"
        case .discharge: "Discharge"
        case .transfer:  "Transfer"
        }
    }

    var icon: String {
        switch self {
        case .admit:     "arrow.down.circle.fill"
        case .discharge: "arrow.up.circle.fill"
        case .transfer:  "arrow.left.arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .admit:     .green
        case .discharge: .red
        case .transfer:  .orange
        }
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
            Divider().frame(maxHeight: 40)
            CensusStatCell(
                label: "Occupied",
                value: "\(summary.occupied)",
                sub: "\(Int(summary.occupancyPct * 100))%",
                color: OccupancyStatus.occupied.color
            )
            Divider().frame(maxHeight: 40)
            CensusStatCell(label: "Vacant", value: "\(summary.vacant)", color: OccupancyStatus.vacant.color)
            Divider().frame(maxHeight: 40)
            CensusStatCell(label: "Reserved", value: "\(summary.reserved)", color: OccupancyStatus.reserved.color)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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
                .font(.title2.monospacedDigit().weight(.semibold))
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
            .padding(.horizontal, 2)
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
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .capsule
        )
    }
}


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
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    FloorTypeBadge(type: floor.floorType)
                    Text(floor.name)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    let c = floorCensus
                    Text("\(c.occupied)/\(c.total) beds")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 16)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(floor.rooms) { room in
                        RoomCell(room: room, namingRule: namingRule)
                    }
                }
                .padding(16)
            }
        }
        .background(.background, in: .rect(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }
}


struct RoomCell: View {
    let room: Room
    let namingRule: BedNamingRule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rm \(room.name)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(Array(room.beds.enumerated()), id: \.offset) { index, bed in
                    BedCell(bed: bed, label: namingRule.label(for: index))
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}


struct BedCell: View {
    let bed: Bed
    let label: String
    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(bed.occupancyStatus.fillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(bed.occupancyStatus.strokeColor, lineWidth: 0.75)
                )
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(bed.occupancyStatus.textColor)
        }
        .frame(width: 30, height: 30)
        .scaleEffect(isHovered ? 1.15 : 1.0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule)
            .foregroundStyle(color)
    }
}


#Preview {
    FacilityOverviewScene()
        .modelContainer(for: [Facility.self, FloorUnit.self, Room.self, Bed.self])
}
