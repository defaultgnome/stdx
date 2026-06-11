//! DLL entry: exports `dll_interface` and forwards to `plugin/root.zig`.
const plugin = @import("plugin");
const interface = @import("interface");

fn dll_transform(frame: u64) callconv(.c) u64 {
    return plugin.transform(frame);
}

export const dll_interface: interface.Interface = .{
    .transform = dll_transform,
};
