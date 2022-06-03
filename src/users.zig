const std = @import("std");

const curl = @import("curl.zig");

pub const User = extern struct {
    dept: u8, // dept
    sub: u8, // sub
    unit: u8, // unit
    div: u8, // div
};

/// Key index for looking up into a ArrayList
const SliceRange = struct {
    start: u24 = 0,
    len: u8 = 0,
};

/// These allow us to store all our strings in one continous block of memory
/// which a hash_map then indexes into using a two context adapters to translate
/// between our offsets within ArrayList and the string slices. This is a similar
/// workflow to
/// https://zig.news/andrewrk/how-to-use-hash-map-contexts-to-save-memory-when-doing-a-string-table-3l33
/// and std.hash_map.StringIndexContext / std.hash_map.StringIndexAdapter but doesn't rely on
/// null terminated strings.
///
/// The main reason for needing this is using an ArrayList directly, the pointers are invalidated
/// whenever the array resizes.
const SliceIndexContext = struct {
    bytes: *const std.ArrayListUnmanaged(u8),

    pub fn eql(self: @This(), a: SliceRange, b: SliceRange) bool {
        _ = self;
        return a.start == b.start and a.len == b.len;
    }

    pub fn hash(self: @This(), x: SliceRange) u64 {
        std.debug.assert(self.bytes.items.len >= x.start + x.len);
        const x_slice = self.bytes.items[x.start..(x.start + x.len)];
        return std.hash_map.hashString(x_slice);
    }
};

const SliceIndexAdapter = struct {
    bytes: *const std.ArrayListUnmanaged(u8),

    pub fn eql(self: @This(), a_slice: []const u8, b: SliceRange) bool {
        std.debug.assert(self.bytes.items.len >= b.start + b.len);
        const b_slice = self.bytes.items[b.start..(b.start + b.len)];
        return std.mem.eql(u8, a_slice, b_slice);
    }

    pub fn hash(self: @This(), adapted_key: []const u8) u64 {
        _ = self;
        return std.hash_map.hashString(adapted_key);
    }
};

pub const UserMap = struct {
    const Self = @This();

    logins: std.ArrayListUnmanaged(u8),
    uid_map: std.HashMapUnmanaged(
        SliceRange,
        u16,
        SliceIndexContext,
        std.hash_map.default_max_load_percentage,
    ),
    users: []User,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var users = try allocator.alloc(User, 128 * 128);
        for (users) |*user| {
            user.* = .{
                .dept = 0,
                .sub = 0,
                .unit = 0,
                .div = 0,
            };
        }

        return UserMap{
            .logins = .{},
            .uid_map = .{},
            .users = users,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.users);
        self.uid_map.deinit(self.allocator);
        self.logins.deinit(self.allocator);
    }

    pub fn addLogin(self: *Self, login: []const u8, uid: u16) !void {
        const slice_context: SliceIndexContext = .{ .bytes = &self.logins };
        const srange = SliceRange{
            .start = @intCast(u24, self.logins.items.len),
            .len = @intCast(u8, login.len),
        };
        try self.logins.appendSlice(self.allocator, login);
        try self.uid_map.putContext(self.allocator, srange, uid, slice_context);
    }

    pub fn getUid(self: Self, login: []const u8) ?u16 {
        const slice_adapter: SliceIndexAdapter = .{ .bytes = &self.logins };
        return self.uid_map.getAdapted(login, slice_adapter);
    }

    pub fn getKey(self: Self, srange: SliceRange) []const u8 {
        std.debug.assert(self.logins.items.len >= (srange.start + srange.len));
        return self.logins.items[srange.start..(srange.start + srange.len)];
    }
};

