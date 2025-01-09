const std = @import("std");

pub const Value = union(enum) {
    String: []const u8,
    Integer: i64,
    List: []const Value,
    Dictionary: std.StringArrayHashMapUnmanaged(Value),

    pub fn deinit(self: *const Value, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .String => |s| alloc.free(s),
            .Integer => {},
            .List => |l| {
                for (l) |*v| v.deinit(alloc);
                alloc.free(l);
            },
            .Dictionary => |*d| {
                for (d.keys()) |k| alloc.free(k);
                for (d.values()) |*v| v.deinit(alloc);
                @constCast(d).deinit(alloc);
            },
        }
    }

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

    fn getT(self: Value, key: []const u8, comptime tag: std.meta.FieldEnum(Value)) ?std.meta.FieldType(Value, tag) {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == tag) @field(ret, @tagName(tag)) else null;
    }

    pub fn getD(self: Value, key: []const u8) ?Value {
        std.debug.assert(self == .Dictionary);
        const ret = self.Dictionary.get(key) orelse return null;
        return if (ret == .Dictionary) ret else null;
    }

    pub fn getL(self: Value, key: []const u8) ?[]const Value {
        return self.getT(key, .List);
    }

    pub fn getS(self: Value, key: []const u8) ?[]const u8 {
        return self.getT(key, .String);
    }

    pub fn getI(self: Value, key: []const u8) ?i64 {
        return self.getT(key, .Integer);
    }

    pub fn getU(self: Value, key: []const u8) ?u64 {
        return @intCast(self.getI(key) orelse return null);
    }
};

const max_number_length = 25;

pub fn parseFixed(alloc: std.mem.Allocator, input: []const u8) !Value {
    var fbs = std.io.fixedBufferStream(input);
    return parse(fbs.reader(), alloc);
}

pub fn parse(r: anytype, alloc: std.mem.Allocator) !Value {
    var pr = peekableReader(r);
    return parseInner(&pr, alloc);
}

fn parseInner(pr: anytype, alloc: std.mem.Allocator) anyerror!Value {
    const pc = (try pr.peek()) orelse return error.EndOfStream;
    if (pc >= '0' and pc <= '9') return Value{
        .String = try parseString(pr, alloc),
    };

    const t = try pr.reader().readByte();
    if (t == 'i') return Value{
        .Integer = try parseInteger(pr, alloc),
    };
    if (t == 'l') return Value{
        .List = try parseList(pr, alloc),
    };
    if (t == 'd') return Value{
        .Dictionary = try parseDict(pr, alloc),
    };
    return error.BencodeBadDelimiter;
}

fn parseString(pr: anytype, alloc: std.mem.Allocator) ![]const u8 {
    const str = try pr.reader().readUntilDelimiterAlloc(alloc, ':', max_number_length);
    defer alloc.free(str);
    const len = try std.fmt.parseInt(usize, str, 10);
    var buf = try alloc.alloc(u8, len);
    const l = try pr.reader().readAll(buf);
    return buf[0..l];
}

fn parseInteger(pr: anytype, alloc: std.mem.Allocator) !i64 {
    const str = try pr.reader().readUntilDelimiterAlloc(alloc, 'e', max_number_length);
    defer alloc.free(str);
    const x = try std.fmt.parseInt(i64, str, 10);
    return x;
}

fn parseList(pr: anytype, alloc: std.mem.Allocator) ![]Value {
    var list = std.ArrayList(Value).init(alloc);
    errdefer list.deinit();
    while (true) {
        if (try pr.peek()) |c| {
            if (c == 'e') {
                pr.buf = null;
                return list.toOwnedSlice();
            }
            const v = try parseInner(pr, alloc);
            try list.append(v);
        } else {
            break;
        }
    }
    return error.EndOfStream;
}

fn parseDict(pr: anytype, alloc: std.mem.Allocator) !std.StringArrayHashMapUnmanaged(Value) {
    var map = std.StringArrayHashMapUnmanaged(Value){};
    errdefer map.deinit(alloc);
    errdefer for (map.keys()) |k| alloc.free(k);
    errdefer for (map.values()) |v| v.deinit(alloc);
    while (true) {
        if (try pr.peek()) |c| {
            if (c == 'e') {
                pr.buf = null;
                return map;
            }
            const k = try parseString(pr, alloc);
            const v = try parseInner(pr, alloc);
            try map.put(alloc, k, v);
        } else {
            break;
        }
    }
    return error.EndOfStream;
}

//
//

fn peekableReader(reader: anytype) PeekableReader(@TypeOf(reader)) {
    return .{ .child_reader = reader };
}

fn PeekableReader(comptime ReaderType: type) type {
    return struct {
        child_reader: ReaderType,
        buf: ?u8 = null,

        const Self = @This();
        pub const Error = ReaderType.Error;
        pub const Reader = std.io.GenericReader(*Self, Error, read);

        fn read(self: *Self, dest: []u8) Error!usize {
            if (self.buf) |c| {
                dest[0] = c;
                self.buf = null;
                return 1;
            }
            return self.child_reader.read(dest);
        }

        pub fn reader(self: *Self) Reader {
            return .{ .context = self };
        }

        pub fn peek(self: *Self) !?u8 {
            if (self.buf) |_| {
                return self.buf.?;
            }
            self.buf = self.child_reader.readByte() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };
            return self.buf.?;
        }
    };
}
