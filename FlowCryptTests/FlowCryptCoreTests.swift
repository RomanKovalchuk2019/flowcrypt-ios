//
//  FlowCryptUITests.swift
//  FlowCryptUITests
//
//  Created by luke on 21/7/2019.
//  Copyright © 2019 FlowCrypt Limited. All rights reserved.
//

import XCTest

class FlowCryptCoreTests: XCTestCase {
    
    override class func setUp() { // Called once before any tests are run
        super.setUp()
        DispatchQueue.promises = .global() // this helps prevent Promise deadlocks
        Core.startInBackgroundIfNotAlreadyRunning()
        do {
            try Core.blockUntilReadyOrThrow()
        } catch {
            XCTFail("Core did not get ready in time")
        }
    }

    // the tests below

    func testVersions() throws {
        let r = try Core.version()
        XCTAssertEqual(r.app_version, "iOS 0.2")
    }
    
    func testGenerateKey() throws {
        let r = try Core.generateKey(passphrase: "some pass phrase test", variant: KeyVariant.curve25519, userIds: [UserId(email: "first@domain.com", name: "First")])
        XCTAssertNotNil(r.key.private);
        XCTAssertEqual(r.key.isDecrypted, false);
        XCTAssertNotNil(r.key.private!.range(of: "-----BEGIN PGP PRIVATE KEY BLOCK-----"))
        XCTAssertNotNil(r.key.public.range(of: "-----BEGIN PGP PUBLIC KEY BLOCK-----"))
        XCTAssertEqual(r.key.ids.count, 2)
    }
    
    func testParseKeys() throws {
        let r = try Core.parseKeys(armoredOrBinary: TestData.k0.pub.data(using: .utf8)! + [10] + TestData.k1.prv.data(using: .utf8)!)
        XCTAssertEqual(r.format, CoreRes.ParseKeys.Format.armored);
        XCTAssertEqual(r.keyDetails.count, 2);
        // k0 k is public
        let k0 = r.keyDetails[0]
        XCTAssertNil(k0.private);
        XCTAssertNil(k0.isDecrypted);
        XCTAssertEqual(k0.ids[0].longid, TestData.k0.longid)
        // k1 is private
        let k1 = r.keyDetails[1]
        XCTAssertNotNil(k1.private);
        XCTAssertEqual(k1.isDecrypted, false);
        XCTAssertEqual(k1.ids[0].longid, TestData.k1.longid)
        // todo - could test user ids
    }
    
    func testDecryptKeyWithCorrectPassPhrase() throws {
        let decryptKeyRes = try Core.decryptKey(armoredPrv: TestData.k0.prv, passphrase: TestData.k0.passphrase)
        XCTAssertNotNil(decryptKeyRes.decryptedKey)
        // make sure indeed decrypted
        let parseKeyRes = try Core.parseKeys(armoredOrBinary: decryptKeyRes.decryptedKey!.data(using: .utf8)!)
        XCTAssertEqual(parseKeyRes.keyDetails[0].isDecrypted, true)
    }

    func testDecryptKeyWithWrongPassPhrase() throws {
        let k = try Core.decryptKey(armoredPrv: TestData.k0.prv, passphrase: "wrong")
        XCTAssertNil(k.decryptedKey)
    }

    func testComposeEmailPlain() throws {
        let msg = SendableMsg(text: "this is the message", to: ["email@hello.com"], cc: [], bcc: [], from: "sender@hello.com", subject: "subj", replyToMimeMsg: nil)
        let composeEmailRes = try Core.composeEmail(msg: msg, fmt: MsgFmt.plain, pubKeys: nil)
        let mime = String(data: composeEmailRes.mimeEncoded, encoding: .utf8)!
        XCTAssertNil(mime.range(of: "-----BEGIN PGP MESSAGE-----")) // not encrypted
        XCTAssertNotNil(mime.range(of: msg.text)) // plain text visible
        XCTAssertNotNil(mime.range(of: "Subject: \(msg.subject)")) // has mime Subject header
        XCTAssertNil(mime.range(of: "In-Reply-To")) // Not a reply
    }

