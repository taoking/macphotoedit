import AppKit
import QuartzCore
import SwiftUI

/// AppKit owns the backing layer used for the editor preview. The layer opts
/// into EDR only when its actual window screen reports headroom above SDR;
/// otherwise Core Animation keeps the preview on its normal SDR tone-mapping
/// path. This is a preview capability, not an HDR export contract.
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

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateEDRMode()
    }

    private func updateEDRMode() {
        wantsLayer = true
        let potentialHeadroom = window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        layer?.wantsExtendedDynamicRangeContent = HDRPhotoCapabilities.supportsExtendedRangePreview(
            potentialHeadroom: potentialHeadroom
        ) && wantsExtendedRange
    }
}
