//! Shared host ↔ plugin contract. Same layout in the executable and the DLL.
pub const Interface = extern struct {
    transform: *const fn (frame: u64) callconv(.c) u64,
};
