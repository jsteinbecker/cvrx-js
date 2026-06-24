//
//  MockData+Census.swift
//  cvrx
//
//  Time-stepped admit/discharge/transfer simulator that operates directly on
//  the Facility → FloorUnit → Room → Bed graph in the SwiftData store.
//
//  Requires: MockData (SeededGenerator, patientNames, patientName helpers)
//            Bed.patient: Patient?  (optional, set by this simulator)
//            Bed.occupancyStatus: OccupancyStatus (toggled by this simulator)
//

import Foundation
import SwiftData

// MARK: - Public surface

extension MockData {

    enum CensusEventKind: CaseIterable, Hashable {
        case admit, discharge, transfer
        static let allCases: [CensusEventKind] = [.admit, .discharge, .transfer]
    }

    struct CensusEvent: Identifiable {
        public let id = UUID()
        /// Zero-based tick index. Tick 0 is the initial snapshot.
        var tick: Int
        /// Wall-clock time this event represents in the simulation.
        var time: Date
        var kind: CensusEventKind
        var patientName: String
        /// Human-readable "FloorUnit · Room · Bed" label for the destination bed.
        var bedLabel: String
        /// Populated only for `.transfer`; identifies the source bed.
        var fromBedLabel: String?
    }

    /// All probability values are per-bed, per-tick.
    struct CensusParams {
        /// Probability that a vacant (or reserved) bed receives a new admit each tick.
        var admitProbability: Double = 0.18

        /// Probability that an occupied bed discharges its patient each tick.
        var dischargeProbability: Double = 0.10

        /// Of discharges, the fraction that become transfers (same patient, new bed).
        var transferShare: Double = 0.25

        /// Simulation clock step in minutes.
        var minutesPerTick: Int = 60

        /// Fraction of beds to pre-fill in the tick-0 snapshot (0…1).
        var initialOccupancy: Double = 0.60

        /// OccupancyStatus values eligible to receive a new admit.
        /// Typically [.vacant] but can include .reserved if your workflow allows it.
        var admissibleStatuses: Set<OccupancyStatus> = [.vacant]
    }

    // MARK: Entry point

