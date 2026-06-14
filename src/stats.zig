const std = @import("std");

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
    paths: Paths = .{},
    launches: LaunchMap = .empty,

    pub fn load(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !Stats {
        const paths = try Paths.init(arena, env);
        try ensureFile(io, paths);

        const data = std.Io.Dir.readFileAlloc(.cwd(), io, paths.file, arena, .limited(1024 * 1024)) catch {
            return empty(arena, io, paths);
        };
        const parsed = std.json.parseFromSliceLeaky(FileStats, arena, data, .{
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .use_last,
            .allocate = .alloc_always,
        }) catch {
            return empty(arena, io, paths);
        };

        return .{
            .arena = arena,
            .io = io,
            .paths = paths,
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
        try std.Io.Dir.createDirPath(.cwd(), self.io, self.paths.dir);

        var out: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer out.deinit();
        try std.json.Stringify.value(FileStats{
            .version = 1,
            .launches = .{ .map = self.launches },
        }, .{ .whitespace = .indent_2 }, &out.writer);
        try out.writer.writeByte('\n');

        var file = try std.Io.Dir.createFileAbsolute(self.io, self.paths.file, .{});
        defer file.close(self.io);
        try file.writeStreamingAll(self.io, out.writer.buffered());
    }

    fn empty(arena: std.mem.Allocator, io: std.Io, paths: Paths) Stats {
        return .{
            .arena = arena,
            .io = io,
            .paths = paths,
        };
    }
};

fn ensureFile(io: std.Io, paths: Paths) !void {
    try std.Io.Dir.createDirPath(.cwd(), io, paths.dir);
    var file = std.Io.Dir.createFileAbsolute(io, paths.file, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
    defer file.close(io);
    try file.writeStreamingAll(io, default_stats);
}

const Paths = struct {
    dir: []const u8 = "",
    file: []const u8 = "",

    fn init(arena: std.mem.Allocator, env: *std.process.Environ.Map) !Paths {
        const home = env.get("HOME") orelse return error.HomeNotSet;
        const dir = try std.fs.path.join(arena, &.{ home, ".config", "zlaunch" });
        const file = try std.fs.path.join(arena, &.{ dir, stats_file_name });
        return .{ .dir = dir, .file = file };
    }
};

test "stats paths live under home config directory" {
    var env = std.process.EnvMap.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/Users/example");

    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const paths = try Paths.init(arena_state.allocator(), &env);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch", paths.dir);
    try std.testing.expectEqualStrings("/Users/example/.config/zlaunch/stats.json", paths.file);
}

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
