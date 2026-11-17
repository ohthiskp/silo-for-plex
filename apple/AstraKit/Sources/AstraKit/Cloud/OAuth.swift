import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A cloud account's sign-in: the access token, and the refresh token that
/// gets a new one. Saved as JSON in the Keychain, never in a file.
public struct OAuthToken: Codable, Sendable, Equatable {
  public var accessToken: String
  public var refreshToken: String?
  /// nil: the token doesn't expire (pCloud) or the service didn't say.
  public var expiresAt: Date?
  /// Service-specific values kept with the sign-in (pCloud's API host).
  public var extra: [String: String]

  public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil, extra: [String: String] = [:]) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
    self.extra = extra
  }

  /// True when the token runs out within `margin` seconds.
  public func expires(within margin: TimeInterval, now: Date) -> Bool {
    guard let expiresAt else { return false }
    return expiresAt.timeIntervalSince(now) < margin
  }

  public var json: String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
  public init?(json: String) {
    guard let value = try? JSONDecoder().decode(OAuthToken.self, from: Data(json.utf8)) else { return nil }
    self = value
  }
}

/// Astra's registration with a cloud service: the ids KP creates in each
/// service's developer console. They reach the app as Info.plist values from
/// GitHub secrets, never as literals in the code.
public struct OAuthApp: Sendable, Hashable {
  public var clientID: String
  /// Only the services that insist on one (Box, pCloud).
  public var clientSecret: String?
  /// Where the service sends the browser back: "astra://oauth/dropbox", or
  /// Google's "com.googleusercontent.apps.<id>:/oauth2redirect".
  public var redirectURI: String

  public init(clientID: String, clientSecret: String? = nil, redirectURI: String) {
    self.clientID = clientID
    self.clientSecret = clientSecret
    self.redirectURI = redirectURI
  }

  /// The scheme `ASWebAuthenticationSession` waits for.
  public var callbackScheme: String? { URL(string: redirectURI)?.scheme }
}

/// How one cloud service signs in.
public struct OAuthService: Sendable, Hashable {
  public var kind: SourceKind
  public var authorizeURL: URL
  public var tokenURL: URL
  /// The device-code endpoint, for Apple TV (sign in on a phone with a code).
  public var deviceURL: URL?
  public var scopes: [String]
  /// PKCE (RFC 7636): a public app proves it started the sign-in.
  public var usesPKCE: Bool
  public var extraAuthorize: [URLQueryItem]

  /// The endpoints and scopes of each cloud service. Read-only scopes only:
  /// Astra never changes or deletes anything in the cloud.
  public static func of(_ kind: SourceKind) -> OAuthService? {
    switch kind {
    case .googleDrive:
      // drive.readonly is a "restricted" scope: fine for KP's own account
      // (app in Testing), a Google security review before anyone else.
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenURL: URL(string: "https://oauth2.googleapis.com/token")!, deviceURL: nil,
        scopes: ["https://www.googleapis.com/auth/drive.readonly"], usesPKCE: true,
        extraAuthorize: [URLQueryItem(name: "access_type", value: "offline"), URLQueryItem(name: "prompt", value: "consent")])
    case .dropbox:
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!, deviceURL: nil,
        scopes: ["account_info.read", "files.metadata.read", "files.content.read"], usesPKCE: true,
        extraAuthorize: [URLQueryItem(name: "token_access_type", value: "offline")])
    case .oneDrive:
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        deviceURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/devicecode")!,
        scopes: ["Files.Read", "User.Read", "offline_access"], usesPKCE: true, extraAuthorize: [])
    case .box:
      // Box sets scopes in its console and needs the client secret.
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://account.box.com/api/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.box.com/oauth2/token")!, deviceURL: nil, scopes: [], usesPKCE: false,
        extraAuthorize: [])
    case .pCloud:
      // The token is exchanged at the account's own API host (US or EU),
      // which pCloud names in the redirect.
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://my.pcloud.com/oauth2/authorize")!,
        tokenURL: URL(string: "https://api.pcloud.com/oauth2_token")!, deviceURL: nil, scopes: [], usesPKCE: false,
        extraAuthorize: [])
    case .yandexDisk:
      OAuthService(
        kind: kind, authorizeURL: URL(string: "https://oauth.yandex.com/authorize")!,
        tokenURL: URL(string: "https://oauth.yandex.com/token")!,
        deviceURL: URL(string: "https://oauth.yandex.com/device/code")!, scopes: ["cloud_api:disk.read"], usesPKCE: true,
        extraAuthorize: [])
    default:
      nil
    }
  }
}

