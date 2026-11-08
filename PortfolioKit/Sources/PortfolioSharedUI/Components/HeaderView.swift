import SwiftUI

/// The title and short description at the top of a view, with room for anything that belongs below them.
public struct HeaderView<Accessory: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    let accessory: Accessory

    public init(
        title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            Label(title, systemImage: systemImage)
                .font(.title2)
                .bold()
            Text(message)
                .foregroundStyle(.secondary)
            accessory
        }
    }
}

extension HeaderView where Accessory == EmptyView {
    public init(title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

extension HeaderView {
    struct Metrics {
        static var spacing: CGFloat { 12 }
    }
}

#Preview {
    HeaderView(title: "Home", systemImage: "house", message: "Your shows and movies.")
}
