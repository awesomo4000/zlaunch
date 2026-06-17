const std = @import("std");
const keymap = @import("keymap.zig");
const paths = @import("paths.zig");

const config_file_name = "zlaunch.json";

pub const default_app_paths = [_][]const u8{
    "/Applications",
    "/Applications/Utilities",
    "/System/Applications",
    "/System/Applications/Utilities",
    "~/Applications",
    "~/Applications/Chrome Apps.localized",
};

const default_config =
    \\{
    \\  "version": 1,
    \\  "hotkey": "ctrl-space",
    \\  "paths": [
    \\    "/Applications",
    \\    "/Applications/Utilities",
    \\    "/System/Applications",
    \\    "/System/Applications/Utilities",
    \\    "~/Applications",
    \\    "~/Applications/Chrome Apps.localized"
    \\  ]
    \\}
    \\
;

pub const Config = struct {
    hotkey: keymap.Key = keymap.default_show_launcher,
    app_paths: []const []const u8 = default_app_paths[0..],
};

const FileConfig = struct {
    version: u32 = 1,
    hotkey: []const u8 = "ctrl-space",
    paths: ?[]const []const u8 = null,
};

pub fn load(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Config {
    const config_path = try paths.configFile(arena, env, config_file_name);
    try paths.ensureFile(io, config_path, default_config);

    const data = std.Io.Dir.readFileAlloc(.cwd(), io, config_path.file, arena, .limited(4096)) catch {
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
        .app_paths = parsed.paths orelse default_app_paths[0..],
    };
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

test "load parsed config paths from json" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try std.json.parseFromSliceLeaky(FileConfig, arena_state.allocator(), "{\"paths\":[\"/tmp/Apps\",\"/opt/Apps\"]}", .{
        .ignore_unknown_fields = true,
    });

    const configured_paths = parsed.paths.?;
    try std.testing.expectEqual(@as(usize, 2), configured_paths.len);
    try std.testing.expectEqualStrings("/tmp/Apps", configured_paths[0]);
    try std.testing.expectEqualStrings("/opt/Apps", configured_paths[1]);
}
