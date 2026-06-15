const std = @import("std");
const paths = @import("paths.zig");

const stats_file_name = "stats.json";

const default_stats =
    \\{
    \\  "version": 1,
    \\  "launches": {}
    \\}
    \\
;

const LaunchMap = std.StringArrayHashMapUnmanaged(u64);
const JsonLaunchMap = std.json.ArrayHashMap(u64);

const FileStats = struct {
    version: u32 = 1,
    launches: JsonLaunchMap = .{},
};

pub const Stats = struct {
    arena: std.mem.Allocator = undefined,
    io: std.Io = undefined,
    config_file: paths.ConfigFile = .{ .dir = "", .file = "" },
    launches: LaunchMap = .empty,

    pub fn load(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Stats {
        const config_file = try paths.configFile(arena, env, stats_file_name);
        try paths.ensureFile(io, config_file, default_stats);

        const data = std.Io.Dir.readFileAlloc(.cwd(), io, config_file.file, arena, .limited(1024 * 1024)) catch {
            return empty(arena, io, config_file);
        };
        const parsed = std.json.parseFromSliceLeaky(FileStats, arena, data, .{
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .use_last,
            .allocate = .alloc_always,
        }) catch {
            return empty(arena, io, config_file);
        };

        return .{
            .arena = arena,
            .io = io,
            .config_file = config_file,
            .launches = parsed.launches.map,
        };
    }

    pub fn count(self: Stats, app_path: []const u8) u64 {
        return self.launches.get(app_path) orelse 0;
    }

    pub fn recordLaunch(self: *Stats, app_path: []const u8) !void {
        try self.increment(app_path);
        try self.save();
    }

    fn increment(self: *Stats, app_path: []const u8) !void {
        const entry = try self.launches.getOrPut(self.arena, app_path);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }

    fn save(self: Stats) !void {
        try std.Io.Dir.createDirPath(.cwd(), self.io, self.config_file.dir);

        var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer out.deinit();
        try std.json.Stringify.value(FileStats{
            .version = 1,
            .launches = .{ .map = self.launches },
        }, .{ .whitespace = .indent_2 }, &out.writer);
        try out.writer.writeByte('\n');

        var file = try std.Io.Dir.createFileAbsolute(self.io, self.config_file.file, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, out.writer.buffered());
    }

    fn empty(arena: std.mem.Allocator, io: std.Io, config_file: paths.ConfigFile) Stats {
        return .{
            .arena = arena,
            .io = io,
            .config_file = config_file,
        };
    }
};

test "stats count defaults to zero and increments by path" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var usage_stats = Stats{ .arena = arena_state.allocator() };
    try std.testing.expectEqual(@as(u64, 0), usage_stats.count("/Applications/Safari.app"));

    try usage_stats.increment("/Applications/Safari.app");
    try usage_stats.increment("/Applications/Safari.app");
    try usage_stats.increment("/Applications/Mail.app");

    try std.testing.expectEqual(@as(u64, 2), usage_stats.count("/Applications/Safari.app"));
    try std.testing.expectEqual(@as(u64, 1), usage_stats.count("/Applications/Mail.app"));
}

test "stats json parses launch counts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const parsed = try std.json.parseFromSliceLeaky(FileStats, arena_state.allocator(),
        \\{"version":1,"launches":{"/Applications/Safari.app":3}}
    , .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });

    const usage_stats = Stats{ .launches = parsed.launches.map };
    try std.testing.expectEqual(@as(u64, 3), usage_stats.count("/Applications/Safari.app"));
    try std.testing.expectEqual(@as(u64, 0), usage_stats.count("/Applications/Mail.app"));
}
