import SwiftUI

/// An item's details as the TV app's hero shows them, top to bottom: an event ("Recently Added"), its logo
/// (or title, without one), what it is (critics' score, kind, genres and boxed rating), what happens in
/// it (an episode's number and name first), dimmed, then when it's from, how long it is and its file's
/// format, less dimmed. They're shown on its platter and full-screen card, and on Home's banner, which
/// moves them to where the full-screen card shows them. A third of the screen wide, at most.
public struct MediaDetailInfoView: View {
    let viewModel: MediaDetailInfoViewModel
    /// Time left to watch, which the info line gives in place of the runtime: "1h 12m left".
    let timeLeft: String?
    /// Whether an episode is titled by its own name, under its show's, in place of its show's logo: on
    /// its own page.
    let titlesEpisode: Bool
    @Environment(\.hidesSpoilers) private var hidesSpoilers

    init(viewModel: MediaDetailInfoViewModel, timeLeft: String? = nil, titlesEpisode: Bool = false) {
        self.viewModel = viewModel
        self.timeLeft = timeLeft
        self.titlesEpisode = titlesEpisode
    }

    /// The details of `card`'s item, the very same its card shows, or for an episode's own page, titled
    /// by the episode, under its show (`titlesEpisode`).
    public init(card: MediaCardViewModel, titlesEpisode: Bool = false) {
        self.init(viewModel: card.detailInfo, timeLeft: card.canResume ? card.timeLeftLabel : nil, titlesEpisode: titlesEpisode)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            // Close over the logo, which is laid out as big as it's drawn.
            VStack(alignment: .leading, spacing: Metrics.eventSpacing) {
                if let event = viewModel.event {
                    Text(event)
                        .font(Metrics.eventFont)
                        .padding(.horizontal, Metrics.eventHorizontalPadding)
                        .padding(.vertical, Metrics.eventVerticalPadding)
                        // Backed as the buttons are.
                        .glassEffect(.regular, in: .capsule)
                }
                logo
            }
            classification
            if let description {
                description
                    .font(Metrics.descriptionFont)
                    .foregroundStyle(.white.opacity(Metrics.descriptionOpacity))
                    .lineLimit(Metrics.descriptionLineLimit)
            }
            info
        }
        // They arrive with the item's details, after the card has grown.
        .animation(Metrics.detailsFade, value: viewModel.badges)
    }

    @ViewBuilder private var logo: some View {
        if titlesEpisode, let episode = viewModel.episodeTitle {
            VStack(alignment: .leading, spacing: Metrics.episodeTitleSpacing) {
                // Vibrant: lightening the art behind it rather than laid over it in gray.
                Text(viewModel.title)
                    .font(Metrics.showTitleFont)
                    .foregroundStyle(.white.opacity(Metrics.showTitleOpacity))
                    .blendMode(.plusLighter)
                Text(episode)
                    .font(.title2)
                    .bold()
            }
            .lineLimit(2)
        } else if let logoURL = viewModel.logoURL {
            LogoView(url: logoURL, maxSize: Metrics.logoSize)
                .accessibilityElement()
                .accessibilityLabel(viewModel.title)
        } else {
            Text(viewModel.title)
                .font(.title2)
                .bold()
        }
    }

    /// "🍅 94%  ★ 7.9  Movie · Drama · Science Fiction [PG-13]".
    private var classification: some View {
        HStack(spacing: Metrics.inlineSpacing) {
            if let score = viewModel.criticScore {
                CriticScoreView(score: score)
            }
            if let rating = viewModel.communityRating {
                Label(rating, systemImage: "star.fill")
                    .labelStyle(CommunityRatingLabelStyle())
                    .accessibilityLabel("Rated \(rating) out of 10")
            }
            if !viewModel.classification.isEmpty {
                Text(viewModel.classification)
            }
            if let rating = viewModel.contentRating {
                BadgeView(label: rating)
            }
        }
        .font(Metrics.classificationFont)
        .lineLimit(1)
        // A long one runs past the block rather than being cut short.
        .fixedSize()
    }

    /// The overview, led by an episode's number and name in bold: on a show's card, its next episode's.
    /// On an episode's own page, titled by its name, just its number.
    private var description: Text? {
        let overview = viewModel.overview(hidingSpoilers: hidesSpoilers)
        let lead = titlesEpisode && viewModel.episodeTitle != nil ? viewModel.episodeNumber : viewModel.episodeLead
        switch (lead, overview) {
        case (let lead?, let overview?): return Text("\(Text("\(lead):").bold()) \(overview)")
        case (let lead?, nil): return Text(lead).bold()
        case (nil, let overview?): return Text(overview)
        case (nil, nil): return nil
        }
    }

    /// "2016 · 1h 56m", then the format's badges, small.
    @ViewBuilder private var info: some View {
        let info = viewModel.info(timeLeft: timeLeft)
        if info != nil || !viewModel.badges.isEmpty {
            HStack(spacing: Metrics.inlineSpacing) {
                if let info {
                    Text(info)
                }
                ForEach(viewModel.badges, id: \.self) { badge in
                    BadgeView(label: badge, isSmall: true)
                }
            }
            .font(Metrics.infoFont)
            .foregroundStyle(.white.opacity(Metrics.infoOpacity))
            .lineLimit(1)
        }
    }
}

