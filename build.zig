const std = @import("std");
const mach = @import("mach");

// zig 0.12.0-dev.3180+83e578a18

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_dep = b.dependency("mach", .{
        .target = target,
        .optimize = optimize,
        // Since we're only using @import("mach").core, we can specify this to avoid
        // pulling in unneccessary dependencies.
        .core = true,
    });

    const zig_imgui_dep = b.dependency(
        "zig_imgui",
        .{ .target = target, .optimize = optimize },
    );

    const imgui_module = zig_imgui_dep.module("zig-imgui");
    imgui_module.addImport("mach", mach_dep.module("mach"));

    const app = try mach.CoreApp.init(b, mach_dep.builder, .{
        .name = "myapp",
        .src = "src/main.zig",
        .target = target,
        .optimize = optimize,
        .mach_mod = mach_dep.module("mach"),
        .deps = &.{
            .{ .name = "zig-imgui", .module = imgui_module },
        },
    });
    app.compile.linkLibrary(zig_imgui_dep.artifact("imgui"));

    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
