import SwiftUI

enum HomeCardStyle: String {
    case image
    case card
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private let cellSize: CGFloat = 128
private let gap: CGFloat = 8
private let overscan: CGFloat = 500
private let pitch: CGFloat = cellSize + gap

private struct WallMetrics {
    let blocksPerRow: Int
    let blockRows: Int
    var blockWidth: CGFloat { CGFloat(PosterWallData.blockCols) * pitch }
    var blockHeight: CGFloat { CGFloat(PosterWallData.blockRows) * pitch }
    var cellWidth: CGFloat { CGFloat(blocksPerRow) * blockWidth }
    var cellHeight: CGFloat { CGFloat(blockRows) * blockHeight }
}

private struct QueueInstance: Identifiable, Equatable {
    let id: String
    let queueIndex: Int
    let cellSlot: Int
    let repeatX: Int
    let repeatY: Int
    let rect: CGRect
        let blockColumn: Int
    let blockRow: Int
    let slotIndex: Int
}

private func makeMetrics(totalEntries: Int) -> WallMetrics {
    let blocks = max(1, Int(ceil(Double(max(0, totalEntries)) / Double(PosterWallData.slotsPerBlock))))
    let blocksPerRow = blocks <= 1 ? 1 : max(1, Int((2.2 * Double(blocks) * Double(PosterWallData.blockRows) / Double(PosterWallData.blockCols)).squareRoot().rounded()))
    let blockRows = Int(ceil(Double(blocks) / Double(blocksPerRow)))
    return WallMetrics(blocksPerRow: blocksPerRow, blockRows: blockRows)
}

private func mixBlockCoords(_ column: Int, _ row: Int) -> Int {
    var value = Int(Int32(truncatingIfNeeded: column &* 0x9e3779b1) ^ Int32(truncatingIfNeeded: row &* 0x85ebca6b))
    value = Int(Int32(truncatingIfNeeded: value ^ (value >> 15)) &* 0x2c1b3c6d)
    value ^= value >> 12
    return Int(UInt32(truncatingIfNeeded: value))
}

private func flipX(_ slots: [PosterWallData.Slot]) -> [PosterWallData.Slot] {
    slots.map { .init(x: PosterWallData.blockCols - $0.x - $0.cols, y: $0.y, cols: $0.cols, rows: $0.rows) }
}

private func flipY(_ slots: [PosterWallData.Slot]) -> [PosterWallData.Slot] {
    slots.map { .init(x: $0.x, y: PosterWallData.blockRows - $0.y - $0.rows, cols: $0.cols, rows: $0.rows) }
}

private func blockTemplate(column: Int, row: Int) -> [PosterWallData.Slot] {
    let count = PosterWallData.templates.count
    let template = ((column + row * 2) % count + count) % count
    let reflection = mixBlockCoords(column, row) % 4
    let base = PosterWallData.templates[template]
    switch reflection {
    case 1: return flipX(base)
    case 2: return flipY(base)
    case 3: return flipX(flipY(base))
    default: return base
    }
}

private func buildInstance(
    metrics: WallMetrics,
    totalEntries: Int,
    absoluteColumn: Int,
    absoluteRow: Int,
    slotIndex: Int
) -> QueueInstance {
    let repeatX = Int(floor(Double(absoluteColumn) / Double(metrics.blocksPerRow)))
    let repeatY = Int(floor(Double(absoluteRow) / Double(metrics.blockRows)))
    let localColumn = absoluteColumn - repeatX * metrics.blocksPerRow
    let localRow = absoluteRow - repeatY * metrics.blockRows
    let cellSlot = (localRow * metrics.blocksPerRow + localColumn) * PosterWallData.slotsPerBlock + slotIndex
    let slot = blockTemplate(column: localColumn, row: localRow)[slotIndex]
    let originX = CGFloat(repeatX) * metrics.cellWidth + CGFloat(localColumn) * metrics.blockWidth
    let originY = CGFloat(repeatY) * metrics.cellHeight + CGFloat(localRow) * metrics.blockHeight
    return QueueInstance(
        id: "\(cellSlot):\(repeatX):\(repeatY)",
        queueIndex: totalEntries > 0 ? cellSlot % totalEntries : 0,
        cellSlot: cellSlot,
        repeatX: repeatX,
        repeatY: repeatY,
        rect: CGRect(
            x: originX + CGFloat(slot.x) * pitch,
            y: originY + CGFloat(slot.y) * pitch,
            width: CGFloat(slot.cols) * pitch - gap,
            height: CGFloat(slot.rows) * pitch - gap
        ),
        blockColumn: absoluteColumn,
        blockRow: absoluteRow,
        slotIndex: slotIndex
    )
}

private func layoutLattice(
    metrics: WallMetrics,
    totalEntries: Int,
    view: CGRect,
    limit: Int = 400
) -> [QueueInstance] {
    guard totalEntries > 0 else { return [] }
    let expanded = view.insetBy(dx: -overscan, dy: -overscan)
    let fromColumn = Int(floor(expanded.minX / metrics.blockWidth))
    let toColumn = Int(floor(expanded.maxX / metrics.blockWidth))
    let fromRow = Int(floor(expanded.minY / metrics.blockHeight))
    let toRow = Int(floor(expanded.maxY / metrics.blockHeight))
    var result: [QueueInstance] = []
    for row in fromRow...toRow {
        for column in fromColumn...toColumn {
            for slot in 0..<PosterWallData.slotsPerBlock {
                let instance = buildInstance(
                    metrics: metrics, totalEntries: totalEntries,
                    absoluteColumn: column, absoluteRow: row, slotIndex: slot
                )
                guard instance.rect.intersects(expanded) else { continue }
                result.append(instance)
                if result.count >= limit { return result }
            }
        }
    }
    return result
}

private enum PosterArtworkCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for card: HomeCard) -> UIImage? {
        guard let data = card.artworkData else { return nil }
        let key = "\(card.id)#\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let source = UIImage(data: data)?.preparingForDisplay() else { return nil }

