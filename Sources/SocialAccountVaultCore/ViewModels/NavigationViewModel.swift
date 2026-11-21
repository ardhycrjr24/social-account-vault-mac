import Foundation
import SwiftUI
import Observation

/// ViewModel managing the primary navigation state, search queries, and modal sheets.
@Observable
@MainActor
public final class NavigationViewModel {
    public var selectedItem: NavigationItem? = .dashboard
    public var searchText: String = ""
    public var isShowingBackupSheet: Bool = false

    public init(selectedItem: NavigationItem? = .dashboard) {
        self.selectedItem = selectedItem
    }

    /// Updates current navigation destination.
    public func select(_ item: NavigationItem) {
        self.selectedItem = item
    }

    /// Clears any active search query.
    public func clearSearch() {
        self.searchText = ""
    }
}
