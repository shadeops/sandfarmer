const std = @import("std");

pub const MessageCounts = struct {
    const Self = @This();
    active: u32 = 0,
    blocked: u32 = 0,
    done: u32 = 0,
    err: u32 = 0,

    pub fn clear(self: *Self) void {
        self.active = 0;
        self.blocked = 0;
        self.done = 0;
        self.err = 0;
    }

    pub fn add(self: *Self, msgs: Self) void {
        self.active += msgs.active;
        self.blocked += msgs.blocked;
        self.done += msgs.done;
        self.err += msgs.err;
    }

    pub fn sub(self: *Self, msgs: Self) void {
        self.active -= msgs.active;
        self.blocked -= msgs.blocked;
        self.done -= msgs.done;
        self.err -= msgs.err;
    }

    pub fn hasMsgs(self: Self) bool {
        return (self.active | self.blocked | self.done | self.err) != 0;
    }
};

pub const ThreadContext = struct {
    msgs: MessageCounts = .{},
    ready: bool = false,
    size: u32 = 10,
    prng: std.rand.Random = undefined,
};

fn gatherData(ctx: *ThreadContext) void {
    ctx.msgs.active = ctx.prng.intRangeAtMost(u32, 0, 10 * ctx.size);
    ctx.msgs.blocked = ctx.prng.intRangeAtMost(u32, 0, 1 * ctx.size);
    ctx.msgs.done = ctx.prng.intRangeAtMost(u32, 0, 10 * ctx.size);
    ctx.msgs.err = ctx.prng.intRangeAtMost(u32, 0, 5 * ctx.size);
}

fn callback(ctx: *ThreadContext) void {
    while (true) {
        while (@atomicLoad(bool, &ctx.ready, .Acquire)) {}
        gatherData(ctx);
        @atomicStore(bool, &ctx.ready, true, .Release);
        std.time.sleep(1 * std.time.ns_per_s);
    }
    std.debug.print("thread done\n", .{});
}

pub fn startGenerator(ctx: *ThreadContext) !std.Thread {
    var thread = try std.Thread.spawn(.{}, callback, .{ctx});
    return thread;
}

pub fn getMessages(ctx: *ThreadContext) ?MessageCounts {
    if (@atomicLoad(bool, &ctx.ready, .Acquire)) {
        var msgs = ctx.msgs;
        ctx.msgs.clear();
        @atomicStore(bool, &ctx.ready, false, .Release);
        return msgs;
    }
    return null;
}
