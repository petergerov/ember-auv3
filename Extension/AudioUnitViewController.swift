import CoreAudioKit
import SwiftUI

#if os(macOS)
private typealias PlatformHostingController = NSHostingController
#else
private typealias PlatformHostingController = UIHostingController
#endif

/// Extension principal class: creates the Audio Unit and hosts the SwiftUI editor.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnit: EmberAudioUnit?
    private var viewModel: EmberViewModel?
    private var hostingController: PlatformHostingController<EmberEditorView>?

    // Hosts may call this on any thread, so it must not touch main-actor state directly.
    nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let audioUnit = try EmberAudioUnit(componentDescription: componentDescription, options: [])
        Task { @MainActor [weak self] in
            self?.connect(to: audioUnit)
        }
        return audioUnit
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 560, height: 400)
        installEditorIfReady()
    }

    private func connect(to audioUnit: EmberAudioUnit) {
        self.audioUnit = audioUnit
        installEditorIfReady()
    }

    /// The Audio Unit and the view can arrive in either order.
    private func installEditorIfReady() {
        guard isViewLoaded, hostingController == nil,
              let audioUnit, let viewModel = EmberViewModel(audioUnit: audioUnit)
        else { return }

        self.viewModel = viewModel
        let hostingController = PlatformHostingController(rootView: EmberEditorView(viewModel: viewModel))
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.hostingController = hostingController
    }

    isolated deinit {
        viewModel?.disconnect()
    }
}
