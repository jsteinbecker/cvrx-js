# RxNormSearch — SwiftUI Port

SwiftUI + SwiftData port of the HTML/JS RxNorm NDC search tool.

## File structure

```
RxNormSearch/
├── RxNormSearchApp.swift   App entry point, SwiftData container
├── Models.swift            Value types: RxConcept, TTY, NDCInfo, ForestNode, DFGNode, SwiftData models
├── NameHelpers.swift       All string-parsing logic (brand stripping, strength keys, DFG map, display labels)
├── RxNormService.swift     All API calls: seeds, gatherConcepts, NDC pooling, cross-pop, NDC name lookup
├── ForestBuilder.swift     4-level nesting algorithm + DFG filter tree builder
├── SearchViewModel.swift   @Observable central state, mirrors JS global state + doSearch/applyNameFilter
└── Views.swift             All SwiftUI views
```

## Architecture → JS mapping

| Swift | JS equivalent |
|---|---|
| `SearchViewModel.doSearch()` | `doSearch()` |
| `SearchViewModel.applyNameFilter()` | `applyNameFilter()` |
| `SearchViewModel.toggleDFGSubtree()` | `toggleSubtree()` |
| `buildFamilyForest()` | `buildFamilyForest()` |
| `buildDFGFilter()` | `prepareGroupsAndRender()` |
| `RxNormService.findRxcuiSeeds()` | `findRxcuiSeeds()` |
| `RxNormService.approximateSeeds()` | `approximateSeeds()` |
| `RxNormService.gatherConcepts()` | `gatherConcepts()` |
| `RxNormService.poolNDCsViaForm()` | `poolNDCsViaForm()` |
| `RxNormService.poolNDCsDirect()` | `poolNDCsDirect()` |
| `RxNormService.mergeNDCs()` | `mergeNDCs()` |
| `RxNormService.fetchNDCInfo()` | `fetchNDCName()` |
| `NameHelpers.matchesTokens()` | `matchesTokens()` |
| `NameHelpers.matchesTokensLoose()` | `matchesTokensLoose()` |
| `NameHelpers.buildFamilyForest()` | `buildFamilyForest()` |
| `APICache` actor | JS `cache` object + `cached()` |
| `SwiftData CachedNDCName` | JS `ndcNameCache` dict (persisted across sessions) |
| `SwiftData SearchHistoryEntry` | (new) search history persistence |

## Key design decisions

**APICache actor** — thread-safe replacement for the JS `cache` dict, used identically: keyed strings, async de-duplication of concurrent fetches.

**ForestNode as ObservableObject** — each node owns its own `ndcState`/`ndcResult` so NDC panels load independently without rebuilding the whole tree, mirroring the JS per-row lazy-load pattern.

**@Observable SearchViewModel** — single source of truth for all state that was spread across JS globals (`active1`, `active2`, `crossPop`, `includeCombos`, `lastUnique`, `lastTokens`, `lastVia`, `selectedGroups`, etc.).

**SwiftData models**:
- `CachedNDCName` — persists NDC product name lookups across sessions (JS kept these in `ndcNameCache` which was lost on reload)
- `SearchHistoryEntry` — stores recent searches with result counts

**FlowLayout** — custom `Layout` replacing CSS `flex-wrap` for the TTY badge bar, NDC chip grid, and DFG filter buttons.

**ConceptNameView** — uses `displayLabel(for:depth:)` to render each depth level distinctly: ingredient·form (d0), monospace strength in blue (d1), amber quantity (d2), italic purple brand (d3) — matching the CSS `.dn-d*` classes.

## To open in Xcode

1. Create a new iOS App project in Xcode (SwiftUI, SwiftData)
2. Replace the generated files with these files
3. Set deployment target to iOS 17+ (required for `@Observable`, Swift regex literals, SwiftData)
4. Build and run — no third-party dependencies

## API endpoints used (unchanged from JS)

- `GET /REST/rxcui.json?name=…&search=1&allsrc=1` — exact seed
- `GET /REST/approximateTerm.json?term=…` — fuzzy fallback seed
- `GET /REST/rxcui/{rxcui}/related.json?tty=…` — concept traversal
- `GET /REST/rxcui/{rxcui}/ndcs.json` — direct NDC fetch
- `GET /REST/ndcstatus.json?ndc=…` — NDC product name + status
