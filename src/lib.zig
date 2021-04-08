const std = @import("std");

pub const Value = union(enum) {
    String: []const u8,
    Integer: usize,
    List: []Value,
    Dictionary: []std.StringArrayHashMap(Value).Entry,
};

fn peek(r: anytype) ?u8 {
    const c = r.context;
    if (c.pos == c.buffer.len) {
        return null;
    }
    return c.buffer[c.pos];
}

const max_number_length = 25;

/// Accepts a {std.io.FixedBufferStream} and a {std.mem.Allocator} to parse a Bencode stream.
/// @see https://en.wikipedia.org/wiki/Bencode
pub fn parse(r: anytype, alloc: *std.mem.Allocator) anyerror!Value {
    const pc = peek(r) orelse return error.EndOfStream;
    if (pc >= '0' and pc <= '9') return Value{ .String = try parseString(r, alloc), };

    const t = try r.readByte();
    if (t == 'i') return Value{ .Integer = try parseInteger(r, alloc), };
    if (t == 'l') return Value{ .List = try parseList(r, alloc), };
    if (t == 'd') return Value{ .Dictionary = try parseDict(r, alloc), };
    return error.BencodeBadDelimiter;
}

fn parseString(r: anytype, alloc: *std.mem.Allocator) ![]const u8 {
    const str = try r.readUntilDelimiterAlloc(alloc, ':', max_number_length);
    const len = try std.fmt.parseInt(usize, str, 10);
    var buf = try alloc.alloc(u8, len);
    const l = try r.read(buf);
    return buf[0..l];
}

fn parseInteger(r: anytype, alloc: *std.mem.Allocator) !usize {
    const str = try r.readUntilDelimiterAlloc(alloc, 'e', max_number_length);
    const x = try std.fmt.parseInt(usize, str, 10);
    return x;
}

fn parseList(r: anytype, alloc: *std.mem.Allocator) ![]Value {
    var list = std.ArrayList(Value).init(alloc);
    while (true) {
        if (peek(r)) |c| {
            if (c == 'e') {
                _ = try r.readByte();
                return list.toOwnedSlice();
            }
            const v = try parse(r, alloc);
            try list.append(v);
        }
        else {
            break;
        }
    }
    return error.EndOfStream;
}

fn parseDict(r: anytype, alloc: *std.mem.Allocator) ![]std.StringArrayHashMap(Value).Entry {
    var map = std.StringArrayHashMap(Value).init(alloc);
    while (true) {
        if (peek(r)) |c| {
            if (c == 'e') {
                _ = try r.readByte();
                return map.items();
            }
            const k = try parseString(r, alloc);
            const v = try parse(r, alloc);
            try map.put(k, v);
        }
        else {
            break;
        }
    }
    return error.EndOfStream;
}
