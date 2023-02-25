const std = @import("std");
const dre = @import("dre.zig");

pub fn Lexer(comptime Token: type, comptime patterns: Patterns(Token)) type {
    return struct {
        s: []const u8,
        start: usize = undefined,
        end: usize = 0,

        const Self = @This();

        pub fn init(s: []const u8) Self {
            return .{ .s = s };
        }

        /// Returns the next token, skipping any ignored tokens.
        /// If there are no more tokens, returns `Token.sentinel`.
        /// If there is no valid token, returns `Token.invalid` and advances by one byte.
        pub fn next(self: *Self) Token {
            // Skip ignored tokens
            while (patterns._ignore.len > 0 and self.match(patterns._ignore)) {}

            self.start = self.end;
            if (self.end == self.s.len) return .sentinel;

            const fields = comptime std.meta.fieldNames(Patterns(Token))[1..];
            @setEvalBranchQuota(fields.len * 1000);
            // OPTIM: merge patterns to avoid backtracking
            inline for (fields) |name| {
                const tok = @field(Token, name);
                const pat = @field(patterns, name);
                if (self.match(pat)) {
                    return tok;
                }
            }

            self.end += 1;
            return .invalid;
        }
        inline fn match(self: *Self, comptime pat: []const u8) bool {
            if (dre.match(pat, self.s[self.end..])) |m| {
                // TODO: tag support?
                self.end += m.len;
                return true;
            } else {
                return false;
            }
        }

        /// Returns the string matched by the last token returned from `next`
        pub fn str(self: Self) []const u8 {
            return self.s[self.start..self.end];
        }
    };
}

pub fn Patterns(comptime Token: type) type {
    if (!@hasField(Token, "invalid")) {
        @compileError("Token enum must have an 'invalid' field for invalid tokens");
    }
    if (!@hasField(Token, "sentinel")) {
        @compileError("Token enum must have a 'sentinel' field for 'end of input'");
    }
    if (@hasField(Token, "_ignore")) {
        @compileError("Token enum must not have an '_ignore' field; this is reserved for ignored tokens");
    }

    const values = std.enums.values(Token);
    var fields: [values.len - 1]std.builtin.Type.StructField = undefined;
    var i = 0;

    fields[i] = .{
        .name = "_ignore",
        .type = []const u8,
        .default_value = @ptrCast(*const anyopaque, &@as([]const u8, "")),
        .is_comptime = false,
        .alignment = @alignOf([]const u8),
    };
    i += 1;

    for (values) |val| {
        if (val == .invalid or val == .sentinel) {
            continue;
        }
        fields[i] = .{
            .name = @tagName(val),
            .type = []const u8,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf([]const u8),
        };
        i += 1;
    }

    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

test "lexer - simple algebra" {
    const Token = enum {
        sin,
        cos,
        tan,

        number,
        ident,

        @"(",
        @")",
        @"+",
        @"*",

        sentinel,
        invalid,
    };
    const L = Lexer(Token, .{
        ._ignore = "[ \t\n]+",

        .sin = "sin",
        .cos = "cos",
        .tan = "tan",

        .number = "[-+]?[0-9]+",
        .ident = "[a-zA-Z_][a-zA-Z0-9_]*",

        .@"(" = "%(",
        .@")" = "%)",
        .@"+" = "%+",
        .@"*" = "%*",
    });

    var toks = L.init("a0 + cos(3) * sin(a1) + -789 + +2");
    const expect = [_]Token{
        .ident,  .@"+", .cos,    .@"(",     .number, .@")",
        .@"*",   .sin,  .@"(",   .ident,    .@")",   .@"+",
        .number, .@"+", .number, .sentinel,
    };
    for (expect) |tok| {
        try std.testing.expectEqual(tok, toks.next());
    }
}
