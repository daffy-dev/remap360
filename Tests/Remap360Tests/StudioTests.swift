import Foundation
import Testing
@testable import Remap360Core

@Test func framingEscapesAndDecodesAcrossChunks() {
    let payload = Data([0x01, 0xAB, 0x02, 0xAC, 0xAD, 0x03])
    let framed = StudioFraming.encode(payload)
    #expect(framed == Data([0xAB, 0x01, 0xAC, 0xAB, 0x02, 0xAC, 0xAC, 0xAC, 0xAD, 0x03, 0xAD]))
    var decoder = StudioFraming.Decoder()
    let mid = framed.count / 2
    #expect(decoder.feed(framed.prefix(mid)).isEmpty)
    #expect(decoder.feed(framed.suffix(from: mid)) == [payload])
}

@Test func encodesSetBindingRequest() throws {
    let data = StudioRequest.setBinding(layerID: 2, position: 15, binding: StudioBinding(behaviorID: -1, param1: 0x070004, param2: 0))
        .encode(id: 7)
    let msg = try ProtoMessage(data)
    #expect(msg.uint(1) == 7)
    let req = try #require(try msg.message(5)?.message(2))
    #expect(req.uint(1) == 2)
    #expect(req.int(2) == 15)
    let binding = try #require(try req.message(3))
    #expect(binding.sint(1) == -1)
    #expect(binding.uint(2) == 0x070004)
}

@Test func decodesKeymapResponse() throws {
    // Build what the keyboard would send: RequestResponse{ id: 3, keymap{ get_keymap{ layers... } } }
    var w = ProtoWriter()
    w.message(1) { rr in
        rr.uint(1, 3)
        rr.message(5) { km in
            km.message(1) { keymap in
                keymap.message(1) { layer in
                    layer.uint(1, 0)
                    layer.string(2, "Base")
                    layer.message(3) { $0.sint(1, 4); $0.uint(2, 0x070004) }
                    layer.message(3) { $0.sint(1, 9); $0.uint(2, 1) }
                }
                keymap.message(1) { layer in
                    layer.uint(1, 1)
                    layer.string(2, "Fn")
                }
                keymap.uint(2, 4)
                keymap.uint(3, 20)
            }
        }
    }
    guard case .response(let id, .keymap(let keymap)) = try StudioDecoder.decode(w.data) else {
        Issue.record("expected keymap")
        return
    }
    #expect(id == 3)
    #expect(keymap.layers.map(\.name) == ["Base", "Fn"])
    #expect(keymap.layers[0].bindings[1] == StudioBinding(behaviorID: 9, param1: 1))
    #expect(keymap.availableLayers == 4)
}

@Test func decodesNotificationsAndErrors() throws {
    var lock = ProtoWriter()
    lock.message(2) { n in n.message(2) { $0.uint(1, 1) } }
    guard case .lockStateChanged(.unlocked) = try StudioDecoder.decode(lock.data) else { Issue.record("lock"); return }

    var err = ProtoWriter()
    err.message(1) { rr in rr.uint(1, 5); rr.message(2) { $0.uint(2, 1) } }
    guard case .response(5, .error(.unlockRequired)) = try StudioDecoder.decode(err.data) else { Issue.record("err"); return }

    var packed = ProtoWriter()
    packed.message(1) { rr in rr.uint(1, 1); rr.message(4) { b in b.message(1) { list in
        var inner = ProtoWriter()
        for v in [1, 2, 300] as [UInt64] { inner.varint(v) }
        list.bytes(1, inner.data)
    } } }
    guard case .response(_, .behaviorIDs(let ids)) = try StudioDecoder.decode(packed.data) else { Issue.record("ids"); return }
    #expect(ids == [1, 2, 300])
}

@Test func hidUsageRoundTrip() {
    #expect(HIDUsage.encode("A") == 0x0007_0004)
    #expect(HIDUsage.encode("LG(LS(A))") == 0x0A07_0004)
    #expect(HIDUsage.encode("EXCL") == 0x0207_001E)
    #expect(HIDUsage.encode("C_VOL_UP") == 0x000C_00E9)
    #expect(HIDUsage.encode("NUMBER_4") == 0x0007_0021)
    #expect(HIDUsage.decode(0x0007_0004) == "A")
    #expect(HIDUsage.decode(0x0207_001E) == "EXCL")
    #expect(HIDUsage.decode(0x0A07_0004) == "LS(LG(A))")
    #expect(HIDUsage.decode(0x0007_00E1) == "LSHFT")
    #expect(HIDUsage.decode(0x0000_0004) == "A")
}

@Test func liveKeymapTranslatesBothWays() throws {
    let behaviors = [
        StudioBehavior(id: 1, displayName: "Key Press", metadata: [StudioParamSet(param1: [StudioParamValue(name: "Key", kind: .hidUsage(keyboardMax: 0xFF, consumerMax: 0xFFF))], param2: [])]),
        StudioBehavior(id: 2, displayName: "Momentary Layer", metadata: [StudioParamSet(param1: [StudioParamValue(name: "Layer", kind: .layerID)], param2: [])]),
        StudioBehavior(id: 3, displayName: "Bluetooth", metadata: []),
        StudioBehavior(id: 4, displayName: "Transparent", metadata: []),
        StudioBehavior(id: 5, displayName: "Mac Copy", metadata: []),
        StudioBehavior(id: 6, displayName: "HOMEROW_MODS", metadata: [StudioParamSet(
            param1: [StudioParamValue(name: "Hold", kind: .hidUsage(keyboardMax: 0xFF, consumerMax: 0))],
            param2: [StudioParamValue(name: "Tap", kind: .hidUsage(keyboardMax: 0xFF, consumerMax: 0))])]),
    ]
    let keymap = StudioKeymap(layers: [
        StudioLayer(id: 0, name: "Base", bindings: [StudioBinding(behaviorID: 1, param1: 0x070004), StudioBinding(behaviorID: 2, param1: 7)]),
        StudioLayer(id: 7, name: "Fn", bindings: [StudioBinding(behaviorID: 4), StudioBinding(behaviorID: 3, param1: 3, param2: 2)]),
    ], availableLayers: 0, maxLayerNameLength: 20)
    let live = LiveKeymap(keymap: keymap, behaviors: behaviors)

    let layers = live.editorLayers()
    #expect(layers[0].bindings == [.kp("A"), KeyBinding("mo", ["1"])])   // layer id 7 → index 1
    #expect(layers[1].bindings == [.trans, KeyBinding("bt", ["BT_SEL", "2"])])

    #expect(try live.studioBinding(KeyBinding("mo", ["1"])) == StudioBinding(behaviorID: 2, param1: 7))
    #expect(try live.studioBinding(.kp("LG(C)")) == StudioBinding(behaviorID: 1, param1: 0x0807_0006))
    #expect(try live.studioBinding(KeyBinding("Mac_Copy")) == StudioBinding(behaviorID: 5))
    #expect(live.customBehaviors.first { $0.label == "HOMEROW_MODS" }?.isHoldTap == true)
    #expect(throws: LiveKeymap.ConversionError.self) { try live.studioBinding(KeyBinding("caps_word")) }
}

@Test func macShortcutsMatchKeyboardSpelling() {
    #expect(MacShortcut.match("LG(PRCNT)")?.name == "Screenshot & Recording")
    #expect(MacShortcut.match("LC(UP_ARROW)")?.name == "Mission Control")
    #expect(MacShortcut.match("F11") == nil)
}
