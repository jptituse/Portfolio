import PortfolioSharedUI
import SwiftUI

/// The open profile's app: a full-height sidebar, with the profile at the top and the top-level
/// sections below, over the section on screen. The app opens with the sidebar hidden and focus on the
/// content. Left or Menu brings the sidebar in over the content, and moving back into the content
/// dismisses it. Each section has its own navigation stack, so moving between sections keeps your
/// place in each.
struct MainNavigationView: View {
    let currentProfile: CurrentProfileViewModel

    @State private var viewModel = MainNavigationViewModel()
    @FocusState private var focusedSection: MainSection?

    init(currentProfile: CurrentProfileViewModel) {
        self.currentProfile = currentProfile
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            List(selection: $viewModel.selection) {
                Section {
                    ForEach(MainSection.allCases, id: \.self) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .focused($focusedSection, equals: section)
                    }
                } header: {
                    // A header rather than a row of its own: rows of a sidebar with a selection only
                    // take focus as navigation links.
                    CurrentProfileView(viewModel: currentProfile)
                }
            }
            .sidebarRowSpacing(Metrics.rowSpacing)
            // Coming into the sidebar lands on the current section, not its first row.
            .defaultFocus($focusedSection, viewModel.selection, priority: .userInitiated)
        } detail: {
            ZStack {
                ForEach(viewModel.sectionsToKeep, id: \.self) { section in
                    let isShowing = section == viewModel.selection
                    NavigationStack { view(for: section) }
                        .opacity(isShowing ? 1 : 0)
                        .disabled(!isShowing)
                        .accessibilityHidden(!isShowing)
                }
            }
        }
    }

    @ViewBuilder private func view(for section: MainSection) -> some View {
        switch section {
        case .home: HomeView()
        case .libraries: LibrariesView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}

extension MainNavigationView {
    struct Metrics {
        /// Room between the rows' highlights, as in the Apple TV app's sidebar.
        static let rowSpacing: CGFloat = 10
    }
}

private extension View {
    /// Spaces the sidebar's rows apart. Lists can only do this from tvOS 27; earlier, the rows touch.
    @ViewBuilder func sidebarRowSpacing(_ spacing: CGFloat) -> some View {
        if #available(tvOS 27, *) {
            listRowSpacing(spacing)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview {
    MainNavigationView(currentProfile: .preview())
}
#endif
