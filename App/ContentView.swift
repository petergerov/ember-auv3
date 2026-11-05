import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "flame.fill")
                .font(.system(size: 54))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
            Text("Ember")
                .font(.largeTitle.weight(.semibold))
            Text("One-knob warm mastering, as an Audio Unit (AUv3) effect.")
                .foregroundStyle(.secondary)
            InstallNotes()
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(minWidth: 420)
    }
}

private struct InstallNotes: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("The plugin is installed. Insert **Gerov: Ember** on a track in your host.")
            #if os(macOS)
            Text("Logic Pro, GarageBand, Ableton Live and other AU hosts list it under Audio Units → Gerov.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #else
            Text("AUM, Logic Pro for iPad, GarageBand and other AUv3 hosts list it under Effects.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #endif
        }
    }
}

#Preview {
    ContentView()
}
