import os

/// Signposts for the history panel. Intervals show in Instruments under the History category.
enum HistorySignpost {
    static let signposter = OSSignposter(subsystem: "com.donovanhiland.navi", category: "History")
}
