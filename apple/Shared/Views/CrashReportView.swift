#if os(iOS) || os(macOS)
  import AstraKit
  import SwiftUI
  #if os(iOS)
    import UIKit
  #else
    import AppKit
  #endif

  extension View {
    /// After a crash, the next launch opens "Astra crashed" with the report
    /// (KP, 2026-11-12). Copy puts it on the clipboard; Send opens the share sheet.
    func crashReportSheet() -> some View {
      modifier(CrashReportPresenter())
    }
  }

  private struct CrashReportPresenter: ViewModifier {
    @State private var reporter = CrashReporter.shared

    func body(content: Content) -> some View {
      content.sheet(
        isPresented: Binding(get: { reporter.pending != nil }, set: { if !$0 { reporter.dismiss() } })
      ) {
        CrashReportView(report: reporter.pending ?? "") { reporter.dismiss() }
          #if os(macOS)
            .frame(width: 560, height: 600)
          #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
          #endif
      }
    }
  }

  struct CrashReportView: View {
    var report: String
    var close: () -> Void
    @State private var copied = false

    var body: some View {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Astra crashed")
              .astraFont(size: 26, weight: .bold)
              .foregroundStyle(Astra.Color.ink)
            Text("Astra closed unexpectedly last time. Copy or send this report so it can be fixed.")
              .astraFont(size: 15)
              .foregroundStyle(Astra.Color.muted)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 12)
          Button(action: close) {
            Image(systemName: "xmark")
          }
          .buttonStyle(GlassIconButtonStyle(size: 36))
          .accessibilityLabel("Close")
        }

        ScrollView {
          Text(report)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Astra.Color.ink.opacity(0.85))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Astra.Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Astra.Color.hairline, lineWidth: 1))

        HStack(spacing: 12) {
          Button(action: copy) {
            Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PlayButtonStyle())

          ShareLink(item: report, subject: Text("Astra crash report")) {
            Label("Send", systemImage: "square.and.arrow.up")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(FallbackGlassButtonStyle())
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 28)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Astra.Color.bg.ignoresSafeArea())
    }

    private func copy() {
      #if os(iOS)
        UIPasteboard.general.string = report
      #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
      #endif
      copied = true
      Task { @MainActor in
        try? await Task.pause(2)
        copied = false
      }
    }
  }
#endif
