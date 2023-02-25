const std = @import("std");
const zacc = @import("zacc");
const ast = @import("ast.zig");

pub fn parse(comptime regex: []const u8) ast.Expr {
    comptime var toks = Tokenizer{ .src = regex };
    const expr = Parser.parseComptime(&toks, Context{ .toks = &toks }) catch |e| {
        @compileError(@errorName(e)); // TODO: better error
    };
    return expr.expr;
}

const Token = enum {
    sentinel, // End of string
    invalid, // Invalid token

    @"(",
    @")",
    @"|",
    @"?",
    @"*",
    @"+",

    class, // [abc0-9]
    repeat, // {3,7}
    tag, // <foo>
    char, // Any non-special character (including escapes)
};

const Parser = zacc.Parser(Token,
    \\start = expr $;
    \\expr = expr '|' alt | alt;
    \\alt = elems .tag | elems;
    \\elems = elems elem | elem;
    \\elem = atom repeat | atom;
    \\repeat = '?' | '*' | '+' | .repeat;
    \\atom = .class | .char | group;
    \\group = '(' expr ')';
);

const Context = struct {
    toks: *Tokenizer,

    pub const Result = union {
        expr: ast.Expr,
        alt: ast.Alternative,
        elems: []const ast.Element,
        elem: ast.Element,
        repeat: ast.Repeat,
        atom: ast.Atom,
        tag: []const u8,
        unused: void,
    };

    pub fn nonTerminal(
        comptime _: Context,
        comptime nt: Parser.NonTerminal,
        comptime children: []const Result,
    ) !Result {
        return switch (nt) {
            .start => unreachable,
            .expr => .{
                .expr = if (children.len > 1)
                    children[0].expr ++ .{children[2].alt}
                else
                    &.{children[0].alt},
            },

            .alt => .{ .alt = .{
                .elems = children[0].elems,
                .tag = if (children.len > 1)
                    children[1].tag
                else
                    null,
            } },

            .elems => .{
                .elems = if (children.len > 1) blk: {
                    const elems = children[0].elems;
                    const elem = children[1].elem;
                    const last = elems[elems.len - 1];

                    // Optimization to join adjacent non-repeated strings
                    if (last.atom == .string and last.repeat.min == 1 and last.repeat.max == 1 and
                        elem.atom == .string and elem.repeat.min == 1 and elem.repeat.max == 1)
                    {
                        const s = [_]ast.Element{.{
                            .atom = .{
                                .string = last.atom.string ++ elem.atom.string,
                            },
                            .repeat = .{
                                .min = 1,
                                .max = 1,
                            },
                        }};
                        // Needed to work around [0]T being unusable at comptime for some reason??
                        if (elems.len > 1) {
                            break :blk elems[0 .. elems.len - 1] ++ s;
                        } else {
                            break :blk &s;
                        }
                    }

                    break :blk elems ++ .{elem};
                } else &.{children[0].elem},
            },

            .elem => .{ .elem = .{
                .atom = children[0].atom,
                .repeat = if (children.len > 1)
                    children[1].repeat
                else
                    .{},
            } },
            .repeat, .atom => children[0],
            .group => blk: {
                const e = children[1].expr;
                break :blk .{ .atom = .{
                    .expr = &e,
                } };
            },
        };
    }

    pub fn terminal(comptime self: Context, comptime t: Token) !Result {
        return switch (t) {
            .@"?" => .{ .repeat = .{ .min = 0, .max = 1 } },
            .@"*" => .{ .repeat = .{ .min = 0, .max = 0 } },
            .@"+" => .{ .repeat = .{ .min = 1, .max = 0 } },
            .repeat => .{ .repeat = try self.toks.repeat() },

            .tag => .{ .tag = self.toks.tag() },

            .class => .{ .atom = .{
                .class = try self.toks.class(),
            } },
            .char => .{ .atom = .{
                .string = try self.toks.char(),
            } },

            else => .{ .unused = {} },
        };
    }
};