    func testComposeEmailEncryptInline() throws {
        let msg = SendableMsg(text: "this is the message", to: ["email@hello.com"], cc: [], bcc: [], from: "sender@hello.com", subject: "subj", replyToMimeMsg: nil)
        let composeEmailRes = try Core.composeEmail(msg: msg, fmt: MsgFmt.encryptInline, pubKeys: [TestData.k0.pub, TestData.k1.pub])
        let mime = String(data: composeEmailRes.mimeEncoded, encoding: .utf8)!
        XCTAssertNotNil(mime.range(of: "-----BEGIN PGP MESSAGE-----")) // encrypted
        XCTAssertNil(mime.range(of: msg.text)) // plain text not visible
        XCTAssertNotNil(mime.range(of: "Subject: \(msg.subject)")) // has mime Subject header
        XCTAssertNil(mime.range(of: "In-Reply-To")) // Not a reply
    }

    func testEndToEnd() throws {
        let passphrase = "some pass phrase test"
        let email = "e2e@domain.com"
        let text = "this is the encrypted e2e content"
        let generateKeyRes = try Core.generateKey(passphrase: passphrase, variant: KeyVariant.curve25519, userIds: [UserId(email: email, name: "End to end")])
        let k = generateKeyRes.key
        let msg = SendableMsg(text: text, to: [email], cc: [], bcc: [], from: email, subject: "e2e subj", replyToMimeMsg: nil)
        let mime = try Core.composeEmail(msg: msg, fmt: MsgFmt.encryptInline, pubKeys: [k.public])
        let keys = [PrvKeyInfo(private: k.private!, longid: k.ids[0].longid, passphrase: passphrase)]
        let decrypted = try Core.parseDecryptMsg(encrypted: mime.mimeEncoded, keys: keys, msgPwd: nil, isEmail: true)
        XCTAssertEqual(decrypted.text, text)
        XCTAssertEqual(decrypted.replyType, CoreRes.ReplyType.encrypted)
        XCTAssertEqual(decrypted.blocks.count, 1)
        let b = decrypted.blocks[0]
        XCTAssertNil(b.keyDetails) // should only be present on pubkey blocks
        XCTAssertNil(b.decryptErr) // was supposed to be a success
        XCTAssertEqual(b.type, MsgBlock.BlockType.plainHtml)
        XCTAssertNotNil(b.content.range(of: text)) // original text contained within the formatted html block
    }

    func testDecryptErrMismatch() throws {
        let key = PrvKeyInfo(private: TestData.k0.prv, longid: TestData.k0.longid, passphrase: TestData.k0.passphrase)
        let r = try Core.parseDecryptMsg(encrypted: TestData.mismatchEncryptedMsg.data(using: .utf8)!, keys: [key], msgPwd: nil, isEmail: false)
        let decrypted = r
        XCTAssertEqual(decrypted.text, "")
        XCTAssertEqual(decrypted.replyType, CoreRes.ReplyType.plain) // replies to errors should be plain
        XCTAssertEqual(decrypted.blocks.count, 2)
        let contentBlock = decrypted.blocks[0]
        XCTAssertEqual(contentBlock.type, MsgBlock.BlockType.plainHtml)
        XCTAssertNotNil(contentBlock.content.range(of: "<body></body>")) // formatted content is empty
        let decryptErrBlock = decrypted.blocks[1]
        XCTAssertEqual(decryptErrBlock.type, MsgBlock.BlockType.decryptErr)
        XCTAssertNotNil(decryptErrBlock.decryptErr)
        let e = decryptErrBlock.decryptErr!;
        XCTAssertEqual(e.error.type, MsgBlock.DecryptErr.ErrorType.keyMismatch)
    }

    func testException() throws {
        do {
            let _ = try Core.decryptKey(armoredPrv: "not really a key", passphrase: "whatnot")
            XCTFail("Should have thrown above")
        } catch Core.Error.exception(let message) {
            print(message)
            XCTAssertNotNil(message.range(of: "Error: Misformed armored text"))
        }
    }

}
