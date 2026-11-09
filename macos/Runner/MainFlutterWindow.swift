import Cocoa
import FlutterMacOS
import ImageIO
import Vision

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()

    // Keep the window itself opaque so WindowServer does not have to blend the
    // whole video window with the desktop every frame. Flutter stays clear so
    // the native video layer behind it remains visible.
    self.isOpaque = true
    self.backgroundColor = NSColor.black
    flutterViewController.backgroundColor = NSColor.clear

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Configure window chrome before restoring the saved frame.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // Add forwarding toolbar for click-through in titlebar area
    let toolbar = ForwardingToolbar(flutterViewController: flutterViewController)
    self.toolbar = toolbar

    MpvPlayerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MpvPlayerPlugin"))

    MpvAudioPlayerPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MpvAudioPlayerPlugin"))

    WindowUtilsPlugin.register(
      with: flutterViewController.registrar(forPlugin: "WindowUtilsPlugin"))
    WindowUtilsPlugin.setWindow(self)
    WindowUtilsPlugin.installWindowDelegate()
    WindowUtilsPlugin.syncWindowChrome()

    AppLookupPlugin.register(
      with: flutterViewController.registrar(forPlugin: "AppLookupPlugin"))

    DeepLinkPlugin.register(
      with: flutterViewController.registrar(forPlugin: "DeepLinkPlugin"))

    AstraArtFocus.register(
      messenger: flutterViewController.registrar(forPlugin: "AstraArtFocus").messenger)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.setFrameAutosaveName("com.edde746.plezy.MainWindow")
    WindowUtilsPlugin.syncWindowChrome()

    super.awakeFromNib()
  }
}


/// Astra: finds where the faces (or, failing that, the most eye-catching
/// subject) sit in a backdrop so the app can frame the art around them.
/// Returns normalized rects with a top-left origin.
final class AstraArtFocus {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "astra/art_focus", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "analyze",
            let args = call.arguments as? [String: Any],
            let string = args["url"] as? String,
            let url = URL(string: string) else {
        result(FlutterMethodNotImplemented)
        return
      }
      URLSession.shared.dataTask(with: url) { data, _, _ in
        let out = data.flatMap { AstraArtFocus.analyze($0) }
        DispatchQueue.main.async { result(out) }
      }.resume()
    }
  }

  static func analyze(_ data: Data) -> [String: Any]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    var out: [String: Any] = ["width": image.width, "height": image.height]
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let faces = VNDetectFaceRectanglesRequest()
    let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
    try? handler.perform([faces, saliency])
    func flip(_ r: CGRect) -> [Double] {
      [Double(r.minX), Double(1 - r.maxY), Double(r.width), Double(r.height)]
    }
    let faceRects = (faces.results ?? []).filter { $0.confidence > 0.6 }.map { flip($0.boundingBox) }
    if !faceRects.isEmpty { out["faces"] = faceRects }
    if let obs = saliency.results?.first, let objects = obs.salientObjects, !objects.isEmpty {
      out["salient"] = objects.map { flip($0.boundingBox) }
    }
    return out
  }
}
