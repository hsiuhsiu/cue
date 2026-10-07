import SwiftUI

// SDK 27 also exposes a macro named State whose plugin ships only with Xcode.
// Naming the property-wrapper type explicitly keeps the same SwiftUI storage,
// bindings, and invalidation on both Xcode and Command Line Tools toolchains.
typealias ViewState<Value> = SwiftUI.State<Value>