extension MediaDetailInfoView {
    public struct Metrics {
        /// A third of the screen, as the TV app's, and fixed, so the text lays out the same at every card
        /// size.
        public static let width: CGFloat = 620
        static let spacing: CGFloat = 18
        static let inlineSpacing: CGFloat = 12
        static var logoSize: CGSize { MediaCardView.Metrics.detailsLogoSize }
        static var eventFont: Font { .caption2.weight(.semibold) }
        static let eventSpacing: CGFloat = 10
        static let eventHorizontalPadding: CGFloat = 14
        static let eventVerticalPadding: CGFloat = 6
        static var classificationFont: Font { .caption.weight(.medium) }
        /// An episode's show, over its name on its own page, faint beside it.
        static var showTitleFont: Font { .headline }
        static let showTitleOpacity = 0.5
        static let episodeTitleSpacing: CGFloat = 4
        static var descriptionFont: Font { .caption }
        static var infoFont: Font { .caption }
        static let descriptionLineLimit = 3
        /// The description dimmed, the info line less so, as the TV app's.
        static let descriptionOpacity = 0.55
        static let infoOpacity = 0.8
        static var detailsFade: Animation { .easeOut(duration: 0.3) }
    }

    /// A badge in a box, as the TV app's: a content rating ("PG-13") as tall as the line it's in, or
    /// small, a format ("4K"). Its text is a size smaller than the line's, so the box fits it.
    struct BadgeView: View {
        let label: String
        var isSmall = false

        var body: some View {
            Text(label)
                .font(isSmall ? Metrics.smallFont : Metrics.font)
                .padding(.horizontal, isSmall ? Metrics.smallHorizontalPadding : Metrics.horizontalPadding)
                .padding(.vertical, Metrics.verticalPadding)
                .overlay(RoundedRectangle(cornerRadius: Metrics.cornerRadius).stroke(lineWidth: Metrics.lineWidth))
                .fixedSize()
        }

        struct Metrics {
            static let horizontalPadding: CGFloat = 6
            static let smallHorizontalPadding: CGFloat = 6
            static let verticalPadding: CGFloat = 0
            static let cornerRadius: CGFloat = 5
            static let lineWidth: CGFloat = 1.5
            /// 20 points, in the 25-point line beside it. Nil here set the body's 29 points: a font of
            /// nil isn't the line's, it's the default.
            static var font: Font { .system(size: 20, weight: .semibold) }
            static var smallFont: Font { .system(size: 17, weight: .bold) }
        }
    }

