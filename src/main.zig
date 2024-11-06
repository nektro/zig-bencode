const std = @import("std");
const bencode = @import("bencode");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const file = @embedFile("torrent_file");

    var buf = std.io.fixedBufferStream(file);
    const r = buf.reader();
    const ben = try bencode.parse(r, alloc);

    std.log.info("{s}", .{ben});
}
