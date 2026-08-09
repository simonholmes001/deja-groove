import SwiftUI

#if os(iOS)
enum DejaGrooveStyle {
    static let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let blue = Color(red: 0.02, green: 0.42, blue: 0.95)
    static let coral = Color(red: 1.00, green: 0.33, blue: 0.22)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.98)

    static var screenBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.98, blue: 1.00),
                Color(red: 0.92, green: 0.93, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing)
    }
}

struct DejaGrooveScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            DejaGrooveStyle.screenBackground
                .ignoresSafeArea()
            content
        }
    }
}

struct DejaGroovePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.65), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }
}

struct DejaGroovePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [DejaGrooveStyle.blue, DejaGrooveStyle.coral],
                    startPoint: .leading,
                    endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: DejaGrooveStyle.blue.opacity(configuration.isPressed ? 0.12 : 0.24), radius: 16, y: 8)
    }
}
#endif
