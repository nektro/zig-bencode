const std = @import("std");

const bencode = @import("./lib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const file = @embedFile("./../archlinux-2021.04.01-x86_64.iso.torrent");
    var buf = std.io.fixedBufferStream(file);
    const r = buf.reader();
    const ben = try bencode.parse(r, alloc);

    std.log.info("{s}", .{ben});
}
