// NameHelpers.swift
// Direct port of the JS string-parsing functions.

import Foundation

// MARK: - Brand stripping

/// Strip trailing "[Brand]" from an RxNorm name.
func stripBrand(_ name: String) -> String {
    name.replacing(#/\s*\[[^\]]*\]\s*$/#, with: "").trimmingCharacters(in: .whitespaces)
}

/// Extract the brand label from "[Brand]" if present.
func brandLabel(_ name: String) -> String? {
    guard let match = name.firstMatch(of: #/\[([^\]]*)\]\s*$/#) else { return nil }
    return String(match.output.1)
}

// MARK: - Quantity handling

/// True if name begins with a leading quantity: "2 ML …", "10 ML …"
func isQuantified(_ name: String) -> Bool {
    stripBrand(name).first?.isNumber ?? false
}

/// Remove leading quantity + unit: "2 ML docetaxel …" → "docetaxel …"
func stripLeadingQty(_ name: String) -> String {
    name.replacing(#/^\s*\d+(\.\d+)?\s*[A-Za-z%μ]+\s+/#, with: "").trimmingCharacters(in: .whitespaces)
}

/// Return just the leading quantity token: "2 ML docetaxel …" → "2 ML"
func leadingQty(_ name: String) -> String? {
    guard let match = stripBrand(name).firstMatch(of: #/^(\d+(\.\d+)?\s*[A-Za-z%μ]+)\s+/#) else { return nil }
    return String(match.output.1)
}

// MARK: - Strength extraction

private let strengthPattern = #/\d+(\.\d+)?\s*(MG|MCG|NG|G|ML|L|MEQ|MMOL|MOL|UNT|IU|U|%|CELLS|BAU|AU)(\s*\/\s*(\d+(\.\d+)?\s*)?(MG|MCG|G|ML|L|HR|ACTUAT|UNT|MEQ|MMOL|MOL))?/#

/// All strength tokens from a name, e.g. ["10 MG/ML"] or ["200 MG", "300 MG"]
func allStrengthTokens(_ name: String) -> [String] {
    let s = stripLeadingQty(stripBrand(name))
    return s.matches(of: strengthPattern).map { String(s[$0.range]).trimmingCharacters(in: .whitespaces) }
}

/// Key used to group concepts in the same strength family: ingredient + strengths, lowercased.
func strengthKey(_ name: String) -> String {
    let s = stripLeadingQty(stripBrand(name))
    var last: String.Index? = nil
    for match in s.matches(of: strengthPattern) {
        last = match.range.upperBound
    }
    let core = last.map { String(s[s.startIndex ..< $0]) } ?? s
    return core.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
}

/// Ingredient key: everything before the first digit, lowercased.
func ingredientKey(_ name: String) -> String {
    let s = stripLeadingQty(stripBrand(name))
    if let range = s.range(of: #"\d"#, options: .regularExpression),
       range.lowerBound > s.startIndex {
        return String(s[s.startIndex ..< range.lowerBound])
            .trimmingCharacters(in: .whitespaces).lowercased()
    }
    return s.lowercased().trimmingCharacters(in: .whitespaces)
}

// MARK: - Dose-form split

private let dfKeywords: [String] = [
    "Injectable", "Solution", "Suspension", "Injection", "Tablet", "Capsule",
    "Oral", "Topical", "Nasal", "Inhalation", "Inhaler", "Spray", "Film",
    "Foam", "Gel", "Powder", "Cream", "Ointment", "Lotion", "Patch",
    "Implant", "Suppository", "Enema", "Lozenge", "Wafer", "Pellet",
    "Granule", "Flake", "Paste", "Syrup", "Elixir", "Prefilled", "Syringe",
    "Auto-Injector", "Pen", "Cartridge", "Extended", "Delayed", "Sustained",
    "Release", "Disintegrating", "Chewable", "Effervescent", "Metered",
    "Dry", "Buccal", "Sublingual", "Vaginal", "Rectal", "Ophthalmic",
    "Otic", "Mucosal", "Intratracheal", "Intraperitoneal", "Irrigation",
    "Urethral", "Transdermal", "Medicated", "Shampoo", "Mouthwash",
    "Douche", "Insert"
]

/// Split an SCDF name into (ingredient, doseForm).
/// "docetaxel Injectable Solution" → ("docetaxel", "Injectable Solution")
func splitIngForm(_ name: String) -> (ing: String, form: String) {
    let s = stripBrand(name)
    for kw in dfKeywords {
        if let range = s.range(of: #"\b"# + kw, options: [.regularExpression, .caseInsensitive]) {
            let ing  = String(s[s.startIndex ..< range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let form = String(s[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            if !ing.isEmpty && !form.isEmpty { return (ing, form) }
        }
    }
    return (s, "")
}

// MARK: - Name filter

/// Split an RxNorm name into ingredient components at " / ".
func nameComponents(_ name: String) -> [String] {
    name.lowercased().components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

private func componentWords(_ comp: String) -> [String] {
    comp.components(separatedBy: .init(charactersIn: " ,()\t[]{}")).filter { !$0.isEmpty }
}

private func compMatchesToken(_ comp: String, _ token: String) -> Bool {
    componentWords(comp).contains { $0.hasPrefix(token) }
}

/// Strict match: token count must equal ingredient component count, each prefix-matching a distinct component.
func matchesTokens(_ name: String, tokens: [String]) -> Bool {
    guard !tokens.isEmpty else { return true }
    let comps = nameComponents(name)
    guard tokens.count == comps.count else { return false }
    let everyTokenHits = tokens.allSatisfy { t in comps.contains { compMatchesToken($0, t) } }
    let everyCompHit   = comps.allSatisfy { c in tokens.contains { compMatchesToken(c, $0) } }
    return everyTokenHits && everyCompHit
}

/// Loose match: every token appears somewhere in the name.
func matchesTokensLoose(_ name: String, tokens: [String]) -> Bool {
    let lower = name.lowercased()
    return tokens.allSatisfy { lower.contains($0) }
}

func tokenize(_ q: String) -> [String] {
    q.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
}

// MARK: - Display label extraction (per depth level)

enum ConceptDisplayLabel {
    case doseForm(ingredient: String, form: String)  // depth 0
    case strength(String)                             // depth 1
    case quantity(String)                             // depth 2
    case brand(String)                                // depth 3
    case raw(String)                                  // fallback
}

func displayLabel(for name: String, depth: Int) -> ConceptDisplayLabel {
    switch depth {
    case 0:
        let (ing, form) = splitIngForm(name)
        return .doseForm(ingredient: ing, form: form)
    case 1:
        let strengths = allStrengthTokens(name)
        return .strength(strengths.isEmpty ? stripLeadingQty(stripBrand(name)) : strengths.joined(separator: " / "))
    case 2:
        return .quantity(leadingQty(name) ?? stripLeadingQty(stripBrand(name)))
    case 3:
        return .brand(brandLabel(name) ?? stripBrand(name))
    default:
        return .raw(name)
    }
}

// MARK: - DFG map

/// Canonical RxNorm DoseFormGroup → DoseForm map (ported from JS DFG_MAP).
let dfgMap: [(dfg: String, forms: [String])] = [
    ("Buccal Product",            ["Buccal Film", "Buccal Tablet", "Sustained Release Buccal Tablet"]),
    ("Chewable Product",          ["Chewable Extended Release Oral Tablet", "Chewable Tablet", "Chewing Gum"]),
    ("Dental Product",            []),
    ("Disintegrating Oral Product", ["Disintegrating Oral Tablet"]),
    ("Drug Implant Product",      ["Drug Implant", "Intrauterine System"]),
    ("Flake Product",             ["Oral Flakes"]),
    ("Granule Product",           ["Delayed Release Oral Granules", "Granules for Oral Solution", "Granules for Oral Suspension", "Oral Granules"]),
    ("Inhalant Product",          ["Dry Powder Inhaler", "Gas for Inhalation", "Inhalation Powder", "Inhalation Solution", "Inhalation Spray", "Inhalation Suspension", "Metered Dose Inhaler"]),
    ("Injectable Product",        ["Auto-Injector", "Cartridge", "Injectable Foam", "Injectable Solution", "Injectable Suspension", "Injection", "Jet Injector", "Pen Injector", "Prefilled Syringe"]),
    ("Intraperitoneal Product",   ["Intraperitoneal Solution"]),
    ("Intratracheal Product",     ["Intratracheal Suspension"]),
    ("Intravesical Product",      ["Intravesical Solution", "Intravesical Suspension", "Powder for Intravesical Solution", "Powder for Intravesical Suspension"]),
    ("Irrigation Product",        ["Irrigation Solution"]),
    ("Lozenge Product",           ["Oral Lozenge"]),
    ("Medicated Pad or Tape",     ["Medicated Pad", "Medicated Tape"]),
    ("Mouthwash Product",         ["Mouthwash"]),
    ("Mucosal Product",           ["Mucosal Spray", "Mucous Membrane Topical Solution"]),
    ("Nasal Product",             ["Metered Dose Nasal Spray", "Nasal Gel", "Nasal Inhalant", "Nasal Ointment", "Nasal Powder", "Nasal Solution", "Nasal Spray", "Powder for Nasal Solution"]),
    ("Ophthalmic Product",        ["Ophthalmic Cream", "Ophthalmic Gel", "Ophthalmic Irrigation Solution", "Ophthalmic Ointment", "Ophthalmic Solution", "Ophthalmic Spray", "Ophthalmic Suspension"]),
    ("Oral Cream Product",        ["Oral Cream"]),
    ("Oral Film Product",         ["Oral Film"]),
    ("Oral Foam Product",         ["Oral Foam"]),
    ("Oral Gel Product",          ["Oral Gel"]),
    ("Oral Liquid Product",       ["Extended Release Suspension", "Oral Solution", "Oral Suspension"]),
    ("Oral Ointment Product",     ["Oral Ointment"]),
    ("Oral Paste Product",        ["Oral Paste"]),
    ("Oral Powder Product",       ["Oral Powder", "Powder for Oral Solution", "Powder for Oral Suspension", "Pack"]),
    ("Oral Product",              []),
    ("Oral Spray Product",        ["Oral Spray"]),
    ("Otic Product",              ["Otic Gel", "Otic Ointment", "Otic Solution", "Otic Suspension"]),
    ("Paste Product",             ["Paste"]),
    ("Pellet Product",            ["Oral Pellet"]),
    ("Pill",                      ["Delayed Release Oral Capsule", "Delayed Release Oral Tablet", "Effervescent Oral Tablet", "Extended Release Oral Capsule", "Extended Release Oral Tablet", "Oral Capsule", "Oral Tablet", "Tablet for Oral Suspension"]),
    ("Pyelocalyceal Product",     ["Powder for Pyelocalyceal Solution"]),
    ("Rectal Product",            ["Enema", "Rectal Cream", "Rectal Foam", "Rectal Gel", "Rectal Ointment", "Rectal Solution", "Rectal Spray", "Rectal Suppository"]),
    ("Shampoo Product",           ["Medicated Shampoo"]),
    ("Soap Product",              ["Medicated Bar Soap", "Medicated Liquid Soap"]),
    ("Sublingual Product",        ["Sublingual Film", "Sublingual Powder", "Sublingual Tablet"]),
    ("Toothpaste Product",        ["Toothpaste"]),
    ("Topical Product",           ["Powder Spray", "Topical Cream", "Topical Foam", "Topical Gel", "Topical Liquefied Gas", "Topical Lotion", "Topical Oil", "Topical Ointment", "Topical Powder", "Topical Solution", "Topical Spray", "Topical Suspension"]),
    ("Transdermal Product",       ["Medicated Patch", "Transdermal System"]),
    ("Urethral Product",          ["Urethral Suppository"]),
    ("Vaginal Product",           ["Douche", "Vaginal Cream", "Vaginal Film", "Vaginal Foam", "Vaginal Gel", "Vaginal Insert", "Vaginal Ointment", "Vaginal System"]),
    ("Wafer Product",             ["Oral Wafer"]),
]

// Pre-build lookup tables
let dfToDFG: [String: String] = {
    var d: [String: String] = [:]
    for (dfg, forms) in dfgMap { for f in forms { d[f] = dfg } }
    return d
}()

let dfgOrder: [String: Int] = {
    var d: [String: Int] = [:]
    for (i, (dfg, _)) in dfgMap.enumerated() { d[dfg] = i }
    return d
}()

let dfOrder: [String: Int] = {
    var d: [String: Int] = [:]
    for (_, forms) in dfgMap { for (j, f) in forms.enumerated() { d[f] = j } }
    return d
}()

/// All DF names sorted longest-first so "Disintegrating Oral Tablet" wins over "Oral Tablet".
let dfNamesByLength: [String] = dfToDFG.keys.sorted { $0.count > $1.count }

/// Suffix-match a concept name against the canonical DF vocabulary.
func doseFormOf(_ name: String) -> String? {
    let n = stripBrand(name)
    return dfNamesByLength.first { n.hasSuffix($0) }
}