    /// The community's rating beside a gold star.
    struct CommunityRatingLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: CriticScoreView.Metrics.spacing) {
                configuration.icon
                    .foregroundStyle(.yellow)
                configuration.title
            }
        }
    }

    /// The item's logo, laid out as big as it's drawn, fitted inside `maxSize`: laid out in the whole of
    /// it, a wide logo left room above it, and what sits over it floated away. Until the image is in,
    /// it takes the whole of `maxSize`.
    struct LogoView: View {
        let url: URL
        let maxSize: CGSize
        @State private var aspectRatio: CGFloat?

        var body: some View {
            let ratio = aspectRatio ?? Self.aspectRatio(of: ImagePipeline.shared.cachedImage(for: url))
            let size = ratio.map { ratio in
                ratio > maxSize.width / maxSize.height
                    ? CGSize(width: maxSize.width, height: maxSize.width / ratio)
                    : CGSize(width: maxSize.height * ratio, height: maxSize.height)
            } ?? maxSize
            // What's open or on Home's banner, so it goes ahead of posters waiting to download.
            RemoteImageView(url: url, alignment: .bottomLeading, priority: .high) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(width: size.width, height: size.height, alignment: .bottomLeading)
            .task(id: url) {
                guard aspectRatio == nil else { return }
                aspectRatio = Self.aspectRatio(of: try? await ImagePipeline.shared.image(for: url, priority: .high))
            }
        }

        private static func aspectRatio(of image: CGImage?) -> CGFloat? {
            guard let image, image.height > 0 else { return nil }
            return CGFloat(image.width) / CGFloat(image.height)
        }
    }

    /// Critics' score beside a tomato: red and whole from 60%, as fresh, else a green splat, as rotten.
    struct CriticScoreView: View {
        let score: Int

        var body: some View {
            HStack(spacing: Metrics.spacing) {
                Group {
                    if isFresh {
                        ZStack(alignment: .top) {
                            Circle()
                                .fill(Metrics.fresh)
                            LeafShape()
                                .fill(Metrics.leaf)
                                .frame(width: Metrics.size * 0.6, height: Metrics.size * 0.3)
                                .offset(y: -Metrics.size * 0.08)
                        }
                    } else {
                        SplatShape()
                            .fill(Metrics.rotten)
                    }
                }
                .frame(width: Metrics.size, height: Metrics.size)
                Text("\(score)%")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Critics \(score)%")
        }

        private var isFresh: Bool { score >= 60 }

        struct Metrics {
            static let size: CGFloat = 22
            static let spacing: CGFloat = 6
            static let fresh = Color(red: 0.95, green: 0.2, blue: 0.1)
            static let rotten = Color(red: 0.18, green: 0.74, blue: 0.27)
            static let leaf = Color(red: 0.3, green: 0.65, blue: 0.2)
        }
    }

    /// A tomato's leaves: a star of five points, flattened.
    struct LeafShape: Shape {
        func path(in rect: CGRect) -> Path {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var path = Path()
            for index in 0..<10 {
                let angle = Double(index) / 10 * 2 * .pi - .pi / 2
                let reach = index.isMultiple(of: 2) ? 1.0 : 0.4
                let point = CGPoint(
                    x: center.x + cos(angle) * rect.width / 2 * reach,
                    y: center.y + sin(angle) * rect.height / 2 * reach
                )
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }

    /// A splat, as a rotten tomato lands: a blob with uneven lobes, and drops flung off it.
    struct SplatShape: Shape {
        /// How far each point of the outline reaches, going round from the top: lobes and the dips
        /// between them.
        private static let reaches: [CGFloat] = [0.95, 0.5, 0.78, 0.45, 1.0, 0.52, 0.7, 0.42, 0.92, 0.5, 0.8, 0.44, 0.88, 0.48]

        func path(in rect: CGRect) -> Path {
            let radius = min(rect.width, rect.height) / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let points = Self.reaches.enumerated().map { index, reach in
                let angle = Double(index) / Double(Self.reaches.count) * 2 * .pi - .pi / 2
                return CGPoint(x: center.x + cos(angle) * radius * reach, y: center.y + sin(angle) * radius * reach)
            }
            func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            }
            // A smooth outline through the midpoints, pulled toward each point.
            var path = Path()
            path.move(to: midpoint(points[points.count - 1], points[0]))
            for index in points.indices {
                path.addQuadCurve(to: midpoint(points[index], points[(index + 1) % points.count]), control: points[index])
            }
            path.closeSubpath()
            for (x, y, size) in [(0.86, 0.12, 0.2), (0.06, 0.78, 0.16), (0.9, 0.86, 0.12)] as [(CGFloat, CGFloat, CGFloat)] {
                path.addEllipse(in: CGRect(
                    x: rect.minX + rect.width * x - rect.width * size / 2,
                    y: rect.minY + rect.height * y - rect.height * size / 2,
                    width: rect.width * size,
                    height: rect.height * size
                ))
            }
            return path
        }
    }
}

/// Who's in an item and who made it, beside a full-screen card's details: "Starring" and the director,
/// smaller and dimmer than the details, labels dimmest.
public struct MediaDetailCreditsView: View {
    let viewModel: MediaDetailInfoViewModel

    /// The credits of `card`'s item, the very same its full-screen card shows.
    public init(card: MediaCardViewModel) {
        viewModel = card.detailInfo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.lineSpacing) {
            ForEach(viewModel.credits, id: \.self) { line in
                Text("\(Text(line.label).foregroundStyle(.white.opacity(Metrics.labelOpacity))) \(line.names)")
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(Metrics.namesOpacity))
        .lineLimit(Metrics.lineLimit)
        .frame(width: Metrics.width, alignment: .leading)
        .animation(MediaDetailInfoView.Metrics.detailsFade, value: viewModel.credits)
    }

    public struct Metrics {
        public static let width: CGFloat = 420
        static let lineSpacing: CGFloat = 4
        static let lineLimit = 2
        static let labelOpacity = 0.5
        static let namesOpacity = 0.75
    }
}
