const std = @import("std");

pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");

pub const parse = parser.parse;

// TODO: stream support
pub fn match(comptime regex: []const u8, str: []const u8) ?Match(parse(regex)) {
    return matchAst(parse(regex), str);
}
pub fn matchAst(comptime expr: ast.Expr, str: []const u8) ?Match(expr) {
    return matchExpr(Match(expr), expr, str);
}
inline fn matchExpr(comptime M: type, comptime expr: ast.Expr, str: []const u8) ?M {
    comptime _ = checkDeterminism(expr);
    inline for (expr) |alt| {
        if (matchAlt(M, alt, str)) |m| {
            return m;
        }
    }
    return null;
}
inline fn matchAlt(comptime M: type, comptime alt: ast.Alternative, str: []const u8) ?M {
    var m: M = .{ .len = 0 };
    inline for (alt.elems) |elem| {
        // OPTIM: maybe special case some common repetitions? look at generated code
        var rep: u32 = 0;
        while (elem.repeat.max == 0 or rep < elem.repeat.max) : (rep += 1) {
            const m2 = matchAtom(M, elem.atom, str[m.len..]) orelse break;
            m.len += m2.len;
            if (m2.tag) |t| m.tag = t;
        }
        if (rep < elem.repeat.min) {
            return null;
        }
    }
    if (alt.tag) |t| {
        m.tag = @field(M.Tag, t);
    }
    return m;
}
inline fn matchAtom(comptime M: type, comptime atom: ast.Atom, str: []const u8) ?M {
    switch (atom) {
        .class => |c| {
            if (str.len == 0 or !c.isSet(str[0])) {
                return null;
            }
            return .{ .len = 1 };
        },
        .string => |s| {
            if (!std.mem.startsWith(u8, str, s)) {
                return null;
            }
            return .{ .len = s.len };
        },
        .expr => |e| return matchExpr(M, e.*, str),
    }
}

fn checkDeterminism(comptime expr: ast.Expr) std.StaticBitSet(256) {
    comptime var set = std.StaticBitSet(256).initEmpty();
    comptime for (expr) |alt| {
        var i: usize = 0;
        for (alt.elems) |elem| {
            var alt_set = std.StaticBitSet(256).initEmpty();
            switch (elem.atom) {
                .class => |c| {
                    var it = c.iterator(.{});
                    while (it.next()) |x| {
                        alt_set.set(x);
                    }
                },
                .string => |s| alt_set.set(s[0]),
                .expr => |e| alt_set = checkDeterminism(e.*),
            }

            const isect = set.intersectWith(alt_set);
            if (isect.count() > 0) {
                @compileError(std.fmt.comptimePrint(
                    "Regex is not deterministic: multiple paths for '{'}' (and {} others)",
                    .{
                        std.zig.fmtEscapes(&.{@intCast(u8, isect.findFirstSet().?)}),
                        isect.count() - 1,
                    },
                ));
            }
            set.setUnion(alt_set);

            i += 1;

            if (elem.repeat.min > 0) {
                break;
            }
        }

        for (alt.elems[i..]) |elem| {
            if (elem.atom == .expr) {
                _ = checkDeterminism(elem.atom.expr.*);
            }
        }
    };
    return set;
}

pub fn Match(comptime expr: ast.Expr) type {
    return struct {
        len: usize,
        tag: ?Tag = null,

        const tag_fields = tagFields(expr);
        pub const Tag = @Type(.{ .Enum = .{
            .tag_type = std.math.IntFittingRange(0, tag_fields.len),
            .fields = tag_fields,
            .decls = &.{},
            .is_exhaustive = true,
        } });
    };
}
fn tagFields(comptime expr: ast.Expr) []const std.builtin.Type.EnumField {
    var fields: []const std.builtin.Type.EnumField = &.{};
    for (expr) |alt| {
        for (alt.elems) |elem| {
            if (elem.atom == .expr) {
                fields = fields ++ tagFields(elem.atom.expr.*);
            }
        }
        if (alt.tag) |tag| {
            fields = fields ++ .{.{
                .name = tag,
                .value = fields.len,
            }};
        }
    }
    return fields;
}

comptime {
    std.testing.refAllDecls(parser);
}

test "match - simple expression" {
    const regex = "ab(c|de?<hi>)*|x[yz0-9]{2,7}";

    {
        const m = match(regex, "abcccfoo") orelse return error.NoMatch;
        try std.testing.expectEqual(@as(usize, 5), m.len);
        try std.testing.expect(m.tag == null);
    }
    {
        const m = match(regex, "abdeddededdfoo") orelse return error.NoMatch;
        try std.testing.expectEqual(@as(usize, 11), m.len);
        try std.testing.expect(m.tag != null and m.tag.? == .hi);
    }
}

test "match - determinism" {
    const regex = "[ab][ab]*";

    const m = match(regex, "abab") orelse return error.NoMatch;
    try std.testing.expectEqual(@as(usize, 4), m.len);
}

test "match - escapes" {
    const regex = "%*%?[^%]]";

    {
        const m = match(regex, "*?3") orelse return error.NoMatch;
        try std.testing.expectEqual(@as(usize, 3), m.len);
    }
    try std.testing.expect(match(regex, "*?]") == null);
}
