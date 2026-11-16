import XCTest

@testable import AstraKit

final class LiveTVTests: XCTestCase {
  func testM3UReadsAttributesNamesAndGuide() {
    let text = """
      #EXTM3U url-tvg="http://guide.test/epg.xml.gz" x-tvg-url="http://other.test/x.xml"
      #EXTINF:-1 tvg-id="news.us" tvg-name="News HD" tvg-logo="http://img.test/news.png" tvg-chno="101" group-title="News, Weather",News HD
      http://stream.test/live/1.ts
      #EXTINF:-1 tvg-id="sports.us" group-title="Sports",Sports 1
      http://stream.test/live/2.m3u8

      #EXTINF:-1,No Attributes
      #EXTGRP:Movies
      http://stream.test/live/3.ts
      #EXTINF:-1 tvg-id="news.us" group-title="News, Weather",News SD
      http://stream.test/live/4.ts
      #EXTINF:-1 tvg-id="news.us" group-title="News, Weather",News SD again
      http://stream.test/live/4.ts
      """
    let result = M3UParser.parse(text)
    XCTAssertEqual(result.guide, URL(string: "http://guide.test/epg.xml.gz"))
    XCTAssertEqual(result.channels.map(\.name), ["News HD", "Sports 1", "No Attributes", "News SD"])
    let news = result.channels[0]
    XCTAssertEqual(news.id, "news.us")
    XCTAssertEqual(news.number, 101)
    XCTAssertEqual(news.group, "News, Weather")
    XCTAssertEqual(news.logo, URL(string: "http://img.test/news.png"))
    XCTAssertEqual(news.guideID, "news.us")
    XCTAssertEqual(result.channels[2].group, "Movies")
    // A second feed with the same tvg-id stays, under its own id.
    XCTAssertEqual(result.channels[3].id, "http://stream.test/live/4.ts")
    XCTAssertEqual(result.channels[3].guideID, "news.us")
  }

