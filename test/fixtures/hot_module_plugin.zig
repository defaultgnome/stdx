const API = extern struct {
    increaseCallCount: *const fn () callconv(.c) void,
    getCallCount: *const fn () callconv(.c) u32,
};

var call_count: u32 = 0;

fn increaseCallCount() callconv(.c) void {
    call_count += 1;
}

fn getCallCount() callconv(.c) u32 {
    return call_count;
}

export const api = API{
    .increaseCallCount = increaseCallCount,
    .getCallCount = getCallCount,
};
