import XCTest

@testable import AstraKit

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

private func json(_ text: String) -> Data { Data(text.utf8) }

private func form(_ request: URLRequest) -> [String: String] {
  var out: [String: String] = [:]
  let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
  for pair in body.split(separator: "&") {
    let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
    out[parts[0]] = parts.count > 1 ? parts[1] : ""
  }
  return out
}

private func query(_ request: URLRequest) -> [String: String] {
  var out: [String: String] = [:]
  for item in URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] { out[item.name] = item.value }
  return out
}

private let googleApp = OAuthApp(
  clientID: "123-abc.apps.googleusercontent.com", redirectURI: "com.googleusercontent.apps.123-abc:/oauth2redirect")

final class OAuthTests: XCTestCase {
  func testSHA256AndPKCEMatchTheStandardsExamples() {
    XCTAssertEqual(
      SHA256.hash(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    XCTAssertEqual(
      SHA256.hash(Data()).map { String(format: "%02x", $0) }.joined(),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    // RFC 7636, appendix B.
    XCTAssertEqual(
      OAuthClient.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    // Over one 64-byte block.
    XCTAssertEqual(
      SHA256.hash(Data(String(repeating: "a", count: 200).utf8)).map { String(format: "%02x", $0) }.joined(),
      "c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5")
  }

  func testAuthorizationPageAsksForReadOnlyDriveWithPKCE() throws {
    let client = OAuthClient(service: OAuthService.of(.googleDrive)!, app: googleApp)
    let request = client.authorization()
    let items = query(URLRequest(url: request.url))
    XCTAssertEqual(request.url.host, "accounts.google.com")
    XCTAssertEqual(items["client_id"], googleApp.clientID)
    XCTAssertEqual(items["redirect_uri"], googleApp.redirectURI)
    XCTAssertEqual(items["scope"], "https://www.googleapis.com/auth/drive.readonly")
    XCTAssertEqual(items["state"], request.state)
    XCTAssertEqual(items["code_challenge"], OAuthClient.challenge(for: request.verifier))
    XCTAssertEqual(items["code_challenge_method"], "S256")
    XCTAssertEqual(items["access_type"], "offline")
    XCTAssertEqual(request.verifier.count, 64)
  }

  func testExchangeChecksStateAndSendsTheVerifier() async throws {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let transport = FakeTransport { _ in (200, json(#"{"access_token":"A1","refresh_token":"R1","expires_in":3600}"#)) }
    let client = OAuthClient(service: OAuthService.of(.googleDrive)!, app: googleApp, transport: transport, now: { now })
    let request = client.authorization()

    let wrong = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=C&state=other")!
    do {
      _ = try await client.exchange(callback: wrong, for: request)
      XCTFail("A reply with another state must be refused")
    } catch {}
    XCTAssertTrue(transport.requests.isEmpty)

    let callback = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=C&state=\(request.state)")!
    let token = try await client.exchange(callback: callback, for: request)
    XCTAssertEqual(token, OAuthToken(accessToken: "A1", refreshToken: "R1", expiresAt: now.addingTimeInterval(3600)))
    let sent = form(try XCTUnwrap(transport.requests.first))
    XCTAssertEqual(sent["grant_type"], "authorization_code")
    XCTAssertEqual(sent["code"], "C")
    XCTAssertEqual(sent["code_verifier"], request.verifier)
    XCTAssertNil(sent["client_secret"])
  }

  func testCancelledSignInSaysSo() async {
    let client = OAuthClient(service: OAuthService.of(.dropbox)!, app: OAuthApp(clientID: "k", redirectURI: "astra://oauth/dropbox"))
    let request = client.authorization()
    do {
      _ = try await client.exchange(callback: URL(string: "astra://oauth/dropbox?error=access_denied&state=\(request.state)")!, for: request)
      XCTFail()
    } catch {
      XCTAssertEqual(error as? SourceError, .share("Sign-in was cancelled."))
    }
  }

  func testPCloudExchangesAtTheAccountsOwnHost() async throws {
    let transport = FakeTransport { _ in (200, json(#"{"result":0,"access_token":"P1","userid":5}"#)) }
    let app = OAuthApp(clientID: "id", clientSecret: "sec", redirectURI: "astra://oauth/pCloud")
    let client = OAuthClient(service: OAuthService.of(.pCloud)!, app: app, transport: transport)
    let request = client.authorization()
    let token = try await client.exchange(
      callback: URL(string: "astra://oauth/pCloud?code=C&state=\(request.state)&hostname=eapi.pcloud.com&locationid=2")!, for: request)
    XCTAssertEqual(transport.requests.first?.url?.host, "eapi.pcloud.com")
    XCTAssertEqual(form(transport.requests[0])["client_secret"], "sec")
    XCTAssertEqual(token.accessToken, "P1")
    XCTAssertNil(token.expiresAt)
    XCTAssertEqual(token.extra["hostname"], "eapi.pcloud.com")

    // A host pCloud didn't name is never trusted.
    let other = client.authorization()
    _ = try await client.exchange(
      callback: URL(string: "astra://oauth/pCloud?code=C&state=\(other.state)&hostname=evil.example.com")!, for: other)
    XCTAssertEqual(transport.requests.last?.url?.host, "api.pcloud.com")
  }

  func testExpiredTokenIsRefreshedOnceForManyRequestsAndSaved() async throws {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let refreshes = Counter()
    let transport = FakeTransport { request in
      _ = refreshes.increment()
      try await Task.pause(0.05)
      XCTAssertEqual(form(request)["grant_type"], "refresh_token")
      return (200, json(#"{"access_token":"NEW","expires_in":3600}"#))
    }
    let client = OAuthClient(service: OAuthService.of(.googleDrive)!, app: googleApp, transport: transport, now: { now })
    let saved = Box<OAuthToken?>(nil)
    let session = OAuthSession(
      token: OAuthToken(accessToken: "OLD", refreshToken: "R", expiresAt: now.addingTimeInterval(10)), client: client
    ) { saved.value = $0 }
    async let a = session.accessToken()
    async let b = session.accessToken()
    async let c = session.accessToken()
    let tokens = try await [a, b, c]
    XCTAssertEqual(tokens, ["NEW", "NEW", "NEW"])
    XCTAssertEqual(refreshes.increment(), 2, "one refresh for three requests")
    // The old refresh token is kept when the service doesn't send a new one.
    XCTAssertEqual(saved.value?.refreshToken, "R")
    XCTAssertEqual(saved.value?.accessToken, "NEW")
  }

  func testA401RenewsTheTokenAndTriesAgain() async throws {
    let now = Date(timeIntervalSince1970: 3_000_000)
    let transport = FakeTransport { request in
      if request.url?.host == "oauth2.googleapis.com" { return (200, json(#"{"access_token":"T2","expires_in":3600}"#)) }
      return request.value(forHTTPHeaderField: "Authorization") == "Bearer T2" ? (200, json("{}")) : (401, Data())
    }
    let client = OAuthClient(service: OAuthService.of(.googleDrive)!, app: googleApp, transport: transport, now: { now })
    let session = OAuthSession(token: OAuthToken(accessToken: "T1", refreshToken: "R", expiresAt: now.addingTimeInterval(3000)), client: client)
    let http = CloudHTTP(auth: .oauth(session, scheme: "Bearer"), transport: transport)
    let (_, response) = try await http.send(URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/about")!))
    XCTAssertEqual(response.statusCode, 200)
    XCTAssertEqual(transport.requests.count, 3)
  }

  func testDeviceCodeWaitsSlowsDownThenSignsIn() async throws {
    let now = Date(timeIntervalSince1970: 4_000_000)
    let step = Counter()
    let transport = FakeTransport { request in
      if request.url?.path.hasSuffix("devicecode") == true {
        return (200, json(#"{"device_code":"D","user_code":"ABCD-1234","verification_uri":"https://microsoft.com/devicelogin","expires_in":900,"interval":5}"#))
      }
      XCTAssertEqual(form(request)["device_code"], "D")
      switch step.increment() {
      case 1: return (400, json(#"{"error":"authorization_pending"}"#))
      case 2: return (400, json(#"{"error":"slow_down"}"#))
      default: return (200, json(#"{"access_token":"A","refresh_token":"R","expires_in":3600}"#))
      }
    }
    let client = OAuthClient(
      service: OAuthService.of(.oneDrive)!, app: OAuthApp(clientID: "ms", redirectURI: "astra://oauth/oneDrive"),
      transport: transport, now: { now })
    let code = try await client.startDeviceCode()
    XCTAssertEqual(code.userCode, "ABCD-1234")
    XCTAssertEqual(code.interval, 5)
    let first = try await client.poll(code)
    XCTAssertEqual(first, .waiting)
    let second = try await client.poll(code)
    XCTAssertEqual(second, .slowDown)
    guard case .done(let token) = try await client.poll(code) else { return XCTFail() }
    XCTAssertEqual(token.refreshToken, "R")
    XCTAssertNil(OAuthService.of(.dropbox)?.deviceURL, "Dropbox has no device sign-in")
  }

  func testCloudAppsComeFromInfoPlistOnlyWhenFilledIn() {
    XCTAssertNil(CloudApps.app(.dropbox, info: [:]))
    XCTAssertNil(CloudApps.app(.dropbox, info: ["AstraDropboxAppKey": "$(ASTRA_DROPBOX_APP_KEY)"]))
    XCTAssertEqual(CloudApps.app(.dropbox, info: ["AstraDropboxAppKey": "key"])?.redirectURI, "astra://oauth/dropbox")
    // Box needs its secret too.
    XCTAssertNil(CloudApps.app(.box, info: ["AstraBoxClientID": "id"]))
    XCTAssertEqual(CloudApps.app(.box, info: ["AstraBoxClientID": "id", "AstraBoxClientSecret": "s"])?.clientSecret, "s")
    let google = CloudApps.app(.googleDrive, info: ["AstraGoogleClientID": "123-abc"])
    XCTAssertEqual(google?.clientID, "123-abc.apps.googleusercontent.com")
    XCTAssertEqual(google?.redirectURI, "com.googleusercontent.apps.123-abc:/oauth2redirect")
    XCTAssertEqual(google?.callbackScheme, "com.googleusercontent.apps.123-abc")
    XCTAssertEqual(OAuthToken(json: OAuthToken(accessToken: "a", extra: ["hostname": "h"]).json)?.extra["hostname"], "h")
  }

  func testKindsAreGroupedLikeInfuse() {
    XCTAssertEqual(SourceKind.kinds(in: .mediaServer), [.plex, .jellyfin, .emby])
    XCTAssertEqual(SourceKind.kinds(in: .networkShare), [.smb, .webdav])
    XCTAssertEqual(SourceKind.kinds(in: .cloud), [.googleDrive, .dropbox, .oneDrive, .box, .pCloud, .yandexDisk])
    XCTAssertTrue(SourceConfig(kind: .plex, name: "Omega", address: "").sections.isEmpty)
    let drive = SourceConfig(
      kind: .dropbox, name: "Dropbox", address: "kp@example.com",
      folders: [SourceFolder(id: "f1", share: "", path: "Movies", content: .movies, title: "Movies")])
    XCTAssertEqual(drive.sections.map(\.type), ["movie"])
  }
}

/// A mutable box for values a test's closures fill in.
final class Box<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}

final class CloudDriveTests: XCTestCase {
  func session(_ token: String = "T") -> OAuthSession {
    OAuthSession(token: OAuthToken(accessToken: token), client: nil)
  }

  func testGoogleDriveFindsFilesByIdUnderTheirPaths() async throws {
    let transport = FakeTransport { request in
      let q = query(request)["q"] ?? ""
      if request.url?.path == "/drive/v3/files", q.contains("'root' in parents") {
        return (200, json(#"""
          {"files":[
            {"id":"m1","name":"Movies","mimeType":"application/vnd.google-apps.folder"},
            {"id":"d1","name":"Notes","mimeType":"application/vnd.google-apps.document"},
            {"id":"s1","name":"Shows","mimeType":"application/vnd.google-apps.shortcut","shortcutDetails":{"targetId":"t9","targetMimeType":"application/vnd.google-apps.folder"}}
          ]}
          """#))
      }
      if request.url?.path == "/drive/v3/files", q.contains("'m1' in parents") {
        return (200, json(#"{"files":[{"id":"f1","name":"Dune (2021).mkv","mimeType":"video/x-matroska","size":"5000","modifiedTime":"2026-11-17T20:21:23.000Z"}]}"#))
      }
      if request.url?.path == "/drive/v3/files/f1" {
        XCTAssertEqual(query(request)["alt"], "media")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=100-199")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer T")
        return (206, Data(repeating: 7, count: 100))
      }
      return (404, Data())
    }
    let drive = GoogleDrive(session: session(), transport: transport)
    let share = try await drive.share("")
    // Reading a path never listed walks down to it.
    let data = try await share.read("Movies/Dune (2021).mkv", offset: 100, length: 100)
    XCTAssertEqual(data.count, 100)
    let size = try await share.size(of: "Movies/Dune (2021).mkv")
    XCTAssertEqual(size, 5000)
    let top = try await share.list("")
    XCTAssertEqual(top.map(\.name), ["Movies", "Shows"], "Docs are skipped; a shortcut is its target")
    XCTAssertEqual(top.map(\.isDirectory), [true, true])
    let movies = try await share.list("Movies")
    XCTAssertEqual(movies.first?.path, "Movies/Dune (2021).mkv")
    XCTAssertNotNil(movies.first?.modified)
    XCTAssertEqual(share.preferredChunkSize, 8 << 20)
  }

  func testDropboxListsEveryPageAndEscapesItsHeader() async throws {
    let transport = FakeTransport { request in
      switch request.url?.path {
      case "/2/files/list_folder":
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["path"] as? String, "/Movies")
        return (200, json(#"{"entries":[{".tag":"file","name":"A.mkv","size":10}],"cursor":"c1","has_more":true}"#))
      case "/2/files/list_folder/continue":
        return (200, json(#"{"entries":[{".tag":"folder","name":"B"},{".tag":"deleted","name":"C"}],"cursor":"c2","has_more":false}"#))
      case "/2/files/download":
        XCTAssertEqual(request.value(forHTTPHeaderField: "Dropbox-API-Arg"), #"{"path":"\/Movies\/Am\u00e9lie.mkv"}"#)
        return (206, Data(count: 4))
      default: return (404, Data())
      }
    }
    let dropbox = Dropbox(session: session(), transport: transport)
    let entries = try await dropbox.list("Movies")
    XCTAssertEqual(entries.map(\.path), ["Movies/A.mkv", "Movies/B"])
    XCTAssertEqual(entries.map(\.isDirectory), [false, true])
    let data = try await dropbox.read("Movies/Amélie.mkv", offset: 0, length: 4)
    XCTAssertEqual(data.count, 4)
  }

  func testOneDriveReadsThroughTheDownloadLinkWithoutTheToken() async throws {
    let links = Counter()
    let transport = FakeTransport { request in
      if request.url?.host == "dl.example.com" {
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        return (206, Data(count: 10))
      }
      if request.url?.absoluteString.contains("/children") == true {
        if query(request)["$skiptoken"] == nil {
          return (200, json(#"{"value":[{"name":"Shows","folder":{"childCount":2}}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/drive/root/children?$skiptoken=2"}"#))
        }
        return (200, json(#"{"value":[{"name":"x.mp4","size":99,"file":{}}]}"#))
      }
      _ = links.increment()
      XCTAssertEqual(request.url?.absoluteString, "https://graph.microsoft.com/v1.0/me/drive/root:/Movies/Le%20Film.mkv:")
      return (200, json(#"{"name":"Le Film.mkv","size":1234,"@microsoft.graph.downloadUrl":"https://dl.example.com/abc"}"#))
    }
    let drive = OneDrive(session: session(), transport: transport)
    let entries = try await drive.list("")
    XCTAssertEqual(entries.map(\.name), ["Shows", "x.mp4"])
    _ = try await drive.read("Movies/Le Film.mkv", offset: 0, length: 10)
    _ = try await drive.read("Movies/Le Film.mkv", offset: 10, length: 10)
    let size = try await drive.size(of: "Movies/Le Film.mkv")
    XCTAssertEqual(size, 1234)
    XCTAssertEqual(links.increment(), 2, "one link for every read of the file")
  }

  func testBoxPagesWithMarkersAndReadsById() async throws {
    let transport = FakeTransport { request in
      let path = request.url?.path ?? ""
      if path == "/2.0/folders/0/items" {
        if query(request)["marker"] == nil {
          return (200, json(#"{"entries":[{"id":"11","type":"folder","name":"Movies"}],"next_marker":"m2"}"#))
        }
        return (200, json(#"{"entries":[{"id":"12","type":"web_link","name":"Link"}],"next_marker":""}"#))
      }
      if path == "/2.0/folders/11/items" {
        return (200, json(#"{"entries":[{"id":"21","type":"file","name":"Heat.mkv","size":300}]}"#))
      }
      if path == "/2.0/files/21/content" { return (206, Data(count: 3)) }
      return (404, Data())
    }
    let box = BoxDrive(session: session(), transport: transport)
    let top = try await box.list("")
    XCTAssertEqual(top.map(\.name), ["Movies"])
    let data = try await box.read("Movies/Heat.mkv", offset: 0, length: 3)
    XCTAssertEqual(data.count, 3)
    let size = try await box.size(of: "Movies/Heat.mkv")
    XCTAssertEqual(size, 300)
  }

  func testPCloudErrorsAndListing() async throws {
    let transport = FakeTransport { request in
      XCTAssertEqual(request.url?.host, "eapi.pcloud.com")
      switch request.url?.path {
      case "/listfolder":
        if query(request)["path"] == "/Nope" { return (200, json(#"{"result":2005,"error":"Directory does not exist."}"#)) }
        return (200, json(#"{"result":0,"metadata":{"name":"/","contents":[{"name":"Movies","isfolder":true},{"name":"a.mkv","isfolder":false,"size":5,"modified":"Thu, 21 Mar 2013 18:31:16 +0000"}]}}"#))
      case "/userinfo": return (200, json(#"{"result":2000,"error":"Log in failed."}"#))
      default: return (404, Data())
      }
    }
    let cloud = PCloud(session: session(), host: "eapi.pcloud.com", transport: transport)
    let entries = try await cloud.list("")
    XCTAssertEqual(entries.map(\.name), ["Movies", "a.mkv"])
    XCTAssertNotNil(entries[1].modified)
    do {
      _ = try await cloud.list("Nope")
      XCTFail()
    } catch { XCTAssertEqual(error as? SourceError, .notFound) }
    do {
      _ = try await cloud.account()
      XCTFail()
    } catch { XCTAssertEqual(error as? SourceError, .wrongLogin) }
  }

  func testYandexPagesByTotalWithItsOwnAuthScheme() async throws {
    let transport = FakeTransport { request in
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "OAuth T")
      XCTAssertEqual(query(request)["path"], "disk:/Movies")
      let offset = Int(query(request)["offset"] ?? "0") ?? 0
      let item = offset == 0 ? #"{"name":"A","type":"dir"}"# : #"{"name":"b.mkv","type":"file","size":9}"#
      return (200, json(#"{"_embedded":{"items":[\#(item)],"total":2}}"#))
    }
    let disk = YandexDisk(session: session(), transport: transport)
    let entries = try await disk.list("Movies")
    XCTAssertEqual(entries.map(\.path), ["Movies/A", "Movies/b.mkv"])
    XCTAssertEqual(transport.requests.count, 2)
  }

  func testWebDAVListsAFolderWithoutItself() async throws {
    let transport = FakeTransport { request in
      XCTAssertEqual(request.httpMethod, "PROPFIND")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Depth"), "1")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic " + Data("kp:pw".utf8).base64EncodedString())
      XCTAssertEqual(request.url?.absoluteString, "https://cloud.example.com/dav/kp/My%20Movies/")
      return (207, json("""
        <?xml version="1.0"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/kp/My%20Movies/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/kp/My%20Movies/Dune%20(2021)/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
          <d:response><d:href>https://cloud.example.com/dav/kp/My%20Movies/Heat.mkv</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>4096</d:getcontentlength><d:getlastmodified>Thu, 21 Mar 2013 18:31:16 GMT</d:getlastmodified></d:prop></d:propstat></d:response>
        </d:multistatus>
        """))
    }
    let share = try WebDAVShare(address: "cloud.example.com/dav/kp", username: "kp", password: "pw", transport: transport)
    let entries = try await share.list("My Movies")
    XCTAssertEqual(entries.map(\.path), ["My Movies/Dune (2021)", "My Movies/Heat.mkv"])
    XCTAssertEqual(entries.map(\.isDirectory), [true, false])
    XCTAssertEqual(entries[1].size, 4096)
    XCTAssertNotNil(entries[1].modified)
    XCTAssertEqual(WebDAVShare.normalizedURL("webdav://nas.local:5005")?.absoluteString, "http://nas.local:5005/")
  }

  func testRangeFallsBackWhenTheServerSendsTheWholeFile() async throws {
    let whole = Data((0..<50).map { UInt8($0) })
    let transport = FakeTransport { _ in (200, whole) }
    let http = CloudHTTP(auth: .none, transport: transport)
    let part = try await http.range(URLRequest(url: URL(string: "https://x.test/f")!), offset: 10, length: 5)
    XCTAssertEqual([UInt8](part), [10, 11, 12, 13, 14])
    let past = try await http.range(URLRequest(url: URL(string: "https://x.test/f")!), offset: 60, length: 5)
    XCTAssertTrue(past.isEmpty)
  }

  func testACloudFolderIsScannedLikeAShare() async throws {
    // The same scanner and catalog as SMB: a Dropbox folder of movies becomes a library.
    let transport = FakeTransport { request in
      let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
      if body?["path"] as? String == "/Movies" {
        return (200, json(#"{"entries":[{".tag":"file","name":"Heat (1995).mkv","size":900000000}],"has_more":false}"#))
      }
      return (404, Data())
    }
    let dropbox = Dropbox(session: session(), transport: transport)
    let folder = SourceFolder(id: "f1", share: "", path: "Movies", content: .movies, title: "Movies")
    let index = try await ShareScanner.scan(folder, share: dropbox, into: ShareIndex(), matcher: nil)
    XCTAssertEqual(index.files.map(\.name.title), ["Heat"])
    XCTAssertEqual(index.files.first?.name.year, 1995)
  }
}
