import SwiftUI

public struct NagRootView: View {
  public init() {}

  public var body: some View {
    Text("NagReminders")
      .font(.largeTitle.weight(.bold))
      .padding()
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .padding()
  }
}
