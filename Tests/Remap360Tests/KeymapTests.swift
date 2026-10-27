import Foundation
import Testing
@testable import Remap360Core

private let fixtureURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("Fixtures")

private func fixture(_ name: String) throws -> String {
    try String(contentsOf: fixtureURL.appendingPathComponent(name), encoding: .utf8)
}

@Test func parsesStockKeymap() throws {
    let doc = try KeymapDocument(text: fixture("adv360.keymap"), extraSources: [fixture("macros.dtsi")])
    #expect(doc.layers.count == 8)
    #expect(doc.activeLayers.map(\.displayName) == ["Base", "Kp", "Fn", "Mod"])
    for layer in doc.activeLayers { #expect(layer.bindings.count == 76) }
    #expect(doc.layers[0].bindings[0] == .kp("EQUAL"))
    #expect(doc.layers[0].bindings[6] == KeyBinding("tog", ["1"]))
    #expect(doc.layers[3].bindings[1] == KeyBinding("bt", ["BT_SEL", "0"]))
    #expect(doc.layers[4].isReserved)
    #expect(doc.customBehaviors.contains { $0.label == "hm" && $0.bindingCells == 2 })
    #expect(doc.customBehaviors.contains { $0.label == "Mac_Copy" && $0.isMacro })
}

@Test func roundTripIsStable() throws {
    let text = try fixture("adv360.keymap")
    let doc = try KeymapDocument(text: text)
    let rendered = doc.render()
    let reparsed = try KeymapDocument(text: rendered)
    #expect(reparsed.layers.map(\.bindings) == doc.layers.map(\.bindings))
    #expect(reparsed.layers.map(\.displayName) == doc.layers.map(\.displayName))
    #expect(reparsed.layers.map(\.status) == doc.layers.map(\.status))
    #expect(reparsed.render() == rendered)
    // Everything outside the keymap node is untouched.
    #expect(rendered.hasPrefix(String(text[..<doc.keymapBodyRange.lowerBound])))
    #expect(rendered.hasSuffix(String(text[doc.keymapBodyRange.upperBound...])))
}

@Test func editsSurviveRoundTrip() throws {
    var doc = try KeymapDocument(text: fixture("adv360.keymap"))
    doc.layers[0].bindings[15] = KeyBinding("mt", ["LCTRL", "LG(LS(Q))"])
    doc.layers[0].displayName = "Main \"layer\""
    let re = try KeymapDocument(text: doc.render())
    #expect(re.layers[0].bindings[15] == KeyBinding("mt", ["LCTRL", "LG(LS(Q))"]))
    #expect(re.layers[0].displayName == "Main 'layer'")
}

@Test func remapsLayerReferences() throws {
    var doc = try KeymapDocument(text: fixture("adv360.keymap"))
    // remove layer 1 (Kp): Fn and Mod move down by one
    doc.layers.remove(at: 1)
    doc.remapLayerRefs([0: 0, 1: nil, 2: 1, 3: 2])
    #expect(doc.layers[0].bindings[6] == .trans)
    #expect(doc.layers[0].bindings[7] == KeyBinding("mo", ["2"]))
    #expect(doc.layers[0].bindings[60] == KeyBinding("mo", ["1"]))
}

@Test func keyExpressions() {
    let e = KeyExpr(parsing: "LC(LG(LS(NUMBER_4)))")
    #expect(e.key == "NUMBER_4")
    #expect(e.mods == [.LC, .LG, .LS])
    #expect(e.text == "LC(LG(LS(NUMBER_4)))")
    #expect(e.label == "⌃⇧⌘4")
    #expect(KeyExpr(parsing: "A").label == "A")
}

@Test func parsesBindingsWithCommentsAndSpacedParens() {
    let b = BindingParser.parse("&kp A /* c */ &kp LS( B ) // tail\n &mt LSHFT C")
    #expect(b == [.kp("A"), .kp("LS(B)"), KeyBinding("mt", ["LSHFT", "C"])])
}

@Test func layoutIsSane() {
    #expect(Adv360Layout.keys.count == 76)
    #expect(Adv360Layout.rowLengths.reduce(0, +) == 76)
    #expect(Adv360Layout.keys.filter(\.isLeft).count == 38)
    #expect(Adv360Layout.neighbor(of: 15, dx: 1, dy: 0) == 16)
}

@Test func layoutFileRoundTrip() throws {
    let doc = try KeymapDocument(text: fixture("adv360.keymap"))
    let file = LayoutFile(keyboard: "Adv360 Pro", layers: doc.activeLayers, savedAt: Date(timeIntervalSince1970: 0))
    let data = try file.encoded()
    let back = try LayoutFile.decode(data)
    #expect(back == file)
    #expect(back.layers.map(\.name) == ["Base", "Kp", "Fn", "Mod"])
    #expect(back.bindings(ofLayer: 0) == doc.layers[0].bindings)
    #expect(String(decoding: data, as: UTF8.self).contains("\"&kp EQUAL\""))
    #expect(throws: LayoutFile.ReadError.self) { try LayoutFile.decode(Data("{}".utf8)) }
}
