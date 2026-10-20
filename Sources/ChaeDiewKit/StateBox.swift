import SwiftUI

/// Mutable view state held in an ObservableObject. Used instead of `@State`, whose macro plugin
/// is not shipped with the Command Line Tools, so the project builds without a full Xcode.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}
