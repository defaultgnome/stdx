//! Plugin logic. Edit this file during development; it is linked directly in Release.
pub fn init() void {}

pub fn deinit() void {}

pub fn transform(frame: u64) u64 {
    // Change me to the power of three while running (frame * frame * frame).
    return frame * frame;
}