test "parse - simple expression" {
    const expr = comptime parse("ab(c|de?<hi>)*|x[yz0-9]{2,7}");
    std.debug.print("{}\n", .{ast.fmtRegex(expr)});
}

const Tokenizer = struct {
    src: []const u8,
    idx: usize = 0,
    start: usize = undefined,

    pub fn next(self: *Tokenizer) Token {
        return self.nextInternal() catch .sentinel;
    }

    fn nextInternal(self: *Tokenizer) !Token {
        self.start = self.idx;
        return switch (try self.pop()) {
            '(' => .@"(",
            ')' => .@")",
            '|' => .@"|",
            '?' => .@"?",
            '*' => .@"*",
            '+' => .@"+",

            '[' => while (true) {
                switch (try self.pop()) {
                    '\\' => _ = try self.pop(),
                    ']' => break .class,
                    else => {},
                }
            },
            ']' => .invalid,

            '{' => while (true) {
                switch (try self.pop()) {
                    '}' => break .repeat,
                    '0'...'9', ',' => {},
                    else => break .invalid,
                }
            },
            '}' => .invalid,

            '<' => while (true) {
                switch (try self.pop()) {
                    '>' => break .tag,
                    'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
                    else => break .invalid,
                }
            },
            '>' => .invalid,

            '\\' => switch (try self.pop()) {
                '(', ')', '|', '?', '*', '+', '[', ']', '{', '}', '\\' => .char,
                // TODO: unicode escapes, hex escapes, common classes, etc
                else => .invalid,
            },

            else => |c| {
                const len = std.unicode.utf8ByteSequenceLength(c) catch return .invalid;
                self.idx += len - 1;
                return .char;
            },
        };
    }

    fn pop(self: *Tokenizer) !u8 {
        if (self.idx == self.src.len) {
            return error.EndOfInput;
        }
        defer self.idx += 1;
        return self.src[self.idx];
    }

    inline fn str(self: Tokenizer) []const u8 {
        return self.src[self.start..self.idx];
    }

    fn repeat(self: Tokenizer) !ast.Repeat {
        const s = self.str();
        std.debug.assert(s[0] == '{' and s[s.len - 1] == '}');
        const rep = s[1 .. s.len - 1];
        if (rep.len == 1) return error.InvalidRepetition; // use * or {0,}
        const comma = std.mem.indexOfScalar(u8, rep, ',') orelse return error.InvalidRepetition;
        return .{
            .min = if (comma == 0)
                0
            else
                try std.fmt.parseUnsigned(u32, rep[0..comma], 10),
            .max = if (comma == rep.len - 1)
                0
            else
                try std.fmt.parseUnsigned(u32, rep[comma + 1 ..], 10),
        };
    }

    fn tag(self: Tokenizer) []const u8 {
        const s = self.str();
        std.debug.assert(s[0] == '<' and s[s.len - 1] == '>');
        return s[1 .. s.len - 1];
    }

    fn class(self: Tokenizer) !ast.Class {
        const s = self.str();
        std.debug.assert(s[0] == '[' and s[s.len - 1] == ']');
        const invert = s[1] == '^';
        const cls = s[1 + @boolToInt(invert) .. s.len - 1];
        if (cls.len == 0 and !invert) return error.InvalidClass; // non-inverted empty classes are useless

        var set = ast.Class.initEmpty();
        var range = false;
        for (cls, 0..) |c, i| {
            if (c >= 128) return error.InvalidClass; // TODO: unicode support
            if (range) {
                set.setRangeValue(.{ .start = cls[i - 2], .end = c }, true);
                range = false;
            } else if (c == '-' and i > 0 and i < cls.len - 1) {
                range = true;
            } else {
                set.set(c);
            }
        }

        if (invert) set.toggleAll();
        return set;
    }

    fn char(self: Tokenizer) ![]const u8 {
        const s = self.str();
        if (s[0] == '\\') {
            std.debug.assert(s.len == 2);
            return s[1..];
        }
        _ = try std.unicode.utf8Decode(self.str());
        return s;
    }
};