        let maxSide = max(source.size.width, source.size.height)
        var result = source
        if maxSide > 512 {
            let scale = 512 / maxSide
            let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            result = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        cache.setObject(result, forKey: key)
        return result
    }
}

struct PosterWallView: View {
    let cards: [HomeCard]
    let currentTrackID: String?
    let resetToken: Int
    let onSelect: (HomeCard) -> Void
    let onDelete: (HomeCard) -> Void
    let onEdit: (HomeCard) -> Void
    let onOpenPlayer: () -> Void

        @AppStorage("homeCardStyle") private var cardStyle: HomeCardStyle = .image

        @State private var cameraX: CGFloat = 0
    @State private var cameraY: CGFloat = 0
    @State private var cameraScale: CGFloat = 0.52
    @State private var viewportSize: CGSize = .zero
        @State private var centeredID: String?
    @State private var entranceDone = false
    @GestureState private var dragStart: CGPoint? = nil
            @State private var shuffleSeed: Int = Int.random(in: 1...Int.max)
            @State private var shuffleMap: [Int] = []
            @State private var instances: [QueueInstance] = []
    @State private var layoutBounds: CGRect = .null

        private func resolveScale(for width: CGFloat) -> CGFloat {
        width < 640 ? 0.52 : width < 1100 ? 0.64 : 0.76
    }

    private var metrics: WallMetrics { makeMetrics(totalEntries: cards.count) }

        private var worldView: CGRect {
        CGRect(
            x: -cameraX / cameraScale,
            y: -cameraY / cameraScale,
            width: viewportSize.width / cameraScale,
            height: viewportSize.height / cameraScale
        )
    }

            private func ensureLayout() {
        guard viewportSize.width > 0, viewportSize.height > 0, cards.count > 0 else {
            instances = []
            layoutBounds = .null
            return
        }
        let view = worldView
        if layoutBounds != .null,
           layoutBounds.insetBy(dx: overscan / 2, dy: overscan / 2).contains(view) {
            return
        }
        let expanded = view.insetBy(dx: -overscan, dy: -overscan)
        instances = layoutLattice(metrics: metrics, totalEntries: cards.count, view: expanded)
        layoutBounds = expanded
    }

    var body: some View {
        GeometryReader { geo in
            let scale = resolveScale(for: geo.size.width)

            ZStack {
                ForEach(instances) { instance in
                    let card = cards[shuffledCardIndex(instance.queueIndex)]
                    let rect = instance.rect
                    poster(card, instance: instance, rect: rect)
                        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
                        .scaleEffect(cameraScale, anchor: .topLeading)
            .offset(x: cameraX, y: cameraY)
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .updating($dragStart) { _, start, _ in
                        if start == nil { start = CGPoint(x: cameraX, y: cameraY) }
                    }
                    .onChanged { value in
                        guard let start = dragStart else { return }
                        cameraX = start.x + value.translation.width
                        cameraY = start.y + value.translation.height
                        centeredID = nil
                        ensureLayout()
                    }
                    .onEnded { _ in }
            )
            .onAppear {
                viewportSize = geo.size
                if cameraScale != scale {
                    cameraScale = scale
                }
                rebuildShuffleMap()
                centerOnQueueStart()
                ensureLayout()
                entranceDone = true
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
                cameraScale = resolveScale(for: newSize.width)
                ensureLayout()
            }
            .onChange(of: cards.count) { _, _ in
                                rebuildShuffleMap()
                layoutBounds = .null
                ensureLayout()
            }
            .onChange(of: resetToken) { _, _ in
                centeredID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    cameraX = 0
                    cameraY = 0
                    centerOnQueueStart()
                }
                ensureLayout()
            }
        }
    }

            private func shuffledCardIndex(_ queueIndex: Int) -> Int {
        let count = cards.count
        guard count > 1, !shuffleMap.isEmpty else { return 0 }
        return shuffleMap[queueIndex % count]
    }

