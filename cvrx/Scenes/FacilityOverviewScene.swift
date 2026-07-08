//
//  FacilityOverviewScene.swift
//  cvrx
//
//  Reimagined as a card-based operational dashboard.
//

import SwiftUI
import SwiftData


// MARK: - Occupancy presentation

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
        case .unavailable: Color.secondary.opacity(0.20)
        }
    }

    var strokeColor: Color {
        switch self {
        case .occupied:    .blue.opacity(0.50)
        case .vacant:      .secondary
        case .reserved:    .orange.opacity(0.50)
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
        Group {
            if let facility = selectedFacility ?? facilities.first {
                FacilityMapView(
                    facility: facility,
                    selectedFloorType: $selectedFloorType
                )
            } else {
                ContentUnavailableView(
                    "No facilities",
                    systemImage: "building.2"
                )
            }
        }
        .navigationTitle("Facilities")
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                facilityPicker
            }
            #else
            ToolbarItem {
                facilityPicker
            }
            #endif
        }
    }

    @ViewBuilder
    private var facilityPicker: some View {
        if facilities.count > 1 {
            let menu = Menu {
                Picker("Facility", selection: facilityBinding) {
                    ForEach(facilities) { facility in
                        Text(facility.name)
                            .tag(Optional(facility))
                    }
                }
            } label: {
                Label("Switch Facility", systemImage: "building.2")
            }
            .menuStyle(.button)

            #if os(macOS)
            if #available(macOS 26.0, *) {
                menu.buttonStyle(.glass)
            } else {
                menu
            }
            #else
            menu
            #endif
        }
    }

    private var facilityBinding: Binding<Facility?> {
        Binding(
            get: { selectedFacility ?? facilities.first },
            set: { selectedFacility = $0 }
        )
    }
}


// MARK: - Facility dashboard

struct FacilityMapView: View {
    let facility: Facility
    @Binding var selectedFloorType: FloorType?

    @Environment(\.modelContext) private var context
    @Query private var allFloors: [FloorUnit]

    @State private var censusEvents: [MockData.CensusEvent] = []
    @State private var showEventLog = false
    @State private var isSimulating = false
    @State private var currentTick = 0
    @State private var simParams = MockData.CensusParams()

