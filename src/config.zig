const std = @import("std");
const keymap = @import("keymap.zig");

const config_file_name = "zlaunch.json";

const default_config =
    \\{
    \\  "version": 1,
    \\  "hotkey": "cmd-space"
    \\}
    \\
;

pub const Config = struct {
    hotkey: keymap.Key = keymap.default_show_launcher,
};

const FileConfig = struct {
    version: u32 = 1,
    hotkey: []const u8 = "cmd-space",
};

pub fn load(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Config {
    const paths = try Paths.init(arena, env);
    try ensureFile(io, paths);

    const data = std.Io.Dir.readFileAlloc(.cwd(), io, paths.file, arena, .limited(4096)) catch {
        return .{};
    };
    const parsed = std.json.parseFromSliceLeaky(FileConfig, arena, data, .{
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .use_last,
    }) catch {
        return .{};
    };

    return .{
        .hotkey = keymap.parse(parsed.hotkey) orelse keymap.default_show_launcher,
    };
}

fn ensureFile(io: std.Io, paths: Paths) !void {
    try std.Io.Dir.createDirPath(.cwd(), io, paths.dir);
    var file = std.Io.Dir.createFileAbsolute(io, paths.file, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, default_config);
}

const Paths = struct {
    dir: []const u8,
    file: []const u8,

    fn init(arena: std.mem.Allocator, env: *std.process.Environ.Map) !Paths {
        const home = env.get("HOME") orelse return error.HomeNotSet;
        const dir = try std.fs.path.join(arena, &.{ home, ".config", "zlaunch" });
        const file = try std.fs.path.join(arena, &.{ dir, config_file_name });
        return .{ .dir = dir, .file = file };
    }
};

test "config paths live under home config directory" {
    var env = std.process.EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/Users/example");

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const paths = try Paths.init(arena_state.allocator(), &env);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch", paths.dir);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch/zlaunch.json", paths.file);
}

test "load parsed config hotkey from json" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try std.json.parseFromSliceLeaky(FileConfig, arena_state.allocator(), "{\"hotkey\":\"ctrl-option-m\"}", .{
        .ignore_unknown_fields = true,
    });

    const hotkey = keymap.parse(parsed.hotkey).?;
    try std.testing.expectEqual(@as(u32, 0x2e), hotkey.carbon_key_code);
}
