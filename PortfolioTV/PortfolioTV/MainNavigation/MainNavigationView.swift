import SwiftUI

/// The signed-in app: a full-height sidebar of top-level sections over the section on screen. The app
/// opens with the sidebar hidden and focus on the content. Left or Menu brings the sidebar in over the
/// content, and moving back into the content dismisses it. Each section has its own navigation stack,
/// so moving between sections keeps your place in each.
struct MainNavigationView: View {
    @State private var viewModel = MainNavigationViewModel()
    @FocusState private var focusedSection: MainSection?

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
                    SidebarProfileHeaderView()
                }
            }
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

#Preview {
    MainNavigationView()
}
