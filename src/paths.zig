const std = @import("std");

pub const ConfigFile = struct {
    dir: []const u8,
    file: []const u8,
};

pub fn configFile(arena: std.mem.Allocator, env: *std.process.Environ.Map, file_name: []const u8) !ConfigFile {
    const home = env.get("HOME") orelse return error.HomeNotSet;
    const dir = try std.fs.path.join(arena, &.{ home, ".config", "zlaunch" });
    const file = try std.fs.path.join(arena, &.{ dir, file_name });
    return .{ .dir = dir, .file = file };
}

pub fn ensureFile(io: std.Io, file: ConfigFile, contents: []const u8) !void {
    try std.Io.Dir.createDirPath(.cwd(), io, file.dir);
    var handle = std.Io.Dir.createFileAbsolute(io, file.file, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer handle.close(io);
    try handle.writeStreamingAll(io, contents);
}

test "config files live under home config directory" {
    var env = std.process.EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/Users/example");

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const config = try configFile(arena_state.allocator(), &env, "zlaunch.json");
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch", config.dir);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch/zlaunch.json", config.file);

    const stats = try configFile(arena_state.allocator(), &env, "stats.json");
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch", stats.dir);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch/stats.json", stats.file);
}
