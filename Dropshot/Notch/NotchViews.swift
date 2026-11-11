import DropshotCore
import SwiftUI

/// Fills the transparent panel and pins the island to its top-centre.
struct NotchRootView: View {
    let model: NotchViewModel

    var body: some View {
        IslandView(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}

/// The black island. Its *size* animates between the hardware notch and the expanded
/// card; content is laid out once at the expanded size and revealed by the growing shape.
struct IslandView: View {
    let model: NotchViewModel

    var body: some View {
        let layout = model.layout
        let scale = layout.scale
        let open = model.isExpanded
        // With Reduce Motion the island does not grow; it cross-fades at full size.
        let large = open || model.reduceMotion
        let size = large ? layout.expandedSize : layout.collapsedSize
        let isNotch = layout.style == .notch

        ZStack(alignment: .top) {
            Color.black
            IslandContent(model: model)
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height)
                .opacity(open ? 1 : 0)
                .scaleEffect(open || model.reduceMotion ? 1 : 0.8, anchor: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(IslandShape(
            style: layout.style,
            topRadius: large && isNotch ? 8 * scale : 0,
            bottomRadius: large ? 26 * scale : (isNotch ? 8 : 3)))
        .background { if !model.isStatic { HoverTracker { model.onHoverChanged($0) } } }
        .shadow(color: .black.opacity(large ? (isNotch ? 0.28 : 0.4) : 0), radius: 14, y: 8)
        .opacity(model.reduceMotion && !open ? 0 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot preview")
    }
}

/// Notch style: flat top that flares into the menu bar with small concave "ears", rounded
/// bottom. Pill style: a plain rounded rectangle.
struct IslandShape: Shape {
    var style: IslandStyle
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .pill:
            let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
            return Path(roundedRect: rect, cornerRadius: max(0, radius), style: .continuous)
        case .notch:
            let top = max(0, min(topRadius, rect.width / 4))
            let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                control: CGPoint(x: rect.minX + top, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                control: CGPoint(x: rect.minX + top, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                control: CGPoint(x: rect.maxX - top, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - top, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Content

private struct IslandContent: View {
    let model: NotchViewModel

    var body: some View {
        let layout = model.layout
        let scale = layout.scale
        let isNotch = layout.style == .notch

        HStack(alignment: .center, spacing: 12 * scale) {
            ThumbnailStack(model: model)
            if let item = model.top {
                InfoColumn(model: model, item: item)
                    .id(item.id)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, (isNotch ? 22 : 16) * scale)
        .padding(.trailing, (isNotch ? 20 : 12) * scale)
        .padding(.top, layout.topInset + (isNotch ? 4 : 12) * scale)
        .padding(.bottom, 12 * scale)
    }
}

private struct ThumbnailStack: View {
    let model: NotchViewModel

    var body: some View {
        let scale = model.layout.scale
        let box = CGSize(width: 116 * scale, height: 72 * scale)
        let visible = Array(model.items.prefix(3))

        ZStack(alignment: .topTrailing) {
            ZStack {
                // Oldest at the back, newest on top.
                ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { index, item in
                    ThumbnailCard(item: item, scale: scale, fill: index > 0)
                        .frame(width: box.width, height: box.height)
                        .scaleEffect(1 - CGFloat(index) * 0.07)
                        .offset(y: CGFloat(index) * -5 * scale)
                        .opacity(index == 0 ? 1 : 0.55)
                        .zIndex(Double(-index))
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: box.width, height: box.height)
            .overlay {
                if let item = model.top, !model.isStatic {
                    DragSource(
                        item: item,
                        onClick: { model.onOpen(item) },
                        onBegan: { model.onDragBegan(item) },
                        onEnded: { model.onDragEnded(item, $0) })
                        .help("Drag into any app · click to open")
                }
            }

            if model.items.count > 1 {
                Text("\(model.items.count)")
                    .font(.system(size: 11 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(Color.accentColor))
                    .overlay(Capsule().strokeBorder(.black, lineWidth: 1.5))
                    .offset(x: 7 * scale, y: -5 * scale)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityLabel("\(model.items.count) screenshots")
            }
        }
    }
}

private struct ThumbnailCard: View {
    let item: PreviewItem
    let scale: CGFloat
    /// Cards further back in the stack fill the whole slot so the deck looks tidy.
    var fill = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
        Group {
            if let thumbnail = item.thumbnail, fill {
                Color.clear.overlay {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: item.kind == .image ? "photo" : "video")
                        .font(.system(size: 20 * scale))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            if item.kind == .recording {
                Image(systemName: "video.fill")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4 * scale)
                    .background(Circle().fill(.black.opacity(0.6)))
                    .padding(4 * scale)
            }
        }
    }
}

private struct InfoColumn: View {
    let model: NotchViewModel
    let item: PreviewItem

    var body: some View {
        let scale = model.layout.scale
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(item.statusText)
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(Color(red: 0.35, green: 0.9, blue: 0.5))
            Text(item.detailText)
                .font(.system(size: 11 * scale, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))

            Spacer(minLength: 2 * scale)

            // Same slot, two states — no layout jump when the pointer arrives.
            ZStack(alignment: .leading) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(model.isHovering ? 0 : 1)

                HStack(spacing: 6 * scale) {
                    IslandButton(symbol: "arrow.up.forward.app", label: "Open", scale: scale) {
                        model.onOpen(item)
                    }
                    IslandButton(symbol: "folder", label: "Show in Finder", scale: scale) {
                        model.onReveal(item)
                    }
                    IslandButton(symbol: "trash", label: "Move to Trash", scale: scale, tint: .red) {
                        model.onDelete(item)
                    }
                }
                .opacity(model.isHovering ? 1 : 0)
                .allowsHitTesting(model.isHovering)
            }
            .frame(height: 24 * scale)
            .animation(.easeOut(duration: 0.12), value: model.isHovering)
        }
        .lineLimit(1)
    }
}

private struct IslandButton: View {
    let symbol: String
    let label: String
    let scale: CGFloat
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12 * scale, weight: .medium))
                .foregroundStyle(tint == .white ? Color.white : Color(red: 1, green: 0.42, blue: 0.4))
                .frame(width: 30 * scale, height: 24 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                        .fill(.white.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