        private func rebuildShuffleMap() {
        let n = cards.count
        guard n > 1 else {
            shuffleMap = n == 1 ? [0] : []
            return
        }
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: shuffleSeed))
        var arr = Array(0..<n)
        for i in stride(from: n - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            arr.swapAt(i, j)
        }
        shuffleMap = arr
    }

        private func centerOnQueueStart() {
        guard let first = layoutLattice(metrics: metrics, totalEntries: max(cards.count, 1), view: CGRect(x: 0, y: 0, width: 1, height: 1)).first else { return }
        let target = first.rect.midX * cameraScale
        let targetY = first.rect.midY * cameraScale
        cameraX += viewportSize.width / 2 - target
        cameraY += viewportSize.height / 2 - targetY
    }

    private func poster(_ card: HomeCard, instance: QueueInstance, rect: CGRect) -> some View {
        PosterCardContent(
            title: card.title,
            secondary: card.secondary,
            artwork: PosterArtworkCache.image(for: card),
            isCurrent: card.records.first?.id.uuidString == currentTrackID,
            width: rect.width,
            height: rect.height,
            style: cardStyle,
            zoom: cameraScale
        )
        .equatable()
        .opacity(entranceDone ? 1 : 0)
        .offset(y: entranceDone ? 0 : -18)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.85).delay(entranceDelay(for: rect)),
            value: entranceDone
        )
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(instance: instance, card: card)
        }
        .contextMenu {
            Button {
                onSelect(card)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
            if card.trackCount == nil {
                Button {
                    onEdit(card)
                } label: {
                    Label("编辑信息", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                onDelete(card)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

        private func handleTap(instance: QueueInstance, card: HomeCard) {
        if centeredID == instance.id {
            onSelect(card)
            return
        }
        centeredID = instance.id
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            cameraX = viewportSize.width / 2 - instance.rect.midX * cameraScale
            cameraY = viewportSize.height / 2 - instance.rect.midY * cameraScale
        }
        ensureLayout()
    }

        private func entranceDelay(for rect: CGRect) -> TimeInterval {
        let steps = max(0, rect.minX - worldView.minX) + max(0, rect.minY - worldView.minY)
        return min(0.34, Double(steps / pitch) * 0.03)
    }
}

private struct PosterCardContent: View, Equatable {
    let title: String
    let secondary: String
    let artwork: UIImage?
    let isCurrent: Bool
    let width: CGFloat
    let height: CGFloat
    let style: HomeCardStyle
        let zoom: CGFloat

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
            && lhs.secondary == rhs.secondary
            && lhs.artwork === rhs.artwork
            && lhs.isCurrent == rhs.isCurrent
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.style == rhs.style
            && lhs.zoom == rhs.zoom
    }

    var body: some View {
        switch style {
        case .image: imageCard
        case .card: polaroidCard
        }
    }

                private var imageCard: some View {
        let s = max(0.1, zoom)
                let textZone = 64 / s
        let shrink = min(1, height * 0.55 / max(textZone, 1))
        let titleSize = 13 / s * shrink
        let subSize = 11 / s * shrink
        return cover
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 3 / s * shrink) {
                        Text(title)
                            .font(.system(size: titleSize, weight: .bold))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2 / s * shrink)
                        if !secondary.isEmpty {
                            Text(secondary)
                                .font(.system(size: subSize, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.75))
                                .shadow(color: .black.opacity(0.5), radius: 2 / s * shrink)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12 / s * shrink)
                    .padding(.bottom, 11 / s * shrink)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
                        .shadow(color: .black.opacity(0.25), radius: 25, y: 25)
            .overlay { isCurrentRing(cornerRadius: 16) }
    }

                        private var polaroidCard: some View {
        let inset: CGFloat = 16
        let textHeight: CGFloat = 8 + 17 + 4 + 15
        let coverSide = max(0, min(width - inset * 2, height - inset * 2 - inset - textHeight))
        return VStack(spacing: 0) {
            cover
                .frame(width: coverSide, height: coverSide)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.black.opacity(0.05), lineWidth: 4)
                        .blur(radius: 2)
                        .mask(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .allowsHitTesting(false)
                }
                .padding(.bottom, inset)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .tracking(-0.35)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 4)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(inset)
        .frame(width: width, height: height, alignment: .top)
        .background {
                        ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.07).opacity(0.95))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        }
                .shadow(color: .black.opacity(0.1), radius: 7.5, y: 10)
        .overlay { isCurrentRing(cornerRadius: 12) }
    }

        private func isCurrentRing(cornerRadius: CGFloat) -> some View {
        Group {
            if isCurrent {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .shadow(color: .white.opacity(0.35), radius: 8)
                    .allowsHitTesting(false)
            }
        }
    }

        @ViewBuilder
    private var cover: some View {
        if let artwork {
            Image(uiImage: artwork)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(red: 39 / 255, green: 39 / 255, blue: 42 / 255).opacity(0.2)
                Image(systemName: "opticaldisc")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }
}
