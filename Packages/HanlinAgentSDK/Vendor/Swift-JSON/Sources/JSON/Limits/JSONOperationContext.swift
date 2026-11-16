// SPDX-License-Identifier: Apache-2.0
/// All stages of a composed operation borrow this single invocation-owned context.
package struct JSONOperationContext: ~Copyable {
    package var meter: JSONWorkMeter
    package init(limits: JSONLimits, domain: JSONOperationDomain, trackAcceptedCapacities: Bool = false) throws {
        meter = try JSONWorkMeter(limits: limits, domain: domain, trackAcceptedCapacities: trackAcceptedCapacities)
    }
}
