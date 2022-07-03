const std = @import("std");
const curl = @import("curl.zig");

const users = @import("users.zig");
const mbox = @import("mbox.zig");

pub const Context = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    usermap: *const users.UserMap,
    msgs: mbox.MsgBuffer,
    ready: bool = false,
    tsid: ?[36:0]u8 = null,
    url: []const u8,

    pub fn getMessages(self: *Self, msg_box: *mbox.MsgBuffer) bool {
        if (@atomicLoad(bool, &self.ready, .Acquire)) {
            msg_box.copy(self.msgs);
            self.msgs.clear();
            @atomicStore(bool, &self.ready, false, .Release);
            return true;
        }
        return false;
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
            defer std.time.sleep(1 * std.time.ns_per_s);

            var has_msgs = self.queryTractor(&mqueue) catch |err| switch (err) {
                error.FailedToPerformRequest => continue,
                else => return err,
            };
            if (!has_msgs) continue;

            /////////////////////////
            // start barrier
            while (@atomicLoad(bool, &self.ready, .Acquire)) {
                // If self.ready is still true it means getMessages hasn't yet
                // had a chance to run so we spin for a bit
                std.atomic.spinLoopHint();
            }

            var i: usize = 0;
            while (!self.msgs.isFull() and i < mqueue.items.len) : (i += 1) {
                _ = try self.msgs.append(mqueue.items[i]);
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

    pub fn queryTractor(self: *Self, queue: *std.ArrayList(mbox.Msg)) !bool {
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
    ) !bool {
        var p = std.json.Parser.init(self.allocator, false);
        defer p.deinit();

        var tree = try p.parse(response.items);
        defer tree.deinit();

        var json_mbox = tree.root.Object.get("mbox") orelse return false;

        for (json_mbox.Array.items) |item| {
            if (std.mem.eql(u8, item.Array.items[0].String, "c")) {
                var mtype: mbox.MsgType = undefined;
                if (std.mem.eql(u8, item.Array.items[4].String, "A")) {
                    mtype = .active;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "B")) {
                    mtype = .blocked;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "D")) {
                    mtype = .done;
                } else if (std.mem.eql(u8, item.Array.items[4].String, "E")) {
                    mtype = .err;
                } else {
                    continue;
                }
                // if uid doesn't exist then it something like root or other meta-user.
                // in this case we store the user as second to last (as the last is the sums).
                var uid: u16 = self.usermap.getUid(item.Array.items[12].String) orelse (128 * 128 - 2);
                try queue.append(.{
                    .jid = @intCast(u32, item.Array.items[1].Integer),
                    .owner = uid,
                    .msg = mtype,
                });
            }
        }

        return true;
    }
};

//"mbox": [["c", 1203080001,14,13,"I",1,"hostname/11.22.00.33",9005,0,0,0,0, "dml", 1331263984.161]]
