import SwiftUI
import TipKit

// TipKit tips for other screens to attach with `.popoverTip(...)` or `TipView(...)`.

struct DiskMapCollectorTip: Tip {
    var title: Text { Text("Collect as you explore") }
    var message: Text? { Text("Drag segments or rows into the Collector, then move everything to the Trash at once.") }
    var image: Image? { Image(systemName: "tray.and.arrow.down.fill") }
}

struct ProjectsStaleTip: Tip {
    var title: Text { Text("Start with stale projects") }
    var message: Text? { Text("“Select stale” picks build folders from projects you haven't touched recently, and only ones a lockfile can restore.") }
    var image: Image? { Image(systemName: "hammer.fill") }
}

struct SweepReviewTip: Tip {
    var title: Text { Text("Review before cleaning") }
    var message: Text? { Text("Expand a category to see every path it contains, and deselect anything you want to keep.") }
    var image: Image? { Image(systemName: "eye") }
}

struct TwinsKeepTip: Tip {
    var title: Text { Text("One copy is always kept") }
    var message: Text? { Text("In every duplicate group one copy is marked Keep. Choose “Keep this copy” on another file to change it.") }
    var image: Image? { Image(systemName: "square.on.square") }
}

struct MenuBarTip: Tip {
    var title: Text { Text("TidyBug is in your menu bar") }
    var message: Text? { Text("Check free space, CPU and memory, or clean safe items without opening the app.") }
    var image: Image? { Image(systemName: "externaldrive") }
}
