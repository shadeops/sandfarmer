const std = @import("std");
const curl = @import("curl.zig");

const users = @import("users.zig");
const mbox = @import("mbox.zig");

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    msgs: mbox.MessageCounts = .{},
    usermap: *const users.UserMap,
    mbuffer: mbox.MsgBuffer,
    ready: bool = false,
    tsid: ?[36:0]u8 = null,
    url: []const u8,

    pub fn getMessages(self: *Self, msg_box: *mbox.MsgBuffer) ?mbox.MessageCounts {
        if (@atomicLoad(bool, &self.ready, .Acquire)) {
            var msgs = self.msgs;
            msg_box.copy(self.mbuffer);
            self.mbuffer.clear();
            self.msgs.clear();
            @atomicStore(bool, &self.ready, false, .Release);
            return msgs;
        }
        return null;
    }

    pub fn startThread(self: *Self) !std.Thread {
        try self.tractorLogin();
        var thread = try std.Thread.spawn(.{}, callback, .{self});
        return thread;
    }

    fn callback(self: *Self) !void {
        var mqueue = std.ArrayList(mbox.Msg).init(self.allocator);
        defer mqueue.deinit();
        // TODO if the mqueue gets huge, sleep (or ignore msgs for a bit)
        while (true) {
            var new_msgs = (try self.queryTractor(&mqueue)) orelse continue;

            /////////////////////////
            // start barrier
            while (@atomicLoad(bool, &self.ready, .Acquire)) {}

            self.msgs.copy(new_msgs);
            var i: usize = 0;
            while (!self.mbuffer.isFull() and i < mqueue.items.len) : (i += 1) {
                _ = try self.mbuffer.append(mqueue.items[i]);
            }

            @atomicStore(bool, &self.ready, true, .Release);
            // end barrier
            /////////////////////////

            var new_len = mqueue.items.len - i;
            if (i > 0) {
                for (mqueue.items[i..]) |v, idx| {
                    mqueue.items[idx] = v;
                }
                mqueue.shrinkRetainingCapacity(new_len);
            }

            std.time.sleep(1 * std.time.ns_per_s);
        }
    }

    fn tractorLogin(self: *Self) !void {
        //std.debug.print("Logging into Tractor\n", .{});
        var buf: [64:0]u8 = undefined;
        var post = try std.fmt.bufPrintZ(buf[0..], "q=login&user={s}", .{std.os.getenv("USER")});
        var response = try curl.request(self.allocator, post, self.url);
        defer response.deinit();

        var p = std.json.Parser.init(self.allocator, false);
        defer p.deinit();

        var tree = try p.parse(response.items);
        defer tree.deinit();
        self.tsid = [_:0]u8{0} ** 36;
        for (tree.root.Object.get("tsid").?.String) |v, i| {
            self.tsid.?[i] = v;
        }
    }

    pub fn queryTractor(self: *Self, queue: *std.ArrayList(mbox.Msg)) !?mbox.MessageCounts {
        var buf: [128:0]u8 = undefined;
        var post = try std.fmt.bufPrintZ(buf[0..], "q=subscribe&jids=0&tsid={s}", .{self.tsid.?});
        var response = try curl.request(self.allocator, post, self.url);
        defer response.deinit();
        //std.debug.print("\n\n{s}\n\n", .{response.items});
        return self.parseResponse(response, queue);
    }

    fn parseResponse(
        self: *Self,
        response: std.ArrayList(u8),
        queue: *std.ArrayList(mbox.Msg),
    ) !?mbox.MessageCounts {
        var p = std.json.Parser.init(self.allocator, false);
        defer p.deinit();

        var tree = try p.parse(response.items);
        defer tree.deinit();

        var json_mbox = tree.root.Object.get("mbox") orelse return null;

        var msgs = mbox.MessageCounts{};

        for (json_mbox.Array.items) |item| {
            if (std.mem.eql(u8, item.Array.items[0].String, "c")) {
                var mtype: mbox.MsgType = undefined;
                if (std.mem.eql(u8, item.Array.items[4].String, "A")) {
                    mtype = .active;
                    msgs.active += 1;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "B")) {
                    mtype = .blocked;
                    msgs.blocked += 1;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "D")) {
                    mtype = .done;
                    msgs.done += 1;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "E")) {
                    mtype = .err;
                    msgs.err += 1;
                } else {
                    continue;
                }
                try queue.append(.{
                    .jid = @intCast(u32, item.Array.items[1].Integer),
                    .owner = self.usermap.getUid(item.Array.items[12].String).?,
                    .msg = mtype,
                });
            }
        }

        return msgs;
    }
};

//"mbox": [["c", 1203080001,14,13,"I",1,"hostname/11.22.00.33",9005,0,0,0,0, "dml", 1331263984.161]]
