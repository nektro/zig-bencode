const std = @import("std");

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Dictionary: std.StringArrayHashMapUnmanaged(Value),

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        _ = fmt;
        _ = options;

        switch (self) {
            .String => |v| {
                try writer.writeByte('"');
                try std.fmt.format(writer, "{}", .{std.zig.fmtEscapes(v)});
                try writer.writeByte('"');
            },
            .Integer => |v| {
                try std.fmt.format(writer, "{d}", .{v});
            },
            .List => |v| {
                try writer.writeByte('[');
                for (v) |item| {
                    try writer.print("{}", .{item});
                    try writer.writeByte(',');
                }
                try writer.writeByte(']');
            },
            .Dictionary => |v| {
                try writer.writeByte('{');
                for (v.keys(), v.values()) |kk, vv| {
                    try writer.print("\"{s}\": {},", .{ kk, vv });
                }
                try writer.writeByte('}');
            },
        }
    }

    pub fn encode(self: Value, writer: anytype) !void {
        switch (self) {
            .String => |v| {
                try writer.print("{d}", .{v.len});
                try writer.writeByte(':');
                try writer.writeAll(v);
            },
            .Integer => |v| {
                try writer.writeByte('i');
                try writer.print("{d}", .{v});
                try writer.writeByte('e');
            },
            .List => |v| {
                try writer.writeByte('l');
                for (v) |item| {
                    try item.encode(writer);
                }
                try writer.writeByte('e');
            },
            .Dictionary => |v| {
                try writer.writeByte('d');
                for (v.keys(), v.values()) |kk, vv| {
                    try (Value{ .String = kk }).encode(writer);
                    try vv.encode(writer);
                }
                try writer.writeByte('e');
            },
        }
    }

    pub fn getT(self: Value, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == tag) @field(ret, @tagName(tag)) else null;
    }
};

fn peek(r: anytype) ?u8 {
    const c = r.context;
    if (c.pos == c.buffer.len) return null;
    return c.buffer[c.pos];
}

const max_number_length = 25;

/// Accepts a {std.io.FixedBufferStream} and a {std.mem.Allocator} to parse a Bencode stream.
/// @see https://en.wikipedia.org/wiki/Bencode
pub fn parse(r: anytype, alloc: std.mem.Allocator) anyerror!Value {
    const pc = peek(r) orelse return error.EndOfStream;
    if (pc >= '0' and pc <= '9') return Value{
        .String = try parseString(r, alloc),
    };

    const t = try r.readByte();
    if (t == 'i') return Value{
        .Integer = try parseInteger(r, alloc),
    };
    if (t == 'l') return Value{
        .List = try parseList(r, alloc),
    };
    if (t == 'd') return Value{
        .Dictionary = try parseDict(r, alloc),
    };
    return error.BencodeBadDelimiter;
}

fn parseString(r: anytype, alloc: std.mem.Allocator) ![]const u8 {
    const str = try r.readUntilDelimiterAlloc(alloc, ':', max_number_length);
    const len = try std.fmt.parseInt(usize, str, 10);
    var buf = try alloc.alloc(u8, len);
    const l = try r.read(buf);
    return buf[0..l];
}

fn parseInteger(r: anytype, alloc: std.mem.Allocator) !i64 {
    const str = try r.readUntilDelimiterAlloc(alloc, 'e', max_number_length);
    const x = try std.fmt.parseInt(i64, str, 10);
    return x;
}

fn parseList(r: anytype, alloc: std.mem.Allocator) ![]Value {
    var list = std.ArrayList(Value).init(alloc);
    while (true) {
        if (peek(r)) |c| {
            if (c == 'e') {
                _ = try r.readByte();
                return list.toOwnedSlice();
            }
            const v = try parse(r, alloc);
            try list.append(v);
        } else {
            break;
        }
    }
    return error.EndOfStream;
}

fn parseDict(r: anytype, alloc: std.mem.Allocator) !std.StringArrayHashMapUnmanaged(Value) {
    var map = std.StringArrayHashMapUnmanaged(Value){};
    while (true) {
        if (peek(r)) |c| {
            if (c == 'e') {
                _ = try r.readByte();
                return map;
            }
            const k = try parseString(r, alloc);
            const v = try parse(r, alloc);
            try map.put(alloc, k, v);
        } else {
            break;
        }
    }
    return error.EndOfStream;
}