  func testXMLTVParsesTimesTitlesAndTrims() throws {
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <tv>
        <channel id="news.us"><display-name>News</display-name></channel>
        <programme start="20261116180000 +0000" stop="20261116183000 +0000" channel="news.us">
          <title lang="en">Evening News</title><desc>Tonight's headlines.</desc><icon src="http://img.test/p.jpg"/>
        </programme>
        <programme start="20261116183000 -0100" stop="20261116190000 -0100" channel="news.us"><title>Late &amp; Live</title></programme>
        <programme start="20261110180000 +0000" stop="20261110183000 +0000" channel="news.us"><title>Old</title></programme>
        <programme start="20261116180000 +0000" stop="20261116183000 +0000" channel="other"><title>Elsewhere</title></programme>
      </tv>
      """
    let now = try XCTUnwrap(XMLTVParser.date("20261116181500 +0000"))
    let programs = XMLTVParser.parse(
      Data(xml.utf8), from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(12 * 3600), channels: ["news.us"])
    XCTAssertEqual(programs.map(\.title), ["Evening News", "Late & Live"])
    XCTAssertEqual(programs[0].summary, "Tonight's headlines.")
    XCTAssertEqual(programs[0].image, URL(string: "http://img.test/p.jpg"))
    // 18:30 at -01:00 is 19:30 UTC.
    XCTAssertEqual(programs[1].start, XMLTVParser.date("20261116193000 +0000"))

    let guide = LiveGuide(programs)
    let channel = LiveChannel(id: "1", name: "News", stream: URL(string: "http://s.test/1.ts")!, guideID: "NEWS.us")
    XCTAssertEqual(guide.now(on: channel, at: now)?.title, "Evening News")
    XCTAssertEqual(guide.lineup(for: channel, at: now).map(\.title), ["Evening News", "Late & Live"])
    XCTAssertEqual(programs[0].remainingText(at: now), "15 min left")
    XCTAssertEqual(programs[0].progress(at: now), 0.5, accuracy: 0.001)
  }

  func testRemainingTextHours() {
    let start = Date(timeIntervalSince1970: 0)
    let p = LiveProgram(channel: "c", title: "Game", start: start, end: start.addingTimeInterval(3 * 3600))
    XCTAssertEqual(p.remainingText(at: start.addingTimeInterval(50 * 60)), "2h 10m left")
    XCTAssertEqual(p.remainingText(at: start.addingTimeInterval(3600)), "2h left")
  }

  func testXtreamServerNormalising() {
    XCTAssertEqual(XtreamClient.normalizedServer(" tv.example.com:8080/ "), "http://tv.example.com:8080")
    XCTAssertEqual(
      XtreamClient.normalizedServer("https://tv.example.com/player_api.php?username=a&password=b"), "https://tv.example.com")
    XCTAssertEqual(XtreamClient.format(from: []), "ts")
    XCTAssertEqual(XtreamClient.format(from: ["m3u8", "rtmp"]), "m3u8")
    XCTAssertEqual(XtreamClient.format(from: ["m3u8", "ts"]), "ts")
  }

  func testXtreamLoadsChannelsWithCategories() async throws {
    let transport = FakeTransport { request in
      let action = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "action" }?.value
      switch action {
      case nil:
        return (200, Data(#"{"user_info":{"auth":1,"status":"Active","allowed_output_formats":["m3u8","ts"]}}"#.utf8))
      case "get_live_categories":
        return (200, Data(#"[{"category_id":"7","category_name":"Sports"},{"category_id":8,"category_name":"News"}]"#.utf8))
      case "get_live_streams":
        return (
          200,
          Data(
            #"[{"num":1,"name":"Sports 1","stream_id":205,"stream_icon":"http://i.test/s.png","epg_channel_id":"sports.us","category_id":"7"},{"num":"2","name":"News","stream_id":"101","stream_icon":"","epg_channel_id":null,"category_id":8},{"name":"","stream_id":3}]"#
              .utf8)
        )
      default:
        return (404, Data())
      }
    }
    let loaded = try await LiveTVLoader.channels(
      for: .xtream(server: "tv.test:8080", username: "kp", password: "pw"), transport: transport)
    XCTAssertEqual(loaded.channels.map(\.name), ["Sports 1", "News"])
    XCTAssertEqual(loaded.channels[0].group, "Sports")
    XCTAssertEqual(loaded.channels[1].group, "News")
    XCTAssertEqual(loaded.channels[1].number, 2)
    XCTAssertNil(loaded.channels[1].logo)
    XCTAssertEqual(loaded.channels[0].stream.absoluteString, "http://tv.test:8080/live/kp/pw/205.ts")
    XCTAssertEqual(loaded.guide?.absoluteString, "http://tv.test:8080/xmltv.php?username=kp&password=pw")
    XCTAssertEqual(LiveCategories.groups(in: loaded.channels), ["Sports", "News"])
    XCTAssertEqual(LiveCategories.groups(in: loaded.channels, hidden: ["News"]), ["Sports"])
  }

  func testXtreamRejectedLogin() async {
    let transport = FakeTransport { _ in (200, Data(#"{"user_info":{"auth":0}}"#.utf8)) }
    do {
      _ = try await LiveTVLoader.channels(for: .xtream(server: "tv.test", username: "a", password: "b"), transport: transport)
      XCTFail("expected a rejection")
    } catch {
      XCTAssertEqual(error as? XtreamClient.Failure, .rejected)
    }
  }

  func testM3USourceUsesItsOwnGuideLink() async throws {
    let playlist = "#EXTM3U url-tvg=\"http://g.test/a.xml\"\n#EXTINF:-1,One\nhttp://s.test/1.ts\n"
    let transport = FakeTransport { _ in (200, Data(playlist.utf8)) }
    let own = try await LiveTVLoader.channels(
      for: .m3u(playlist: "http://p.test/list.m3u", guide: "http://mine.test/g.xml"), transport: transport)
    XCTAssertEqual(own.guide, URL(string: "http://mine.test/g.xml"))
    let header = try await LiveTVLoader.channels(for: .m3u(playlist: "http://p.test/list.m3u", guide: ""), transport: transport)
    XCTAssertEqual(header.guide, URL(string: "http://g.test/a.xml"))
  }

  #if canImport(Darwin)
    func testGunzip() throws {
      // gzip of "<tv></tv>" (made with Python's gzip module, mtime 0).
      let gz = Data(base64Encoded: "H4sIAAAAAAAC/7MpKbOz0QcSAHbSosAJAAAA")!
      XCTAssertEqual(String(decoding: LiveTVLoader.gunzipped(gz), as: UTF8.self), "<tv></tv>")
      XCTAssertEqual(LiveTVLoader.gunzipped(Data("plain".utf8)), Data("plain".utf8))
    }
  #endif

  func testSourceCodableRoundTrip() throws {
    let source = LiveTVSource.m3u(playlist: "http://p.test/x.m3u", guide: nil)
    let data = try JSONEncoder().encode(source)
    XCTAssertEqual(try JSONDecoder().decode(LiveTVSource.self, from: data), source)
    XCTAssertEqual(LiveTVSource.xtream(server: "tv.test:8080", username: "a", password: "b").displayHost, "tv.test")
  }

  func testLiveTabSitsBeforeLibraryAndIsNeverSaved() {
    XCTAssertEqual(TabLayout.withLive([.home, .search, .libraries], true), [.home, .search, .live, .libraries])
    XCTAssertEqual(TabLayout.withLive([.home, .search, .libraries], false), [.home, .search, .libraries])
    XCTAssertEqual(TabLayout.tabs(from: "home,live,search"), [.home, .search, .libraries])
    XCTAssertEqual(TabLayout.toggled(TabLayout.defaultTabs, .live, on: true), TabLayout.defaultTabs)
  }
}
