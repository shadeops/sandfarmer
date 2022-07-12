const std = @import("std");

pub const MsgType = enum(u2) {
    active,
    done,
    blocked,
    err,
};

pub const Msg = struct {
    jid: u32,
    owner: u16,
    msg: MsgType, //u3
};

pub const MsgBuffer = struct {
    const Self = @This();
    msgs: []Msg,
    pos: usize = 0,
    size: usize = 0,

    pub fn append(self: *Self, msg: Msg) !usize {
        var new_size = self.size + 1;
        if (new_size > self.msgs.len)
            return error.FullMsgBuffer;
        var append_pos = (self.pos + self.size) % self.msgs.len;
        self.msgs[append_pos] = msg;
        self.size = new_size;
        return self.size;
    }

    pub fn isFull(self: Self) bool {
        return self.size >= self.msgs.len;
    }

    pub fn copy(self: *Self, buf: MsgBuffer) void {
        std.debug.assert(buf.msgs.len == self.msgs.len);
        var i: usize = 0;
        while (i < buf.size) : (i += 1) {
            var idx = (buf.pos + i) % buf.msgs.len;
            self.msgs[idx] = buf.msgs[idx];
        }
        self.pos = buf.pos;
        self.size = buf.size;
    }

    pub fn next(self: *Self) ?Msg {
        if (self.size == 0) return null;
        var cur_pos = self.pos;
        self.pos = (self.pos + 1) % self.msgs.len;
        self.size = self.size - 1;
        return self.msgs[cur_pos];
    }

    pub fn clear(self: *Self) void {
        self.pos = 0;
        self.size = 0;
    }
};

test "msg buffer" {
    var msgs = [_]Msg{undefined} ** 3;
    var buffer = MsgBuffer{
        .msgs = msgs[0..],
    };
    try std.testing.expectEqual(3, msgs.len);

    _ = try buffer.append(.{ .jid = 1, .msg = .active, .owner = 1 });
    try std.testing.expectEqual(@as(usize, 1), buffer.size);
    try std.testing.expectEqual(@as(usize, 0), buffer.pos);

    _ = try buffer.append(.{ .jid = 2, .msg = .active, .owner = 1 });
    try std.testing.expectEqual(@as(usize, 2), buffer.size);

    _ = try buffer.append(.{ .jid = 3, .msg = .active, .owner = 1 });
    try std.testing.expectEqual(@as(usize, 3), buffer.size);

    try std.testing.expectError(
        error.FullMsgBuffer,
        buffer.append(.{ .jid = 4, .msg = .active, .owner = 1 }),
    );

    var m = buffer.next();
    try std.testing.expectEqual(@as(usize, 1), buffer.pos);
    try std.testing.expectEqual(@as(usize, 2), buffer.size);
    try std.testing.expectEqual(@as(u32, 1), m.?.jid);

    _ = try buffer.append(.{ .jid = 4, .msg = .active, .owner = 1 });
    try std.testing.expectEqual(@as(usize, 3), buffer.size);
    try std.testing.expectEqual(@as(usize, 1), buffer.pos);

    try std.testing.expectEqual(@as(u32, 4), buffer.msgs[0].jid);
    m = buffer.next();
    m = buffer.next();
    m = buffer.next();
    try std.testing.expect(buffer.next() == null);
}

test "msg_queue" {
    var queue = std.ArrayList(Msg).init(std.testing.allocator);
    defer queue.deinit();
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        try queue.append(.{ .jid = @intCast(u32, i), .owner = 0, .msg = .active });
    }
    try std.testing.expectEqual(queue.items.len, 32);
    try std.testing.expectEqual(queue.items[0].jid, 0);
    var capacity = queue.capacity;
    var new_len = queue.items.len - 20;
    try queue.replaceRange(0, 10, queue.items[20..30]);
    try std.testing.expectEqual(queue.items[0].jid, 20);
    queue.shrinkRetainingCapacity(new_len);
    try std.testing.expectEqual(queue.capacity, capacity);
}
