// SPDX-License-Identifier: Apache-2.0
/// A typed source path component; numeric object keys remain keys.
public enum JSONLocationComponent: Sendable, Hashable, Codable {
    /// An exact object key, even when the text consists of digits.
    case key(JSONKey)
    /// A zero-based runtime array index.
    case index(Int)
}
