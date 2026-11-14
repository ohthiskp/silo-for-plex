#if os(iOS) || os(macOS)
  import AstraKit
  import SwiftUI
  #if os(iOS)
    import UIKit
  #else
    import AppKit
  #endif

  extension View {
    /// After a crash, the next launch opens the crash report (KP, 2026-11-12).
    /// Copy puts it on the clipboard; Send opens the share sheet.
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
            .frame(width: 520, height: 640)
          #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
          #endif
      }
    }
  }

  /// Calm and short (KP, 2026-11-13: "make it better"): the Astra mark, what
  /// happened in plain words, and the full report folded away under
  /// Technical Details. Copy and Send stay at the bottom.
  struct CrashReportView: View {
    var report: String
    var close: () -> Void
    @State private var copied = false
    @State private var showDetails = Demo.isOn && UserDefaults.standard.bool(forKey: "AstraDemoCrashDetails")

    private var summary: CrashSummary { CrashReportText.summary(of: report) }

    var body: some View {
      ScrollView {
        VStack(spacing: Astra.Spacing.l) {
          header
          summaryCard
          details
        }
        .padding(.horizontal, Astra.Spacing.l)
        .padding(.top, Astra.Spacing.xl)
        .padding(.bottom, Astra.Spacing.l)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
      }
      .scrollIndicators(.hidden)
      .safeAreaInset(edge: .bottom, spacing: 0) { actions }
      .background(Astra.Color.bg.ignoresSafeArea())
    }

    // MARK: - Parts

    private var header: some View {
      VStack(spacing: Astra.Spacing.m) {
        AstraLogo(lit: 0.7)
          .frame(width: 64, height: 64)
          .padding(Astra.Spacing.s)
          .astraGlass(in: Circle())
        Text("Astra quit unexpectedly")
          .astraFont(size: 24, weight: .bold)
          .foregroundStyle(Astra.Color.ink)
          .multilineTextAlignment(.center)
        Text("Sorry about that. Send this report and it can be fixed.")
          .astraFont(size: 15)
          .foregroundStyle(Astra.Color.muted)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.bottom, Astra.Spacing.xs)
    }

    private var summaryCard: some View {
      let s = summary
      return VStack(spacing: 0) {
        row("What happened", s.what, note: s.detail)
        if let place = s.place {
          divider
          row("Where", place, mono: true)
        }
        if let time = s.time {
          divider
          row("When", time.formatted(.relative(presentation: .named)).capitalizedFirst)
        }
        if let main = s.onMainThread {
          divider
          row("Thread", main ? "Main" : "Background")
        }
        if let version = s.version {
          divider
          row("Version", version)
        }
      }
      .background(RoundedRectangle(cornerRadius: Astra.Radius.card + 4).fill(Astra.Color.surface))
      .overlay(RoundedRectangle(cornerRadius: Astra.Radius.card + 4).stroke(Astra.Color.hairline, lineWidth: 1))
    }

    private var divider: some View {
      Rectangle().fill(Astra.Color.hairline).frame(height: 1).padding(.leading, Astra.Spacing.m)
    }

    private func row(_ label: String, _ value: String, note: String? = nil, mono: Bool = false) -> some View {
      HStack(alignment: .firstTextBaseline, spacing: Astra.Spacing.m) {
        Text(label)
          .astraFont(size: 14)
          .foregroundStyle(Astra.Color.muted)
        Spacer(minLength: Astra.Spacing.s)
        VStack(alignment: .trailing, spacing: 3) {
          Text(value)
            .font(mono ? .system(size: 13, weight: .medium, design: .monospaced) : .system(size: 14, weight: .semibold))
            .foregroundStyle(Astra.Color.ink)
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
          if let note, !note.isEmpty {
            Text(note)
              .astraFont(size: 12)
              .foregroundStyle(Astra.Color.muted)
              .multilineTextAlignment(.trailing)
              .lineLimit(3)
          }
        }
      }
      .padding(.horizontal, Astra.Spacing.m)
      .padding(.vertical, Astra.Spacing.m - 2)
    }

    private var details: some View {
      VStack(alignment: .leading, spacing: Astra.Spacing.s) {
        Button {
          withAnimation(Astra.Motion.base) { showDetails.toggle() }
        } label: {
          HStack(spacing: Astra.Spacing.xs) {
            Text("Technical Details")
              .astraFont(size: 14, weight: .semibold)
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .bold))
              .rotationEffect(.degrees(showDetails ? 90 : 0))
            Spacer()
          }
          .foregroundStyle(Astra.Color.muted)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if showDetails {
          // One crash line per row, scrolled sideways rather than wrapped.
          ScrollView(.horizontal, showsIndicators: false) {
            Text(report)
              .font(.system(size: 10.5, design: .monospaced))
              .foregroundStyle(Astra.Color.ink.opacity(0.8))
              .lineSpacing(2)
              .fixedSize()
              .textSelection(.enabled)
              .padding(Astra.Spacing.m)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: Astra.Radius.card).fill(Astra.Color.surface.opacity(0.6)))
          .transition(.opacity)
        }
      }
      .padding(.horizontal, Astra.Spacing.xs)
    }

    private var actions: some View {
      VStack(spacing: Astra.Spacing.s) {
        HStack(spacing: Astra.Spacing.s) {
          Button(action: copy) {
            Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc")
              .contentTransition(.symbolEffect(.replace))
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PlayButtonStyle())

          ShareLink(item: report, subject: Text("Astra crash report")) {
            Label("Send", systemImage: "square.and.arrow.up")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(FallbackGlassButtonStyle())
        }
        Button("Not Now", action: close)
          .buttonStyle(.plain)
          .astraFont(size: 15, weight: .medium)
          .foregroundStyle(Astra.Color.muted)
          .frame(height: 36)
      }
      .padding(.horizontal, Astra.Spacing.l)
      .padding(.top, Astra.Spacing.s)
      .padding(.bottom, Astra.Spacing.xs)
      .frame(maxWidth: 520)
      .frame(maxWidth: .infinity)
      .background {
        // Solid behind the buttons, fading out above them so the details scroll under cleanly.
        VStack(spacing: 0) {
          LinearGradient(colors: [Astra.Color.bg.opacity(0), Astra.Color.bg], startPoint: .top, endPoint: .bottom)
            .frame(height: Astra.Spacing.l)
          Astra.Color.bg
        }
        .padding(.top, -Astra.Spacing.l)
        .ignoresSafeArea()
      }
    }

    private func copy() {
      #if os(iOS)
        UIPasteboard.general.string = report
      #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
      #endif
      withAnimation(Astra.Motion.fast) { copied = true }
      Task { @MainActor in
        try? await Task.pause(2)
        withAnimation(Astra.Motion.fast) { copied = false }
      }
    }
  }

  extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
  }
#endif
