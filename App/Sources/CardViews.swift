import PokerCore
import SwiftUI

extension Card {
    var symbol: String {
        switch suit {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    var rankLabel: String {
        switch rank {
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        case 14: "A"
        default: "\(rank)"
        }
    }

    var isRed: Bool { suit == .hearts || suit == .diamonds }

    /// For VoiceOver, e.g. "Ace of hearts".
    var spokenName: String {
        let rankName =
            switch rank {
            case 11: "Jack"
            case 12: "Queen"
            case 13: "King"
            case 14: "Ace"
            default: "\(rank)"
            }
        let suitName =
            switch suit {
            case .clubs: "clubs"
            case .diamonds: "diamonds"
            case .hearts: "hearts"
            case .spades: "spades"
            }
        return "\(rankName) of \(suitName)"
    }
}

private extension [Card] {
    var spokenNames: String { map(\.spokenName).joined(separator: ", ") }
}

/// Card size and shape shared by face, back and slot: 5:7, corners at 12 % of the width.
private struct CardShape: ViewModifier {
    let width: CGFloat

    func body(content: Content) -> some View {
        content.frame(width: width, height: width * 1.4).clipShape(.rect(cornerRadius: width * 0.12))
    }
}

struct CardFaceView: View {
    let card: Card
    let width: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Text(card.rankLabel).font(.system(size: width * 0.42, weight: .bold, design: .rounded))
            Text(card.symbol).font(.system(size: width * 0.42))
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .foregroundStyle(card.isRed ? theme.cardRed : theme.cardText)
        .frame(width: width, height: width * 1.4)
        .background(theme.cardFace)
        .overlay(RoundedRectangle(cornerRadius: width * 0.12).strokeBorder(theme.cardFrame, lineWidth: max(1, width * 0.03)))
        .modifier(CardShape(width: width))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.spokenName)
    }
}

struct CardBackView: View {
    let back: CardBack
    let width: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let inset = width * 0.08
        let line = max(0.5, width * 0.012)
        let frame = theme.cardFrame
        let inner = RoundedRectangle(cornerRadius: width * 0.08)
        back.color
            .overlay {
                Canvas { context, size in
                    // Two sets of diagonals at a fixed step form the diamond lattice.
                    let step = max(2, width * 0.09)
                    var path = Path()
                    var x = -size.height
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += step
                    }
                    context.stroke(path, with: .color(frame.opacity(0.35)), lineWidth: line)
                }
                .clipShape(inner)
                .overlay(inner.strokeBorder(frame, lineWidth: line * 1.5))
                .padding(inset)
            }
            .modifier(CardShape(width: width))
            .accessibilityHidden(true)
    }
}

/// Where a card will lie, e.g. a board card not dealt yet.
struct CardSlotView: View {
    let width: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.12)
            .strokeBorder(theme.cardFrame.opacity(0.25), lineWidth: max(1, width * 0.03))
            .modifier(CardShape(width: width))
            .accessibilityHidden(true)
    }
}

/// Cards inline, e.g. `A♥ K♠`, with hearts and diamonds in the theme's red.
struct CardsText: View {
    let cards: [Card]
    @Environment(\.theme) private var theme

    var body: some View {
        Text(attributed).accessibilityLabel(cards.spokenNames)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, card) in cards.enumerated() {
            if index > 0 { result += AttributedString(" ") }
            var part = AttributedString(card.rankLabel + card.symbol)
            if card.isRed { part.foregroundColor = theme.cardRed }
            result += part
        }
        return result
    }
}

/// The own two hole cards: face down unless `faceUp`, shown while pressed, or through the "Show cards" action.
struct HoleCardsView: View {
    let cards: [Card]
    let faceUp: Bool
    let width: CGFloat
    @AppStorage("cardBack") private var back = CardBack.red
    @GestureState private var pressed = false
    @State private var revealed = false

    var body: some View {
        let shown = faceUp || pressed || revealed
        HStack(spacing: width * 0.1) {
            ForEach(cards, id: \.self) { card in
                if shown { CardFaceView(card: card, width: width) } else { CardBackView(back: back, width: width) }
            }
        }
        .contentShape(.rect)
        .gesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = true })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? cards.spokenNames : "Your cards, hidden")
        .accessibilityActions {
            if !faceUp {
                Button(revealed ? "Hide cards" : "Show cards") {
                    revealed.toggle()
                    if revealed { AccessibilityNotification.Announcement(cards.spokenNames).post() }
                }
            }
        }
        .onChange(of: cards) { revealed = false }
    }
}

#Preview {
    let cards = [Card("Ah")!, Card("Ts")!]
    VStack(spacing: 0) {
        ForEach([("Felt", Theme.felt), ("Dark", Theme.dark)], id: \.0) { _, theme in
            VStack(spacing: 12) {
                HStack {
                    CardFaceView(card: cards[0], width: 48)
                    CardFaceView(card: cards[1], width: 48)
                    CardSlotView(width: 48)
                }
                HStack {
                    ForEach(CardBack.allCases, id: \.self) { CardBackView(back: $0, width: 36) }
                }
                CardsText(cards: cards).foregroundStyle(theme.text)
                HoleCardsView(cards: cards, faceUp: false, width: 56)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface[0])
            .environment(\.theme, theme)
        }
    }
}
