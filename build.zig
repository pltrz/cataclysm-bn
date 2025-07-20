const std = @import("std");

pub fn build(b: *std.Build) !void {
    const GraphicsMode = enum { curses, tiles };
    const graphics = b.option(GraphicsMode, "graphics", "Build curses or tiles version.") orelse GraphicsMode.curses;
    const SaveDirMode = enum { xdg, home };
    const save_dir = b.option(SaveDirMode, "save_dir", "Directory to use for save and config files.") orelse SaveDirMode.xdg;
    const sound = b.option(bool, "sound", "Support for in-game sounds & music.") orelse false;
    const backtrace = b.option(bool, "backtrace", "Support for printing stack backtraces on crash.") orelse false;
    const libbacktrace = b.option(bool, "libbacktrace", "Print backtrace with libbacktrace.") orelse false;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var aa = std.heap.ArenaAllocator.init(gpa.allocator());
    defer aa.deinit();
    const allocator = aa.allocator();

    const argv = [_][]const u8{ "git", "describe", "--tags", "--always", "--dirty", "--match", "[0-9A-Z]*.[0-9A-Z]*" };
    const proc = try std.process.Child.run(.{
        .argv = &argv,
        .allocator = allocator,
    });

    const version_string = std.mem.trimRight(u8, proc.stdout, "\r\n");
    const version_h_path = "src/version.h";
    const version_h_content = try std.fmt.allocPrint(
        allocator,
        "#define VERSION \"{s}\"\n",
        .{version_string},
    );
    var version_file = try std.fs.cwd().createFile(version_h_path, .{ .truncate = true, .read = false });
    defer version_file.close();
    try version_file.writeAll(version_h_content);

    var src_files = std.ArrayList([]const u8).init(allocator);

    var dir = try std.fs.cwd().openDir("./src", .{ .iterate = true });
    defer dir.close();

    var it_src = dir.iterate();
    while (try it_src.next()) |entry| {
        if ((entry.kind == .file) and (std.mem.endsWith(u8, entry.name, ".cpp"))) {
            const full_path = try std.fmt.allocPrint(allocator, "./src/{s}", .{entry.name});
            try src_files.append(full_path);
        }
    }

    const exe = b.addExecutable(.{
        .name = if (graphics == GraphicsMode.tiles) "cataclysm-bn-tiles" else "cataclysm-bn",
        .target = target,
        .optimize = optimize,
    });
    var cpp_flags = std.ArrayList([]const u8).init(allocator);
    try cpp_flags.append("-std=c++23");
    try cpp_flags.append("-ffast-math");
    if (graphics == GraphicsMode.tiles) {
        try cpp_flags.append("-DTILES");
        if (sound) try cpp_flags.append("-DSDL_SOUND");
    }
    if (backtrace) {
        try cpp_flags.append("-DBACKTRACE");
        // exe.addLinkArgs("-rdynamic"); TODO: how the fuck to do this?
        if (libbacktrace) {
            try cpp_flags.append("-DLIBBACKTRACE");
            exe.linkSystemLibrary("backtrace");
        }
    }
    if (sound and (graphics == GraphicsMode.curses)) @panic("sound requires tiles.");
    switch (save_dir) {
        SaveDirMode.xdg => try cpp_flags.append("-DUSE_XDG_DIR"),
        SaveDirMode.home => try cpp_flags.append("-DUSE_HOME_DIR"),
    }

    exe.addCSourceFiles(.{
        .files = src_files.items,
        .flags = cpp_flags.items,
    });

    exe.addIncludePath(b.path("./src/"));

    exe.linkLibCpp();
    if (graphics == GraphicsMode.tiles) {
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("SDL2_image");
        exe.linkSystemLibrary("SDL2_ttf");
        if (sound) {
            exe.linkSystemLibrary("SDL2_mixer");
        }
    }
    exe.linkSystemLibrary("ncurses");
    exe.linkSystemLibrary("sqlite3");
    exe.linkSystemLibrary("lua");
    exe.linkSystemLibrary("z");

    b.installArtifact(exe);
    b.installDirectory(.{ .source_dir = b.path("./data/font/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/font/" });
    b.installDirectory(.{ .source_dir = b.path("./data/json/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/json/" });
    b.installDirectory(.{ .source_dir = b.path("./data/mods/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/mods/" });
    b.installDirectory(.{ .source_dir = b.path("./data/names/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/names/" });
    b.installDirectory(.{ .source_dir = b.path("./data/raw/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/raw/" });
    b.installDirectory(.{ .source_dir = b.path("./data/motd/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/motd/" });
    b.installDirectory(.{ .source_dir = b.path("./data/credits/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/credits/" });
    b.installDirectory(.{ .source_dir = b.path("./data/title/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/title/" });
    b.installDirectory(.{ .source_dir = b.path("./data/help/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/help/" });
    b.installDirectory(.{ .source_dir = b.path("./data/sound/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/sound/" });
    b.installDirectory(.{ .source_dir = b.path("./gfx/"), .install_dir = .prefix, .install_subdir = "share/cataclysm-bn/gfx" });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
