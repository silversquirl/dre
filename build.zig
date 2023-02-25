const std = @import("std");

pub fn build(b: *std.Build) void {
    const zacc = b.dependency("zacc", .{}).module("zacc");

    b.addModule(.{
        .name = "dre",
        .source_file = .{ .path = "src/dre.zig" },
        .dependencies = &.{
            .{ .name = "zacc", .module = zacc },
        },
    });

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/dre.zig" },
    });
    tests.addModule("zacc", zacc);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