pub fn queryUsers(allocator: std.mem.Allocator, url: []const u8) !UserMap {
    var response = try curl.request(allocator, null, url);
    defer response.deinit();
    //std.debug.print("\n\n{s}\n\n", .{response.items});

    var p = std.json.Parser.init(allocator, false);
    defer p.deinit();

    var tree = try p.parse(response.items);
    defer tree.deinit();

    var dept_map = std.StringHashMap(u8).init(allocator);
    defer dept_map.deinit();
    var sub_map = std.StringHashMap(u8).init(allocator);
    defer sub_map.deinit();
    var unit_map = std.StringHashMap(u8).init(allocator);
    defer unit_map.deinit();
    var div_map = std.StringHashMap(u8).init(allocator);
    defer div_map.deinit();

    var user_map_obj = tree.root.Object;

    var user_mapping = try UserMap.init(allocator);
    errdefer user_mapping.deinit();

    var user_map_iter = user_map_obj.iterator();
    while (user_map_iter.next()) |kv| {
        var user_obj = kv.value_ptr.Object;

        var login = user_obj.get("login").?.String;
        var uid = try std.fmt.parseUnsigned(u16, kv.key_ptr.*, 10);
        try user_mapping.addLogin(login, uid);

        var div_str = user_obj.get("division").?.String;
        var div: ?u8 = undefined;
        div = div_map.get(div_str);
        if (div == null) {
            div = @intCast(u8, div_map.count());
            try div_map.put(div_str, div.?);
        }

        var dept_str = user_obj.get("dept").?.String;
        var dept: ?u8 = undefined;
        dept = dept_map.get(dept_str);
        if (dept == null) {
            dept = @intCast(u8, dept_map.count());
            try dept_map.put(dept_str, dept.?);
        }

        var sub_str = user_obj.get("sub").?.String;
        var sub: ?u8 = undefined;
        sub = sub_map.get(sub_str);
        if (sub == null) {
            sub = @intCast(u8, sub_map.count());
            try sub_map.put(sub_str, sub.?);
        }

        var unit_str = user_obj.get("unit").?.String;
        var unit: ?u8 = undefined;
        unit = unit_map.get(unit_str);
        if (unit == null) {
            unit = @intCast(u8, unit_map.count());
            try unit_map.put(unit_str, unit.?);
        }

        user_mapping.users[uid] = .{
            .dept = dept.?,
            .sub = sub.?,
            .unit = unit.?,
            .div = div.?,
        };
    }

    user_mapping.users[user_mapping.users.len - 1] = .{
        .dept = @intCast(u8, dept_map.count()),
        .sub = @intCast(u8, sub_map.count()),
        .unit = @intCast(u8, unit_map.count()),
        .div = @intCast(u8, div_map.count()),
    };

    return user_mapping;
}

test "hash contexts" {
    const Mapper = struct {
        names: std.ArrayListUnmanaged(u8),
        map: std.HashMapUnmanaged(
            SliceRange,
            u16,
            SliceIndexContext,
            std.hash_map.default_max_load_percentage,
        ),
        fn init() @This() {
            return .{ .map = .{}, .names = .{} };
        }
        fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.names.deinit(allocator);
            self.map.deinit(allocator);
        }
    };

    const gpa = std.testing.allocator;
    var users = Mapper.init();
    defer users.deinit(gpa);

    const slice_context: SliceIndexContext = .{ .bytes = &users.names };
    var name1: []const u8 = "hello";
    var name2: []const u8 = "there";

    var srange = SliceRange{};
    srange = .{
        .start = @intCast(u24, users.names.items.len),
        .len = @intCast(u8, name1.len),
    };
    try users.names.appendSlice(gpa, name1);
    try users.map.putContext(gpa, srange, 0, slice_context);

    srange = .{
        .start = @intCast(u24, users.names.items.len),
        .len = @intCast(u8, name2.len),
    };
    try users.names.appendSlice(gpa, name2);
    try users.map.putContext(gpa, srange, 1, slice_context);

    const slice_adapter: SliceIndexAdapter = .{ .bytes = &users.names };
    var found_entry = users.map.getEntryAdapted(@as([]const u8, "hello"), slice_adapter);
    try std.testing.expectEqual(found_entry.?.value_ptr.*, 0);
    found_entry = users.map.getEntryAdapted(@as([]const u8, "there"), slice_adapter);
    try std.testing.expectEqual(found_entry.?.value_ptr.*, 1);
    found_entry = users.map.getEntryAdapted(@as([]const u8, "nope"), slice_adapter);
    try std.testing.expectEqual(found_entry, null);
}