    private let columns = [
        GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 18, alignment: .top)
    ]

    private var facilityFloors: [FloorUnit] {
        allFloors
            .filter { $0.facility.id == facility.id }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var floors: [FloorUnit] {
        guard let selectedFloorType else { return facilityFloors }
        return facilityFloors.filter { $0.floorType == selectedFloorType }
    }

    private var census: CensusSummary {
        CensusSummary(floors: floors)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FacilityDashboardHeader(
                    facility: facility,
                    summary: census,
                    visibleFloorCount: floors.count,
                    totalFloorCount: facilityFloors.count,
                    currentTick: currentTick,
                    isSimulating: isSimulating
                )

                FloorTypeFilterBar(selected: $selectedFloorType)

                if floors.isEmpty {
                    ContentUnavailableView(
                        "No matching floors",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Choose another floor category to see available units.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(floors) { floor in
                            FloorDashboardCard(
                                floor: floor,
                                namingRule: facility.bedNamingRule
                            )
                        }
                    }
                }
            }
            .padding(18)
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

    @ViewBuilder
    private var censusSimMenu: some View {
        Menu {
            Button {
                runFullSimulation()
            } label: {
                Label("Run Simulation", systemImage: "play.fill")
            }
            .disabled(isSimulating)

            Button {
                stepOneTick()
            } label: {
                Label("Step One Tick", systemImage: "forward.frame.fill")
            }
            .disabled(isSimulating)

            Divider()

            Button {
                showEventLog = true
            } label: {
                Label(
                    censusEvents.isEmpty
                        ? "Event Log"
                        : "Event Log (\(censusEvents.count))",
                    systemImage: "list.bullet.clipboard"
                )
            }
            .disabled(censusEvents.isEmpty)

            Divider()

            Button(role: .destructive) {
                resetSimulation()
            } label: {
                Label("Reset Census", systemImage: "arrow.counterclockwise")
            }
            .disabled(isSimulating)
        } label: {
            Label(
                "Census Sim",
                systemImage: isSimulating
                    ? "clock.arrow.2.circlepath"
                    : "person.badge.clock"
            )
            .symbolEffect(.pulse, isActive: isSimulating)
        }
    }

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

    private func stepOneTick() {
        isSimulating = true

        if censusEvents.isEmpty {
            censusEvents = MockData.simulateCensus(
                in: context,
                ticks: 0,
                params: simParams
            )
            currentTick = 0
            isSimulating = false
            return
        }

        let nextTick = currentTick + 1
        var stepParams = simParams
        stepParams.initialOccupancy = 0

        let stepEvents = MockData.simulateCensus(
            in: context,
            ticks: 1,
            params: stepParams
        )
        .filter { $0.tick == 1 }
        .map { event -> MockData.CensusEvent in
            var updatedEvent = event
            updatedEvent.tick = nextTick
            return updatedEvent
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


// MARK: - Dashboard header

struct FacilityDashboardHeader: View {
    let facility: Facility
    let summary: CensusSummary
    let visibleFloorCount: Int
    let totalFloorCount: Int
    let currentTick: Int
    let isSimulating: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Facility census")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(facility.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if isSimulating {
                    Label("Simulation running", systemImage: "clock.arrow.2.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.orange.opacity(0.10), in: Capsule())
                } else if currentTick > 0 {
                    Text("Tick \(currentTick)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.secondary.opacity(0.08), in: Capsule())
                }
            }
            .padding(18)

            Divider()

            HStack(spacing: 0) {
                DashboardStat(
                    value: "\(summary.total)",
                    label: "Beds"
                )

                statDivider

                DashboardStat(
                    value: "\(summary.occupied)",
                    label: "Occupied"
                )

                statDivider

                DashboardStat(
                    value: "\(summary.vacant)",
                    label: "Vacant"
                )

                statDivider

                DashboardStat(
                    value: "\(summary.reserved)",
                    label: "Reserved"
                )
            }
            .padding(.vertical, 16)

            Divider()

            HStack(spacing: 14) {
                Label(
                    visibleFloorCount == totalFloorCount
                        ? "\(totalFloorCount) floors"
                        : "\(visibleFloorCount) of \(totalFloorCount) floors",
                    systemImage: "square.stack.3d.up"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                ProgressView(value: summary.occupancyPct)
                    .frame(maxWidth: 240)

                Text(summary.occupancyPct, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .padding(18)
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 46)
    }
}

struct DashboardStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}


// MARK: - Floor filters

struct FloorTypeFilterBar: View {
    @Binding var selected: FloorType?

    private let types: [(FloorType, String)] = [
        (.ms, "Med/Surg"),
        (.pc, "Prog. Care"),
        (.ic, "ICU"),
        (.ob, "OB"),
        (.op, "Outpatient")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    label: "All",
                    isSelected: selected == nil
                ) {
                    selected = nil
                }

                ForEach(types, id: \.0) { type, label in
                    FilterChip(
                        label: label,
                        isSelected: selected == type
                    ) {
                        selected = type
                    }
                }
            }
            .padding(.horizontal, 1)
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
        #if os(macOS)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear
                    .glassEffect(
                        isSelected
                            ? .regular.tint(.accentColor).interactive()
                            : .regular.interactive(),
                        in: .capsule
                    )
            } else {
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            }
        }
        #endif
    }
}


// MARK: - Floor card

struct FloorDashboardCard: View {
    let floor: FloorUnit
    let namingRule: BedNamingRule

    @State private var isExpanded = false

    private var census: CensusSummary {
        CensusSummary(floors: [floor])
    }

    private var roomCount: Int {
        floor.rooms.count
    }

    private var unavailableCount: Int {
        floor.rooms
            .flatMap(\.beds)
            .filter { $0.status == .unavailable }
            .count
    }

