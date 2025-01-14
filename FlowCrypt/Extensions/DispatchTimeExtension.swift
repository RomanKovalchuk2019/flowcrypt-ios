//
// © 2017-2019 FlowCrypt Limited. All rights reserved.
//

import Foundation

extension DispatchTime {

    public func millisecondsSince() -> UInt64 {
        return (DispatchTime.now().uptimeNanoseconds - self.uptimeNanoseconds) / 1_000_000
    }

}