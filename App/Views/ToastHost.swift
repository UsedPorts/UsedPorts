import SwiftUI

@MainActor
public final class ToastCenter: ObservableObject {
    @Published var banner: String? = nil
    @Published var toast: String? = nil

    public init() {}

    public func showBanner(_ s: String?) { banner = s }
    public func showToast(_ s: String, duration: TimeInterval = 2.5) {
        toast = s
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self?.toast == s { self?.toast = nil }
        }
    }
}

struct ToastHost<Content: View>: View {
    @ObservedObject var center: ToastCenter
    let content: () -> Content

    init(center: ToastCenter, @ViewBuilder content: @escaping () -> Content) {
        self.center = center
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            content()
            VStack(spacing: 4) {
                if let b = center.banner {
                    Text(b)
                        .padding(8)
                        .background(.red.opacity(0.85))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                        .padding(.top, 4)
                }
                if let t = center.toast {
                    Text(t)
                        .padding(8)
                        .background(.thinMaterial)
                        .cornerRadius(6)
                }
            }
            .padding(.top, 4)
        }
    }
}
