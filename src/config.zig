const std = @import("std");
const keymap = @import("keymap.zig");
const paths = @import("paths.zig");

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
