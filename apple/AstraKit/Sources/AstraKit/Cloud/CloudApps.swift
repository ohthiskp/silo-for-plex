import Foundation

/// Astra's registrations with the cloud services, read from Info.plist. Each
/// value comes from a build setting filled by a GitHub secret (see
/// project.yml); an empty or missing one means that service isn't offered.
public enum CloudApps {
  /// The Info.plist keys for each service: client id, then client secret
  /// (only Box and pCloud need one).
  public static func keys(_ kind: SourceKind) -> (id: String, secret: String?)? {
    switch kind {
    case .googleDrive: ("AstraGoogleClientID", nil)
    case .dropbox: ("AstraDropboxAppKey", nil)
    case .oneDrive: ("AstraOneDriveClientID", nil)
    case .box: ("AstraBoxClientID", "AstraBoxClientSecret")
    case .pCloud: ("AstraPCloudClientID", "AstraPCloudClientSecret")
    case .yandexDisk: ("AstraYandexClientID", nil)
    default: nil
    }
  }

  /// The app registration for `kind`, or nil when it isn't set up in this build.
  public static func app(_ kind: SourceKind, info: [String: Any]) -> OAuthApp? {
    guard let keys = keys(kind), var id = value(info[keys.id]) else { return nil }
    // Google's secret holds the id's first part (the URL scheme needs it alone).
    if kind == .googleDrive, !id.hasSuffix(".apps.googleusercontent.com") { id += ".apps.googleusercontent.com" }
    let secret = keys.secret.flatMap { value(info[$0]) }
    if keys.secret != nil, secret == nil { return nil }
    return OAuthApp(clientID: id, clientSecret: secret, redirectURI: redirectURI(kind, clientID: id))
  }

  /// Google's iOS clients only take their own reversed-id scheme; the others
  /// come back to "astra://oauth/<service>" (registered in each console).
  public static func redirectURI(_ kind: SourceKind, clientID: String) -> String {
    if kind == .googleDrive {
      let prefix = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
      return "com.googleusercontent.apps.\(prefix):/oauth2redirect"
    }
    return "astra://oauth/\(kind.rawValue)"
  }

  /// The URL schemes the app must list in CFBundleURLTypes.
  public static func callbackSchemes(info: [String: Any]) -> [String] {
    SourceKind.kinds(in: .cloud).compactMap { app($0, info: info)?.callbackScheme }
  }

  /// A real value, not empty and not an unfilled "$(SETTING)".
  static func value(_ any: Any?) -> String? {
    guard let text = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
      !text.hasPrefix("$(")
    else { return nil }
    return text
  }
}
