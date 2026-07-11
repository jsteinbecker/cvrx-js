//
//  DateSelector.swift
//  cvrx
//
//  A reusable YYYY/MM/DD date entry field for iOS / Mac Catalyst.
//
//  Behavior
//  --------
//  • Looks like a single bordered text input when unfocused.
//  • Internally three segments (year / month / day) so the user can type
//    straight through ("20260315" auto-advances across segments) AND each
//    segment can be blanked independently, rendering as ----/--/--.
//  • Tab moves Year → Month → Day → next form control (segments are real
//    focusable TextFields).
//  • Focusing any segment opens a popover with a day grid, a month grid,
//    and a year row (current year ... +7). Picking from the popover and
//    typing both write the same underlying value.
//  • Binds to an optional `Date`. The binding is non-nil only when all three
//    components form a real Gregorian date (rejects e.g. Feb 30); otherwise
//    it is nil (partial / blank).
//
//  Usage
//  -----
//      @State private var beyondUseDate: Date? = nil
//      ...
//      CompoundingDateField(date: $beyondUseDate)
//
//  Inject a calendar if you need a fixed time zone for round-tripping:
//      CompoundingDateField(date: $bud, calendar: myCalendar)
//

import SwiftUI

// MARK: - PartialDate

/// A calendar date whose components may be individually unset, allowing the
/// field to represent partially-entered or fully-blank states.
public struct PartialDate: Equatable {
    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date?, calendar: Calendar) {
        guard let date else { self.init(); return }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year, month: c.month, day: c.day)
    }

    public var isEmpty: Bool { year == nil && month == nil && day == nil }
    public var isComplete: Bool { year != nil && month != nil && day != nil }

    /// Returns a real `Date` only when all three components form a valid
    /// Gregorian date (e.g. rejects Feb 30, day 31 in April).
    public func date(in calendar: Calendar) -> Date? {
        guard let y = year, let m = month, let d = day else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        guard let date = calendar.date(from: c) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return date
    }
}

// MARK: - CompoundingDateField

public struct DateSelector: View {

    @Binding private var date: Date?
    private let calendar: Calendar

    public init(date: Binding<Date?>,
                calendar: Calendar = Calendar(identifier: .gregorian)) {
        self._date = date
        self.calendar = calendar
    }

    private enum Segment: Hashable { case year, month, day }

    @FocusState private var focus: Segment?
    @State private var yearText = ""
    @State private var monthText = ""
    @State private var dayText = ""

    // MARK: Body

    public var body: some View {
        HStack(spacing: 4) {
            segment($yearText, .year, placeholder: "----", width: 50)
                .onChange(of: yearText) { _, new in handleYear(new) }

            Text("/").foregroundStyle(.secondary)
                .onTapGesture { focus = .year }

            segment($monthText, .month, placeholder: "--", width: 30)
                .onChange(of: monthText) { _, new in handleMonth(new) }
                .onKeyPress(.delete) { backspaceJump(from: .month) }

            Text("/").foregroundStyle(.secondary)
                .onTapGesture { focus = .month }

            segment($dayText, .day, placeholder: "--", width: 30)
                .onChange(of: dayText) { _, new in handleDay(new) }
                .onKeyPress(.delete) { backspaceJump(from: .day) }

            if !currentPartial().isEmpty {
                Button {
                    clearAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear date")
            }
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focus != nil ? Color.accentColor : Color.secondary.opacity(0.4),
                        lineWidth: focus != nil ? 2 : 1)
        )
        // Popover opens on focus and closes when focus leaves the whole field
        // (e.g. Tab to the next control). Popover buttons re-assert focus so a
        // tap inside the popover never collapses it.
        .popover(isPresented: Binding(
            get: { focus != nil },
            set: { if !$0 { focus = nil } })
        ) {
            pickerPopover()
        }
        .onAppear { loadFromDate() }
        .onChange(of: date) { _, newDate in
            if newDate != currentPartial().date(in: calendar) { loadFromDate() }
        }
    }

    // MARK: Segment field

    private func segment(_ text: Binding<String>,
                         _ seg: Segment,
                         placeholder: String,
                         width: CGFloat) -> some View {
                                TextField(placeholder, text: text)
                                    .focused($focus, equals: seg)
                                    .multilineTextAlignment(.center)
                                    .textFieldStyle(.plain)
                                    .frame(width: width)
                                    #if os(iOS)
                                    .keyboardType(.numberPad)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .autocorrectionDisabled()
                            }

    // MARK: Typing handlers

    private func handleYear(_ new: String) {
        let s = sanitizeYear(new)
        if s != new { yearText = s; return }
        clampDayIfNeeded(); commit()
        if s.count == 4, focus == .year { focus = .month }
    }

    private func handleMonth(_ new: String) {
        let s = sanitizeMonth(new)
        if s != new { monthText = s; return }
        clampDayIfNeeded(); commit()
        if s.count == 2, focus == .month { focus = .day }
    }

