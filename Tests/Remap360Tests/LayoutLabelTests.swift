import Testing
@testable import Remap360Core

// Reads layouts that ship with macOS without selecting them, so the user's keyboard is untouched.
@MainActor private func layout(_ id: String) throws -> KeyboardLayoutLabels.Result {
    try #require(KeyboardLayoutLabels.layout(id: "com.apple.keylayout.\(id)"))
}

@MainActor @Test func usLayoutNeedsNoOverrides() throws {
    let us = try layout("US")
    for code in ["A", "Q", "SEMI", "LBKT", "MINUS", "N2"] { #expect(us.labels[code] == nil, "\(code)") }
    #expect(us.shifted["N2"] == "@")
}

@MainActor @Test func germanSwapsYZAndHasUmlauts() throws {
    let de = try layout("German")
    #expect(de.labels["Y"] == "Z")
    #expect(de.labels["Z"] == "Y")
    #expect(de.labels["SEMI"] == "Ö")
    #expect(de.labels["SQT"] == "Ä")
    #expect(de.labels["LBKT"] == "Ü")
    #expect(de.labels["MINUS"] == "ß")
}

@MainActor @Test func frenchIsAzerty() throws {
    let fr = try layout("French")
    #expect(fr.labels["Q"] == "A")
    #expect(fr.labels["A"] == "Q")
    #expect(fr.labels["W"] == "Z")
    #expect(fr.labels["SEMI"] == "M")
}

@MainActor @Test func nordicLayouts() throws {
    let sv = try layout("Swedish-Pro")
    #expect([sv.labels["SEMI"], sv.labels["SQT"], sv.labels["LBKT"]] == ["Ö", "Ä", "Å"])
    let no = try layout("Norwegian")
    #expect([no.labels["SEMI"], no.labels["SQT"], no.labels["LBKT"]] == ["Ø", "Æ", "Å"])
    let da = try layout("Danish")
    #expect([da.labels["SEMI"], da.labels["SQT"], da.labels["LBKT"]] == ["Æ", "Ø", "Å"])
    let isl = try layout("Icelandic")
    #expect([isl.labels["SEMI"], isl.labels["LBKT"], isl.labels["MINUS"], isl.labels["FSLH"]] == ["Æ", "Ð", "Ö", "Þ"])
    #expect(isl.option["MINUS"] == "\\")
}

@MainActor @Test func britishPoundSign() throws {
    let gb = try layout("British")
    #expect(gb.shifted["N3"] == "£")
    #expect(gb.labels["A"] == nil)
}
