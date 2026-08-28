import AppKit

/// Honours the system's Reduce Motion setting. The panel's fade and the rings'
/// interpolation are decoration; someone who has asked the system to stop
/// moving things should get the new value straight away instead.
enum Motion {
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `seconds`, or zero when motion is reduced.
    static func duration(_ seconds: CFTimeInterval) -> CFTimeInterval {
        reduced ? 0 : seconds
    }
}
