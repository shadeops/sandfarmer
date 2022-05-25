const std = @import("std");

const MessageCounts = @import("mbox.zig").MessageCounts;

pub const Context = struct {
    const Self = @This();

    msgs: MessageCounts = .{},
    ready: bool = false,
    size: u32 = 10,
    prng: std.rand.Random = undefined,

    pub fn getMessages(self: *Self) ?MessageCounts {
        if (@atomicLoad(bool, &self.ready, .Acquire)) {
            var msgs = self.msgs;
            self.msgs.clear();
            @atomicStore(bool, &self.ready, false, .Release);
            return msgs;
        }
        return null;
    }

    pub fn startThread(self: *Self) !std.Thread {
        var thread = try std.Thread.spawn(.{}, callback, .{self});
        return thread;
    }

    fn callback(self: *Self) void {
        while (true) {
            while (@atomicLoad(bool, &self.ready, .Acquire)) {}
            self.gatherData();
            @atomicStore(bool, &self.ready, true, .Release);
            std.time.sleep(1 * std.time.ns_per_s);
        }
        std.debug.print("thread done\n", .{});
    }

    fn gatherData(self: *Self) void {
        self.msgs.active = self.prng.intRangeAtMost(u32, 0, 10 * self.size);
        self.msgs.blocked = self.prng.intRangeAtMost(u32, 0, 1 * self.size);
        self.msgs.done = self.prng.intRangeAtMost(u32, 0, 10 * self.size);
        self.msgs.err = self.prng.intRangeAtMost(u32, 0, 5 * self.size);
    }
};