    private func handleDay(_ new: String) {
        let s = sanitizeDay(new)
        if s != new { dayText = s; return }
        commit()
    }

    /// Backspace on an empty segment jumps to the previous segment and trims a
    /// digit (hardware-keyboard convenience). Non-empty segments delete normally.
    private func backspaceJump(from seg: Segment) -> KeyPress.Result {
        switch seg {
        case .month where monthText.isEmpty:
            focus = .year
            if !yearText.isEmpty { yearText.removeLast() }
            return .handled
        case .day where dayText.isEmpty:
            focus = .month
            if !monthText.isEmpty { monthText.removeLast() }
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: Sanitizers

    private func sanitizeYear(_ s: String) -> String {
        String(s.filter(\.isNumber).prefix(4))
    }

    private func sanitizeMonth(_ s: String) -> String {
        var d = String(s.filter(\.isNumber).prefix(2))
        if let v = Int(d), v > 12 { d = "12" }
        return d
    }

    private func sanitizeDay(_ s: String) -> String {
        var d = String(s.filter(\.isNumber).prefix(2))
        let maxD = daysInMonth()
        if let v = Int(d), v > maxD { d = String(maxD) }
        return d
    }

    private func clampDayIfNeeded() {
        let maxD = daysInMonth()
        if let v = Int(dayText), v > maxD { dayText = String(format: "%02d", maxD) }
    }

    // MARK: Model glue

    private func currentPartial() -> PartialDate {
        PartialDate(year: Int(yearText), month: Int(monthText), day: Int(dayText))
    }

    private func commit() {
        let newDate = currentPartial().date(in: calendar)
        if newDate != date { date = newDate }
    }

    private func loadFromDate() {
        let p = PartialDate(date, calendar: calendar)
        yearText  = p.year.map  { String(format: "%04d", $0) } ?? ""
        monthText = p.month.map { String(format: "%02d", $0) } ?? ""
        dayText   = p.day.map   { String(format: "%02d", $0) } ?? ""
    }

    private func clearAll() {
        yearText = ""; monthText = ""; dayText = ""
        commit()
        focus = .year
    }

    /// Days in the currently-entered month. When the year is unknown, uses a
    /// leap year so Feb 29 is selectable; full-date validation rejects truly
    /// invalid combinations on commit.
    private func daysInMonth() -> Int {
        guard let m = Int(monthText), (1...12).contains(m) else { return 31 }
        var c = DateComponents()
        c.year = Int(yearText) ?? 2000
        c.month = m
        c.day = 1
        guard let date = calendar.date(from: c),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    // MARK: Popover

    @ViewBuilder
    private func pickerPopover() -> some View {
        let selectedYear  = Int(yearText)
        let selectedMonth = Int(monthText)
        let selectedDay   = Int(dayText)
        let startYear = calendar.component(.year, from: Date())
        let years = Array(startYear...(startYear + 7))
        let symbols = calendar.shortMonthSymbols
        let maxDay = daysInMonth()

        let dayCols   = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let monthCols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        let yearCols  = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

        VStack(alignment: .leading, spacing: 14) {
            // Day grid
            section("Day") {
                LazyVGrid(columns: dayCols, spacing: 4) {
                    ForEach(1...31, id: \.self) { d in
                        cell("\(d)",
                             selected: selectedDay == d,
                             disabled: d > maxDay) {
                            dayText = String(format: "%02d", d)
                            focus = .day
                        }
                    }
                }
            }

            Divider()

            // Month grid
            section("Month") {
                LazyVGrid(columns: monthCols, spacing: 6) {
                    ForEach(0..<min(12, symbols.count), id: \.self) { i in
                        cell(symbols[i], selected: selectedMonth == i + 1) {
                            monthText = String(format: "%02d", i + 1)
                            clampDayIfNeeded()
                            focus = .month
                        }
                    }
                }
            }

            Divider()

            // Year row
            section("Year") {
                LazyVGrid(columns: yearCols, spacing: 6) {
                    ForEach(years, id: \.self) { y in
                        cell("\(y)", selected: selectedYear == y) {
                            yearText = String(y)
                            clampDayIfNeeded()
                            focus = .year
                        }
                    }
                }
            }

            HStack {
                Button("Clear", role: .destructive) { clearAll() }
                Spacer()
                Button("Done") { focus = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 320)
        .presentationCompactAdaptation(.popover) // stay a popover on iPhone too
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func cell(_ label: String,
                      selected: Bool,
                      disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(selected ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? Color.white
                                 : (disabled ? Color.secondary.opacity(0.4) : Color.primary))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var bud: Date? = nil
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Beyond-use date").font(.headline)
                DateSelector(date: $bud)
                TextField("Next field (Tab target)", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                Text(bud.map { $0.formatted(date: .abbreviated, time: .omitted) }
                     ?? "— no date —")
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(width: 440)
        }
    }
    return Demo()
}
