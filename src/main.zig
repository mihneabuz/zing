const std = @import("std");
const zring = @import("zring");

pub fn main() !void {
    try zring.server(3000);
}

