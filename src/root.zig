const std = @import("std");
const print = std.debug.print;

const c = @cImport({
    @cInclude("liburing.h");
});

fn check(ret: i32) !void {
    if (ret < 0) {
        return switch (ret) {
            -c.EINVAL => error.Invalid,
            else => error.Unexpected,
        };
    }
}

const Uring = struct {
    ring: c.io_uring,

    const Self = @This();

    const Options = struct {
        queue_size: u16 = 256,
    };

    pub fn init(opts: Options) !Self {
        var self = Self{
            .ring = undefined,
        };

        try check(c.io_uring_queue_init(opts.queue_size, &self.ring, c.IORING_SETUP_SINGLE_ISSUER));

        return self;
    }

    pub fn deinit(self: *Self) void {
        c.io_uring_queue_exit(&self.ring);
    }

    pub fn entry(self: *Self) !Entry {
        const sqe = c.io_uring_get_sqe(&self.ring);
        return Entry{ .sqe = sqe orelse return error.NoEntryFree };
    }

    pub fn submit(self: *Self) !void {
        try check(c.io_uring_submit(&self.ring));
    }

    pub fn submit_and_wait(self: *Self, count: u16) !void {
        try check(c.io_uring_submit_and_wait(&self.ring, count));
    }

    const Entry = struct {
        sqe: *c.io_uring_sqe,

        pub fn prep_socket(self: *Entry) void {
            c.io_uring_prep_socket(&self.sqe, 0, 0, 0, 0);
        }

        pub fn prep_read(self: *Entry, fd: i32, buf: []u8, offset: u64) void {
            c.io_uring_prep_read(&self.sqe, fd, buf.ptr, buf.len, offset);
        }
    };
};

pub fn server(port: u16) !void {
    var ring = try Uring.init(.{});
    defer ring.deinit();

    try ring.submit();

    print("Starting on port {}\n", .{port});
}