/// A sign-in started in the browser: open `url`, then hand the redirect to
/// `OAuthClient.exchange(callback:for:)` with this same request.
public struct OAuthRequest: Sendable, Hashable {
  public var kind: SourceKind
  public var url: URL
  public var state: String
  public var verifier: String
}

/// Sign-in on Apple TV: show `userCode` and `verificationURL`, then poll.
public struct DeviceCode: Sendable, Hashable, Codable {
  public var userCode: String
  public var verificationURL: URL
  /// The address with the code filled in, for a QR code.
  public var verificationURLComplete: URL?
  public var deviceCode: String
  /// Seconds between polls.
  public var interval: Int
  public var expiresAt: Date
}

public enum DevicePoll: Sendable, Equatable {
  /// Not approved yet: poll again after the interval.
  case waiting
  /// Polled too often: wait 5 seconds longer from now on.
  case slowDown
  case done(OAuthToken)
}

/// Talks to a service's sign-in endpoints.
public struct OAuthClient: Sendable {
  public let service: OAuthService
  public let app: OAuthApp
  let transport: HTTPTransport
  let now: @Sendable () -> Date

  public init(
    service: OAuthService, app: OAuthApp, transport: HTTPTransport = URLSessionTransport(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.service = service
    self.app = app
    self.transport = transport
    self.now = now
  }

  /// The page that asks the person to let Astra read their files.
  public func authorization() -> OAuthRequest {
    let state = Self.randomString(24)
    let verifier = Self.randomString(64)
    var components = URLComponents(url: service.authorizeURL, resolvingAgainstBaseURL: false)!
    var query = [
      URLQueryItem(name: "client_id", value: app.clientID),
      URLQueryItem(name: "redirect_uri", value: app.redirectURI),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "state", value: state),
    ]
    if !service.scopes.isEmpty { query.append(URLQueryItem(name: "scope", value: service.scopes.joined(separator: " "))) }
    if service.usesPKCE {
      query.append(URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)))
      query.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
    }
    components.queryItems = query + service.extraAuthorize
    return OAuthRequest(kind: service.kind, url: components.url!, state: state, verifier: verifier)
  }

  /// Trades the redirect's code for tokens.
  public func exchange(callback: URL, for request: OAuthRequest) async throws -> OAuthToken {
    let items = Self.parameters(of: callback)
    if let error = items["error"] {
      throw error == "access_denied" ? SourceError.share("Sign-in was cancelled.") : SourceError.share("Sign-in failed: \(items["error_description"] ?? error).")
    }
    guard items["state"] == request.state else { throw SourceError.share("Sign-in failed: the reply didn't match. Try again.") }
    guard let code = items["code"] else { throw SourceError.share("Sign-in failed: the service sent no code.") }
    var form = [
      "grant_type": "authorization_code", "code": code, "redirect_uri": app.redirectURI, "client_id": app.clientID,
    ]
    if service.usesPKCE { form["code_verifier"] = request.verifier }
    if let secret = app.clientSecret, !secret.isEmpty { form["client_secret"] = secret }
    var tokenURL = service.tokenURL
    var extra: [String: String] = [:]
    if service.kind == .pCloud {
      // pCloud: the EU and US accounts live on different API hosts.
      let host = items["hostname"].flatMap { ["api.pcloud.com", "eapi.pcloud.com"].contains($0) ? $0 : nil } ?? "api.pcloud.com"
      tokenURL = URL(string: "https://\(host)/oauth2_token")!
      extra["hostname"] = host
    }
    var token = try await post(tokenURL, form: form)
    token.extra.merge(extra) { $1 }
    return token
  }

  /// A new access token from the refresh token (some services hand out a
  /// new refresh token too, which then replaces the old one).
  public func refresh(_ token: OAuthToken) async throws -> OAuthToken {
    guard let refreshToken = token.refreshToken else { throw SourceError.wrongLogin }
    var form = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": app.clientID]
    if let secret = app.clientSecret, !secret.isEmpty { form["client_secret"] = secret }
    if service.kind == .oneDrive { form["scope"] = service.scopes.joined(separator: " ") }
    var fresh = try await post(service.tokenURL, form: form)
    if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
    fresh.extra = token.extra.merging(fresh.extra) { $1 }
    return fresh
  }

  // MARK: - Device code (Apple TV)

  public var supportsDeviceCode: Bool { service.deviceURL != nil }

  public func startDeviceCode() async throws -> DeviceCode {
    guard let url = service.deviceURL else { throw SourceError.share("\(service.kind.title) can't sign in with a code.") }
    var form = ["client_id": app.clientID]
    if !service.scopes.isEmpty { form["scope"] = service.scopes.joined(separator: " ") }
    let (data, status) = try await send(url, form: form)
    struct Body: Decodable {
      var device_code: String
      var user_code: String
      var verification_uri: String?
      var verification_url: String?
      var verification_uri_complete: String?
      var expires_in: Int?
      var interval: Int?
    }
    guard (200..<300).contains(status), let body = try? JSONDecoder().decode(Body.self, from: data),
      let verification = URL(string: body.verification_uri ?? body.verification_url ?? "")
    else { throw Self.error(data, status: status) }
    return DeviceCode(
      userCode: body.user_code, verificationURL: verification,
      verificationURLComplete: body.verification_uri_complete.flatMap(URL.init(string:)), deviceCode: body.device_code,
      interval: max(1, body.interval ?? 5), expiresAt: now().addingTimeInterval(TimeInterval(body.expires_in ?? 900)))
  }

  /// Asks once whether the code was approved.
  public func poll(_ code: DeviceCode) async throws -> DevicePoll {
    guard now() < code.expiresAt else { throw SourceError.share("The code expired. Start again for a new one.") }
    var form = [
      "grant_type": service.kind == .yandexDisk ? "device_code" : "urn:ietf:params:oauth:grant-type:device_code",
      "client_id": app.clientID,
    ]
    form[service.kind == .yandexDisk ? "code" : "device_code"] = code.deviceCode
    if let secret = app.clientSecret, !secret.isEmpty { form["client_secret"] = secret }
    let (data, status) = try await send(service.tokenURL, form: form)
    if (200..<300).contains(status) { return .done(try Self.token(data, now: now())) }
    let error = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    switch error {
    case "authorization_pending": return .waiting
    case "slow_down": return .slowDown
    case "access_denied", "authorization_declined": throw SourceError.share("Sign-in was declined.")
    case "expired_token", "bad_verification_code": throw SourceError.share("The code expired. Start again for a new one.")
    default: throw Self.error(data, status: status)
    }
  }

  // MARK: - Requests

  private func post(_ url: URL, form: [String: String]) async throws -> OAuthToken {
    let (data, status) = try await send(url, form: form)
    guard (200..<300).contains(status) else { throw Self.error(data, status: status) }
    return try Self.token(data, now: now())
  }

  private func send(_ url: URL, form: [String: String]) async throws -> (Data, Int) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = Data(Self.formEncode(form).utf8)
    let (data, response) = try await transport.send(request)
    return (data, response.statusCode)
  }

  struct ErrorBody: Decodable {
    var error: String?
    var error_description: String?
  }

  static func token(_ data: Data, now: Date) throws -> OAuthToken {
    struct Body: Decodable {
      var access_token: String?
      var refresh_token: String?
      var expires_in: Double?
      var result: Int?
      var error: String?
    }
    guard let body = try? JSONDecoder().decode(Body.self, from: data) else { throw PlexError.invalidResponse }
    // pCloud answers 200 with a non-zero "result" when it refuses.
    guard let access = body.access_token, !access.isEmpty, (body.result ?? 0) == 0 else {
      throw SourceError.share("Sign-in failed: \(body.error ?? "the service sent no token").")
    }
    return OAuthToken(
      accessToken: access, refreshToken: body.refresh_token,
      expiresAt: body.expires_in.map { now.addingTimeInterval($0) })
  }

  static func error(_ data: Data, status: Int) -> SourceError {
    let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
    switch body?.error {
    case "invalid_grant": return .wrongLogin
    case "invalid_client", "unauthorized_client":
      return .share("Astra's \(status == 401 ? "app id" : "registration") was refused by the service.")
    default: break
    }
    if let text = body?.error_description ?? body?.error { return .share("Sign-in failed: \(text)") }
    return status == 401 ? .wrongLogin : .http(status)
  }

  // MARK: - Helpers

  /// The query (and fragment) values of a redirect.
  static func parameters(of url: URL) -> [String: String] {
    var out: [String: String] = [:]
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    for item in components?.queryItems ?? [] { out[item.name] = item.value ?? "" }
    if let fragment = components?.fragment, var parsed = URLComponents(string: "x:/") {
      parsed.query = fragment
      for item in parsed.queryItems ?? [] where out[item.name] == nil { out[item.name] = item.value ?? "" }
    }
    return out
  }

  static func challenge(for verifier: String) -> String { SHA256.hash(Data(verifier.utf8)).base64URL }

  /// Letters, digits and "-._~" (the characters PKCE allows), from the system's secure random source.
  static func randomString(_ length: Int) -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    var generator = SystemRandomNumberGenerator()
    return String((0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] })
  }

  static func formEncode(_ form: [String: String]) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return form.sorted { $0.key < $1.key }.map { key, value in
      "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
    }.joined(separator: "&")
  }
}

