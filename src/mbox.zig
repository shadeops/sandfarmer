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

    pub fn copy(self: *Self, msgs: Self) void {
        self.active = msgs.active;
        self.blocked = msgs.blocked;
        self.done = msgs.done;
        self.err = msgs.err;
    }

    pub fn hasMsgs(self: Self) bool {
        return (self.active | self.blocked | self.done | self.err) != 0;
    }
};
