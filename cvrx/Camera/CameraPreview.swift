import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
typealias ViewRepresentable = UIViewRepresentable
#elseif canImport(AppKit)
import AppKit
typealias PlatformView = NSView
typealias ViewRepresentable = NSViewRepresentable
#endif


/// A platform view whose backing layer is always an `AVCaptureVideoPreviewLayer`.
final class PreviewView: PlatformView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    #if canImport(UIKit)
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    #elseif canImport(AppKit)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = AVCaptureVideoPreviewLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    #endif
}



struct CameraPreview: ViewRepresentable {
    let session: AVCaptureSession

    private func makeView() -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    private func updateView(_ view: PreviewView) {
        if view.videoPreviewLayer.session !== session {
            view.videoPreviewLayer.session = session
        }
    }

    #if canImport(UIKit)
    func makeUIView(context: Context) -> PreviewView { makeView() }
    func updateUIView(_ uiView: PreviewView, context: Context) { updateView(uiView) }
    #elseif canImport(AppKit)
    func makeNSView(context: Context) -> PreviewView { makeView() }
    func updateNSView(_ nsView: PreviewView, context: Context) { updateView(nsView) }
    #endif
}
