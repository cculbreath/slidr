import SwiftUI

struct GridKeyboardModifier: ViewModifier {
    let onDelete: () -> Void
    let onQuickLook: () -> Void
    let onMoveSelection: (NavigationDirection) -> Void
    let onRate: ((Int) -> Void)?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete) {
                onDelete()
                return .handled
            }
            .onKeyPress(.upArrow) {
                onMoveSelection(.up)
                return .handled
            }
            .onKeyPress(.downArrow) {
                onMoveSelection(.down)
                return .handled
            }
            .onKeyPress(.leftArrow) {
                onMoveSelection(.left)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                onMoveSelection(.right)
                return .handled
            }
            .onKeyPress(.space) {
                onQuickLook()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "012345"), phases: .down) { press in
                guard press.modifiers == .option,
                      let digit = press.characters.first?.wholeNumberValue,
                      let onRate else { return .ignored }
                onRate(digit)
                return .handled
            }
    }
}

extension View {
    func gridKeyboardHandling(
        onDelete: @escaping () -> Void,
        onQuickLook: @escaping () -> Void,
        onMoveSelection: @escaping (NavigationDirection) -> Void,
        onRate: ((Int) -> Void)? = nil
    ) -> some View {
        modifier(GridKeyboardModifier(
            onDelete: onDelete,
            onQuickLook: onQuickLook,
            onMoveSelection: onMoveSelection,
            onRate: onRate
        ))
    }
}