/// Hands out a fresh access token for one account, refreshing it once when
/// it runs out (one refresh at a time, however many requests are waiting)
/// and saving the new sign-in through `onRefresh`.
public actor OAuthSession {
  public private(set) var token: OAuthToken
  let client: OAuthClient?
  let onRefresh: @Sendable (OAuthToken) -> Void
  private var refreshing: Task<OAuthToken, Error>?

  /// `client` nil: the token can't be refreshed (a service without expiry).
  public init(token: OAuthToken, client: OAuthClient?, onRefresh: @escaping @Sendable (OAuthToken) -> Void = { _ in }) {
    self.token = token
    self.client = client
    self.onRefresh = onRefresh
  }

  /// A token good for at least another minute.
  public func accessToken() async throws -> String {
    if let client, token.expires(within: 60, now: client.now()) { return try await refresh().accessToken }
    return token.accessToken
  }

  /// After a 401: the token was revoked or expired early. `rejected` is the
  /// token that failed, so a refresh another request already did isn't repeated.
  public func renew(after rejected: String) async throws -> String {
    if token.accessToken != rejected { return token.accessToken }
    return try await refresh().accessToken
  }

  public var extra: [String: String] { token.extra }

  private func refresh() async throws -> OAuthToken {
    if let refreshing { return try await refreshing.value }
    guard let client, token.refreshToken != nil else { throw SourceError.wrongLogin }
    let current = token
    let task = Task { try await client.refresh(current) }
    refreshing = task
    defer { refreshing = nil }
    let fresh = try await task.value
    token = fresh
    onRefresh(fresh)
    return fresh
  }
}
