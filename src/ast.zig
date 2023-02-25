const std = @import("std");

pub const Expr = []const Alternative;
pub const Alternative = struct {
    elems: []const Element,
    tag: ?[]const u8,
};
pub const Element = struct {
    atom: Atom,
    repeat: Repeat,
};
pub const Repeat = struct {
    min: u32 = 1,
    max: u32 = 1, // 0 = no maximum
};
pub const Atom = union(enum) {
    class: Class,
    string: []const u8,
    expr: *const Expr,
};
pub const Class = std.StaticBitSet(128); // TODO: unicode

pub const not_newline = blk: {
    var set = Class.initFull();
    set.unset('\n');
    set.unset('\r');
    break :blk set;
};
pub const special = "()|?*+.[]{}%";

pub fn fmtRegex(expr: Expr) std.fmt.Formatter(formatRegex) {
    return .{ .data = expr };
}
fn formatRegex(expr: Expr, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
    for (expr, 0..) |alt, i| {
        if (i > 0) {
            try w.writeAll("|");
        }
        for (alt.elems) |elem| {
            switch (elem.atom) {
                .class => |cls| if (cls.eql(not_newline)) {
                    try w.writeAll(".");
                } else {
                    try w.writeAll("[");

                    var it = cls.iterator(.{});
                    var start: u7 = undefined;
                    var count: u7 = 0;
                    while (it.next()) |c_usize| {
                        const c = @intCast(u7, c_usize);
                        if (count > 0 and start == c - count) {
                            count += 1;
                            continue;
                        } else if (count > 3) {
                            try w.print("{c}-{c}", .{ start, start + count - 1 });
                        } else if (count > 0) {
                            for (start..start + count) |x| {
                                try w.writeByte(@intCast(u7, x));
                            }
                        }
                        start = c;
                        count = 1;
                    }

                    if (count > 3) {
                        try w.print("{c}-{c}", .{ start, start + count - 1 });
                    } else if (count > 0) {
                        for (start..start + count) |x| {
                            try w.writeByte(@intCast(u7, x));
                        }
                    }

                    try w.writeAll("]");
                },
                .string => |s| for (s) |c| {
                    if (std.mem.indexOfScalar(u8, special, c) != null) {
                        try w.writeByte('%');
                    }
                    try w.writeByte(c);
                },
                .expr => |e| try w.print("({})", .{fmtRegex(e.*)}),
            }
            if (elem.atom == .string and elem.atom.string.len != 1) {
                std.debug.assert(elem.repeat.min == 1);
                std.debug.assert(elem.repeat.max == 1);
            }

            const r = elem.repeat;
            if (r.min == 0 and r.max == 0) {
                try w.writeAll("*");
            } else if (r.min == 1 and r.max == 0) {
                try w.writeAll("+");
            } else if (r.min == 0 and r.max == 1) {
                try w.writeAll("?");
            } else if (r.min == 1 and r.max == 1) {
                // No repetition
            } else if (r.min == 0) {
                try w.print("{{,{}}}", .{r.max});
            } else if (r.max == 0) {
                try w.print("{{{},}}", .{r.min});
            } else {
                try w.print("{{{},{}}}", .{ r.min, r.max });
            }
        }

        if (alt.tag) |tag| {
            try w.print("<{s}>", .{tag});
        }
    }
}
