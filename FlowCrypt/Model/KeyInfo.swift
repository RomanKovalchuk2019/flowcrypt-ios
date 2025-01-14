//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import RealmSwift

class KeyInfo: Object {

    @objc dynamic var `private`: String = ""
    @objc dynamic var `public`: String = ""
    @objc dynamic var longid: String = ""
    @objc dynamic var passphrase: String = ""
    @objc dynamic var source: String = ""

    convenience init(_ keyDetails: KeyDetails, passphrase: String, source: String) {
        self.init()
        self.private = keyDetails.private! // crash the app if someone tries to pass a public key - that would be a programming error
        self.public = keyDetails.public
        self.longid = keyDetails.ids[0].longid
        self.passphrase = passphrase
        self.source = source
    }

}

