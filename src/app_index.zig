const std = @import("std");
const apps = @import("apps.zig");
const stats = @import("stats.zig");
const config = @import("config.zig");

pub const App = apps.App;

pub const AppIndex = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    app_paths: []const []const u8 = &.{},
    all: std.ArrayList(App) = .empty,
    matches: std.ArrayList(usize) = .empty,

    pub fn init(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map, app_paths: []const []const u8) !AppIndex {
        return .{
            .arena = arena,
            .io = io,
            .env = env,
            .app_paths = app_paths,
            .all = try apps.discover(arena, io, env, app_paths),
        };
    }

    pub fn refresh(self: *AppIndex) !void {
        // Re-read the config so edits to the configured paths take effect on
        // refresh; keep the existing paths if the config fails to load.
        if (config.load(self.arena, self.io, self.env)) |reloaded| {
            self.app_paths = reloaded.app_paths;
        } else |_| {}
        self.all = try apps.discover(self.arena, self.io, self.env, self.app_paths);
    }

    pub fn search(self: *AppIndex, query_lower: []const u8, launch_stats: stats.Stats) void {
        apps.filter(self.arena, self.all.items, query_lower, &self.matches);
        apps.sortMatchesByLaunchCount(self.all.items, self.matches.items, launch_stats);
    }

    pub fn count(self: AppIndex) usize {
        return self.matches.items.len;
    }

    pub fn appForMatch(self: AppIndex, match_index: usize) ?App {
        if (match_index >= self.matches.items.len) return null;
        return self.all.items[self.matches.items[match_index]];
    }

    pub fn visibleMatchesContainMissingPath(self: AppIndex, scroll_offset: usize, visible_rows: usize) bool {
        for (0..visible_rows) |i| {
            const app = self.appForMatch(scroll_offset + i) orelse return false;
            if (!pathExists(self.io, app.path)) return true;
        }
        return false;
    }

    pub fn longestCommonPrefix(self: AppIndex) ?[]const u8 {
        if (self.matches.items.len == 0) return null;

        var prefix = self.all.items[self.matches.items[0]].name_lower;
        for (self.matches.items[1..]) |app_index| {
            const candidate = self.all.items[app_index].name_lower;
            prefix = prefix[0..commonPrefixLen(prefix, candidate)];
            if (prefix.len == 0) return prefix;
        }
        return prefix;
    }
};

pub fn pathExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.accessAbsolute(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound, error.BadPathName, error.NameTooLong => return false,
        else => return true,
    };
    return true;
}

fn commonPrefixLen(lhs: []const u8, rhs: []const u8) usize {
    const n = @min(lhs.len, rhs.len);
    for (lhs[0..n], rhs[0..n], 0..) |a, b, i| {
        if (a != b) return i;
    }
    return n;
}

test "appForMatch returns null outside match bounds" {
    const index = AppIndex{
        .arena = std.testing.allocator,
        .io = undefined,
        .env = undefined,
    };

    try std.testing.expect(index.appForMatch(0) == null);
}

test "longest common prefix uses matched app names" {
    const test_apps = [_]App{
        .{ .name = "Microsoft Excel", .name_lower = "microsoft excel", .path = "" },
        .{ .name = "Microsoft Word", .name_lower = "microsoft word", .path = "" },
        .{ .name = "Microsoft Teams", .name_lower = "microsoft teams", .path = "" },
    };
    const matches = [_]usize{ 0, 1, 2 };

    const index = AppIndex{
        .arena = std.testing.allocator,
        .io = undefined,
        .env = undefined,
        .all = .{ .items = @constCast(&test_apps) },
        .matches = .{ .items = @constCast(&matches) },
    };

    try std.testing.expectEqualStrings("microsoft ", index.longestCommonPrefix().?);
}

test "longest common prefix returns null without matches" {
    const index = AppIndex{
        .arena = std.testing.allocator,
        .io = undefined,
        .env = undefined,
    };

    try std.testing.expect(index.longestCommonPrefix() == null);
}

test "longest common prefix can narrow to one app" {
    const test_apps = [_]App{
        .{ .name = "Calculator", .name_lower = "calculator", .path = "" },
    };
    const matches = [_]usize{0};

    const index = AppIndex{
        .arena = std.testing.allocator,
        .io = undefined,
        .env = undefined,
        .all = .{ .items = @constCast(&test_apps) },
        .matches = .{ .items = @constCast(&matches) },
    };

    try std.testing.expectEqualStrings("calculator", index.longestCommonPrefix().?);
}
