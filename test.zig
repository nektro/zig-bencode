const std = @import("std");
const bencode = @import("bencode");
const expect = @import("expect").expect;

test {
    const alloc = std.testing.allocator;
    const file = @embedFile("./archlinux-2021.04.01-x86_64.iso.torrent");

    var fbs = std.io.fixedBufferStream(file);
    const r = fbs.reader();
    const ben = try bencode.parse(r, alloc);
    defer ben.deinit(alloc);

    try expect(ben.getS("comment")).toEqualString("Arch Linux 2021.04.01 (www.archlinux.org)");
    try expect(ben.getS("created by")).toEqualString("mktorrent 1.1");
    try expect(ben.getU("creation date")).toEqual(1617297570);
    try expect(ben.getD("info")).not().toBeNull();
    try expect(ben.getD("info").?.getU("length")).toEqual(786771968);
    try expect(ben.getD("info").?.getS("name")).toEqualString("archlinux-2021.04.01-x86_64.iso");
    try expect(ben.getD("info").?.getU("piece length")).toEqual(524288);
    try expect(ben.getD("info").?.getS("pieces").?.len).toEqual(30020);
}
