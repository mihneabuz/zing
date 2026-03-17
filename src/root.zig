const std = @import("std");
const print = std.debug.print;

const c = @cImport({
    @cInclude("netinet/in.h");
    @cInclude("liburing.h");
});

extern fn io_uring_get_sqe(arg_ring: [*c]c.io_uring) callconv(.c) [*c]c.io_uring_sqe;
extern fn io_uring_peek_cqe(arg_ring: [*c]c.io_uring, arg_cqe_ptr: [*c][*c]c.io_uring_cqe) callconv(.c) c_int;
extern fn io_uring_cqe_seen(arg_ring: [*c]c.io_uring, arg_cqe: [*c]c.io_uring_cqe) callconv(.c) void;

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

    pub fn entry(self: *Self) !Submission {
        const sqe = io_uring_get_sqe(&self.ring);
        return Submission{ .sqe = sqe orelse return error.NoEntryFree };
    }

    pub fn submit(self: *Self) !void {
        try check(c.io_uring_submit(&self.ring));
    }

    pub fn submit_and_wait(self: *Self, count: u16) !void {
        try check(c.io_uring_submit_and_wait(&self.ring, count));
    }

    pub fn completion(self: *Self) !Completion {
        var cqe = Completion{ .cqe = undefined };
        try check(io_uring_peek_cqe(&self.ring, &cqe.cqe));
        io_uring_cqe_seen(&self.ring, cqe.cqe);
        return cqe;
    }

    const Submission = struct {
        sqe: [*c]c.io_uring_sqe,

        pub fn prep_socket(self: *Submission, domain: c_int, stype: c_int) void {
            c.io_uring_prep_socket(self.sqe, domain, stype, 0, 0);
        }

        pub fn prep_bind(self: *Submission, fd: c_int, addr: *const c.sockaddr, addrlen: c.socklen_t) void {
            c.io_uring_prep_bind(self.sqe, fd, addr, addrlen);
        }

        pub fn prep_read(self: *Submission, fd: c_int, buf: []u8, offset: u64) void {
            c.io_uring_prep_read(self.sqe, fd, buf.ptr, buf.len, offset);
        }
    };

    const Completion = struct {
        cqe: [*c]c.io_uring_cqe,

        pub fn result(self: *const Completion) i32 {
            return self.cqe.*.res;
        }
    };
};

pub fn server(port: u16) !void {
    var ring = try Uring.init(.{});
    defer ring.deinit();

    var entry1 = try ring.entry();
    entry1.prep_socket(c.AF_INET, c.SOCK_STREAM);

    try ring.submit();

    const comp1 = try ring.completion();
    const sock = comp1.result();
    print("Socket: {}\n", .{sock});

    var entry2 = try ring.entry();
    const addr: c.sockaddr_in = .{
        .sin_family = c.AF_INET,
        .sin_addr = c.in_addr {
            .s_addr = c.INADDR_ANY,
        },
    };
    entry2.prep_bind(sock, @ptrCast(&addr), @sizeOf(c.sockaddr_in));

    try ring.submit();

    const comp2 = try ring.completion();
    print("Bind: {}\n", .{comp2.result()});

    print("Starting on port {}\n", .{port});
}