    private var patientCount: Int {
        floor.rooms
            .flatMap(\.beds)
            .filter { $0.patient != nil }
            .count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            metrics
            Divider()
            details
            if isExpanded {
                Divider()
                roomGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
            footer
        }
        .background(.separator, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
        .shadow(radius: 3)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var header: some View {
        HStack(spacing: 12) {
            FloorIcon(type: floor.floorType)

            VStack(alignment: .leading, spacing: 3) {
                Text(floor.floorType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(floor.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label(
                        isExpanded ? "Collapse Rooms" : "Expand Rooms",
                        systemImage: isExpanded
                            ? "rectangle.compress.vertical"
                            : "rectangle.expand.vertical"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            FloorMetric(value: census.total, label: "Beds")
            metricDivider
            FloorMetric(value: census.occupied, label: "Occupied")
            metricDivider
            FloorMetric(value: census.vacant, label: "Vacant")
        }
        .padding(.vertical, 15)
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 13) {
            GridRow {
                DetailLabel("Category")
                FloorTypeBadge(type: floor.floorType)
                    .gridColumnAlignment(.leading)
            }

            GridRow {
                DetailLabel("Rooms")
                Text("\(roomCount)")
                    .font(.subheadline.weight(.medium))
            }

            GridRow {
                DetailLabel("Patients")
                Text("\(patientCount)")
                    .font(.subheadline.weight(.medium))
            }

            GridRow {
                DetailLabel("Unavailable")
                Text("\(unavailableCount)")
                    .font(.subheadline.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var roomGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: 10)],
            spacing: 10
        ) {
            ForEach(floor.rooms) { room in
                RoomCell(room: room, namingRule: namingRule)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("\(roomCount)", systemImage: "door.left.hand.open")
            Label("\(census.reserved)", systemImage: "calendar.badge.clock")

            Spacer(minLength: 12)

            ProgressView(value: census.occupancyPct)
                .frame(maxWidth: 150)

            Text(census.occupancyPct, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(16)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 42)
    }
}

struct FloorMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(value)")
                .font(.title3.monospacedDigit().weight(.semibold))

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

struct DetailLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 86, alignment: .leading)
    }
}

struct FloorIcon: View {
    let type: FloorType

    var body: some View {
        Image(systemName: type.icon)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(type.color)
            .frame(width: 44, height: 44)
            .background(type.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
    }
}


// MARK: - Rooms and beds

struct RoomCell: View {
    let room: Room
    let namingRule: BedNamingRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Room \(room.name)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                Text("\(room.beds.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                ForEach(Array(room.beds.enumerated()), id: \.offset) { index, bed in
                    BedCell(
                        bed: bed,
                        label: namingRule.label(for: index)
                    )
                }
            }
        }
        .padding(11)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct BedCell: View {
    let bed: Bed
    let label: String

    @State private var isHovered = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(bed.status.fillColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            bed.status.strokeColor,
                            lineWidth: 0.75
                        )
                }

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(bed.status.textColor)
        }
        .frame(width: 31, height: 31)
        .scaleEffect(isHovered ? 1.12 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(bedTooltip)
    }

    private var bedTooltip: String {
        let base = "Bed \(label) · \(bed.status.displayName)"
        guard let patient = bed.patient else { return base }
        return "\(base) — \(patient.name)"
    }
}


// MARK: - Floor type presentation

extension FloorType {
    var displayName: String {
        switch self {
        case .ms: "Med/Surg"
        case .pc: "Prog. Care"
        case .ic: "ICU"
        case .ob: "OB"
        case .op: "Outpatient"
        }
    }

    var color: Color {
        switch self {
        case .ms: .blue
        case .pc: .purple
        case .ic: .red
        case .ob: .pink
        case .op: .green
        }
    }

    var icon: String {
        switch self {
        case .ms: "cross.case.fill"
        case .pc: "waveform.path.ecg"
        case .ic: "heart.text.square.fill"
        case .ob: "figure.and.child.holdinghands"
        case .op: "person.crop.circle.badge.checkmark"
        }
    }
}

struct FloorTypeBadge: View {
    let type: FloorType

    var body: some View {
        Text(type.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(type.color)
            .background(type.color.opacity(0.12), in: Capsule())
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
        var total = 0
        var occupied = 0
        var vacant = 0
        var reserved = 0

        for floor in floors {
            for room in floor.rooms {
                for bed in room.beds {
                    total += 1

                    switch bed.status {
                    case .occupied:
                        occupied += 1
                    case .vacant:
                        vacant += 1
                    case .reserved:
                        reserved += 1
                    case .unavailable:
                        break
                    }
                }
            }
        }

        self.total = total
        self.occupied = occupied
        self.vacant = vacant
        self.reserved = reserved
    }
}


// MARK: - Event log

struct CensusEventLogSheet: View {
    let events: [MockData.CensusEvent]

    @Environment(\.dismiss) private var dismiss
    @State private var kindFilter: MockData.CensusEventKind?

    private var filtered: [MockData.CensusEvent] {
        guard let kindFilter else { return events }
        return events.filter { $0.kind == kindFilter }
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
                    Button("Done") {
                        dismiss()
                    }
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

    private var kindFilterMenu: some View {
        Menu {
            Button {
                kindFilter = nil
            } label: {
                Label(
                    "All",
                    systemImage: kindFilter == nil
                        ? "checkmark"
                        : "line.3.horizontal.decrease"
                )
            }

            Divider()

            ForEach(
                [
                    MockData.CensusEventKind.admit,
                    .discharge,
                    .transfer
                ],
                id: \.self
            ) { kind in
                Button {
                    kindFilter = kind
                } label: {
                    Label(
                        kind.displayName,
                        systemImage: kindFilter == kind
                            ? "checkmark"
                            : kind.icon
                    )
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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

                if let fromBedLabel = event.fromBedLabel {
                    Text("from \(fromBedLabel)")
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

extension MockData.CensusEventKind {
    var displayName: String {
        switch self {
        case .admit: "Admit"
        case .discharge: "Discharge"
        case .transfer: "Transfer"
        }
    }

    var icon: String {
        switch self {
        case .admit: "arrow.down.circle.fill"
        case .discharge: "arrow.up.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .admit: .green
        case .discharge: .red
        case .transfer: .orange
        }
    }
}


#Preview {
    FacilityOverviewScene()
        .modelContainer(
            for: [
                Facility.self,
                FloorUnit.self,
                Room.self,
                Bed.self
            ]
        )
}
