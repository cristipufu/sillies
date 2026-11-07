import Foundation
import SilliesCore
import Testing

@Test func vaultHTMLExcerptKeepsReadableTextAndNeverReturnsEmbeddedScripts() {
  #expect(
    VaultHTMLExcerpt.text(
      "<blockquote><p>Hello &amp; good morning &#x1F31E;.</p><a href='https://example.com?a=1>0'>A source</a></blockquote><script>unwanted()</script>"
    ) == "Hello & good morning 🌞.\nA source")
  #expect(
    VaultHTMLExcerpt.text("&lt;script&gt;ordinary words&lt;/script&gt;")
      == "<script>ordinary words</script>")
}

@Test(arguments: [
  ("&mdash; &ndash; &hellip;", "— – …"),
  ("&ldquo;caf&eacute;&rdquo; &Aogon; &alpha;", "“café” Ą α"),
  ("&CounterClockwiseContourIntegral; &NotEqualTilde;", "∳ ≂\u{338}"),
  ("A&nbsp;B &apos; &quot;", "A\u{A0}B ' \""),
  ("&#8212; &#x2014; &#x1F31E;", "— — 🌞"),
  ("&amp;mdash; &amp;lt;", "&mdash; &lt;"),
  ("&unknown; &mdash &#xD800; &#x110000;", "&unknown; &mdash &#xD800; &#x110000;"),
])
func vaultHTMLReferencesDecodeStandardNamesWithoutReinterpretingLiteralText(
  html: String, expected: String
) {
  #expect(VaultHTMLExcerpt.text(html) == expected)
}

@Test func vaultHTMLReferencesPreserveLongMalformedInput() {
  let malformed = String(repeating: "&", count: 32_768) + "&notACharacterReference;"
  #expect(VaultHTMLExcerpt.text(malformed) == malformed)
}

@Test func vaultTextBlocksPreserveLongMultilingualDocuments() throws {
  let text = String(repeating: "An idea 🌳 e\u{301} — 記録 — ملاحظة\n", count: 2_000)
  var blocks: [String] = []
  VaultTextBlocks.enumerate(text) { ordinal, block in
    #expect(ordinal == blocks.count)
    #expect(block.unicodeScalars.count <= VaultTextBlocks.maximumScalars)
    blocks.append(block)
  }
  #expect(blocks.count > 10)
  #expect(blocks.joined() == text)
}

@Test(arguments: [
  ("https://youtu.be/abcdefghijk?t=42", VaultLink.Kind.video, "abcdefghijk"),
  ("https://www.youtube.com/watch?v=abcdefghijk&list=example", .video, "abcdefghijk"),
  ("https://youtube.com/shorts/abcdefghijk", .video, "abcdefghijk"),
  ("https://x.com/example/status/123456789", .post, "123456789"),
  ("https://twitter.com/example/status/123456789?s=20", .post, "123456789"),
])
func vaultLinkIdentifiesSupportedSources(url: String, kind: VaultLink.Kind, identity: String) throws
{
  let link = try VaultLink(url: #require(URL(string: url)))
  #expect(link.kind == kind)
  #expect(link.sourceID == identity)
  #expect(link.url.absoluteString == url)
}

@Test(arguments: ["https://youtube.com.example.org/watch?v=abcdefghijk", "https://x.com/home"])
func vaultLinksDoNotTreatOtherPagesAsSocialPosts(_ value: String) throws {
  #expect(try VaultLink(url: #require(URL(string: value))).kind == .website)
}

@Test(arguments: ["file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.org"])
func vaultLinksRejectNonWebResourcesAndCredentials(_ value: String) throws {
  let url = try #require(URL(string: value))
  #expect(throws: VaultLinkError.self) { try VaultLink(url: url) }
}

@Test func vaultRankingCombinesIndependentEvidenceWithoutDuplicatingResults() {
  struct Hit {
    let id: Int
    let text: String
  }
  let keyword = [
    Hit(id: 1, text: "exact"), Hit(id: 2, text: "both"), Hit(id: 2, text: "duplicate"),
  ]
  let semantic = [Hit(id: 3, text: "related"), Hit(id: 2, text: "semantic excerpt")]
  let merged = VaultRankFusion.merge([keyword, semantic], identifiedBy: \.id, limit: 3)
  #expect(merged.map(\.id) == [2, 1, 3])
  #expect(merged.first?.text == "both")
  #expect(VaultRankFusion.merge([keyword, []], identifiedBy: \.id, limit: 5).map(\.id) == [1, 2])
  #expect(VaultRankFusion.merge([keyword], identifiedBy: \.id, limit: 0).isEmpty)
  var query = VaultWorkspaceQuery(scope: .notes, text: "ideas")
  query.tag = "private"
  let candidates = VaultSearchRequest(workspace: query).rankingCandidates
  #expect(candidates.workspaceQuery == query)
}

@Test func vaultBlockBoundariesPreserveOrdinaryExtendedGraphemes() {
  let prefix = String(repeating: "a", count: VaultTextBlocks.maximumScalars - 1)
  let text = prefix + "👩🏽‍💻" + String(repeating: "b", count: 100)
  var blocks: [String] = []
  VaultTextBlocks.enumerate(text) { _, block in blocks.append(block) }
  #expect(blocks.count == 2)
  #expect(blocks[0] == prefix)
  #expect(blocks[1].hasPrefix("👩🏽‍💻"))
  #expect(blocks.joined() == text)
}