    /// Runs a census simulation against every `Bed` found in the SwiftData store.
    ///
    /// Each tick represents `params.minutesPerTick` minutes of simulated time.
    /// Tick 0 seeds the initial occupancy snapshot; ticks 1…`ticks` step forward.
    ///
    /// - Parameters:
    ///   - context:  The `ModelContext` that owns the Facility/Bed graph.
    ///   - ticks:    Number of time steps *after* the initial snapshot.
    ///   - params:   Probability tunables (defaults produce a plausible census).
    ///   - seed:     Fixed seed for deterministic output; nil = random.
    /// - Returns:    Chronological `[CensusEvent]` covering all ticks.
    @MainActor
    @discardableResult
    static func simulateCensus(
        in context: ModelContext,
        ticks: Int = 12,
        params: CensusParams = CensusParams(),
        seed: UInt64? = nil
    ) -> [CensusEvent] {

        var rng = SeededGenerator(seed: seed ?? UInt64.random(in: .min ... .max))

        let allBeds = fetchAllBeds(from: context)
        guard !allBeds.isEmpty else { return [] }

        var events: [CensusEvent] = []
        var clock = Date.now

        // ── Tick 0: initial occupancy snapshot ───────────────────────────────
        for bed in allBeds where params.admissibleStatuses.contains(bed.occupancyStatus) {
            guard Double.random(in: 0...1, using: &rng) < params.initialOccupancy else { continue }
            let patient = admitNewPatient(to: bed, in: context, &rng)
            events.append(CensusEvent(
                tick: 0, time: clock, kind: .admit,
                patientName: patient.name,
                bedLabel: bedLabel(bed)
            ))
        }

        // ── Ticks 1…n ────────────────────────────────────────────────────────
        for tick in 1...max(1, ticks) {
            clock = clock.addingTimeInterval(Double(params.minutesPerTick) * 60)

            // Collect beds freed this tick so we don't immediately re-admit
            // to a bed that just emptied in the same pass.
            var freedThisTick = Set<UUID>()

            // Pass 1 — discharges / transfers on currently occupied beds.
            for bed in allBeds where bed.occupancyStatus == .occupied {
                guard Double.random(in: 0...1, using: &rng) < params.dischargeProbability
                else { continue }

                let patient = bed.patient!
                let candidateForTransfer = Double.random(in: 0...1, using: &rng) < params.transferShare

                // Vacate the source bed.
                vacate(bed)
                freedThisTick.insert(bed.id)

                if candidateForTransfer {
                    // Find another admissible bed that isn't the source and wasn't
                    // just freed this tick.
                    let dest = allBeds.first {
                        $0.id != bed.id
                        && !freedThisTick.contains($0.id)
                        && params.admissibleStatuses.contains($0.occupancyStatus)
                    }

                    if let dest {
                        occupy(dest, with: patient)
                        events.append(CensusEvent(
                            tick: tick, time: clock, kind: .transfer,
                            patientName: patient.name,
                            bedLabel: bedLabel(dest),
                            fromBedLabel: bedLabel(bed)
                        ))
                        continue    // patient stays in the store; skip delete
                    }
                    // No open bed for transfer → fall through to discharge.
                }

                // Discharge: remove patient from store.
                events.append(CensusEvent(
                    tick: tick, time: clock, kind: .discharge,
                    patientName: patient.name,
                    bedLabel: bedLabel(bed)
                ))
                context.delete(patient)
            }

            // Pass 2 — admits on beds that are admissible and weren't just freed.
            for bed in allBeds
            where params.admissibleStatuses.contains(bed.occupancyStatus)
                && !freedThisTick.contains(bed.id)
            {
                guard Double.random(in: 0...1, using: &rng) < params.admitProbability
                else { continue }

                let patient = admitNewPatient(to: bed, in: context, &rng)
                events.append(CensusEvent(
                    tick: tick, time: clock, kind: .admit,
                    patientName: patient.name,
                    bedLabel: bedLabel(bed)
                ))
            }
        }

        return events
    }

    // MARK: Reset

    /// Discharges every current patient and resets all beds to `.vacant`.
    /// Useful before re-running a simulation from scratch.
    @MainActor
    static func resetCensus(in context: ModelContext) {
        for bed in fetchAllBeds(from: context) {
            if let patient = bed.patient { context.delete(patient) }
            vacate(bed)
        }
    }
}

// MARK: - Private helpers

private extension MockData {

    // MARK: Bed operations

    @discardableResult
    static func admitNewPatient(
        to bed: Bed,
        in context: ModelContext,
        _ rng: inout SeededGenerator
    ) -> Patient {
        let patient = Patient(
            name: patientNames.randomElement(using: &rng)!,
            floor: bed.room.floor.name,
            room: bed.room.name,
            bed: bed.name
        )
        context.insert(patient)
        occupy(bed, with: patient)
        return patient
    }

    static func occupy(_ bed: Bed, with patient: Patient) {
        bed.patient = patient
        bed.occupancyStatus = .occupied
        // Keep Patient's string fields in sync with the destination bed
        // so any legacy floor/room/bed reads stay accurate.
        patient.floor = bed.room.floor.name
        patient.room = bed.room.name
        patient.bed = bed.name
    }

    static func vacate(_ bed: Bed) {
        bed.patient = nil
        bed.occupancyStatus = .vacant
    }

    // MARK: Store access

    static func fetchAllBeds(from context: ModelContext) -> [Bed] {
        (try? context.fetch(FetchDescriptor<Bed>())) ?? []
    }

    // MARK: Display label

    static func bedLabel(_ bed: Bed) -> String {
        "\(bed.room.floor.name) · \(bed.room.name) · \(bed.name)"
    }
}
