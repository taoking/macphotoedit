import AppKit
import QuartzCore
import SwiftUI

/// AppKit owns the backing layer used for the editor preview. Opting that layer
/// into EDR lets a half-float TIFF preview reach a compatible HDR display while
/// retaining normal system tone mapping on an SDR display.
struct ExtendedRangeImageView: NSViewRepresentable {
    let image: NSImage
    let enablesExtendedRange: Bool

    func makeNSView(context: Context) -> EDRImageView {
        let view = EDRImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageAlignment = .alignCenter
        return view
    }

    func updateNSView(_ view: EDRImageView, context: Context) {
        view.image = image
        view.wantsExtendedRange = enablesExtendedRange
    }
}

final class EDRImageView: NSImageView {
    var wantsExtendedRange = false {
        didSet { updateEDRMode() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        updateEDRMode()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        updateEDRMode()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEDRMode()
    }

    private func updateEDRMode() {
        wantsLayer = true
        layer?.wantsExtendedDynamicRangeContent = wantsExtendedRange
    }
}
