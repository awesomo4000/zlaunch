const std = @import("std");

pub const App = struct {
    name: []const u8,
    name_lower: []const u8,
    path: []const u8,
};

pub fn discover(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map) !std.ArrayList(App) {
    var list: std.ArrayList(App) = .empty;
    try discoverDir(arena, io, &list, "/Applications");
    discoverDir(arena, io, &list, "/Applications/Utilities") catch {};
    discoverDir(arena, io, &list, "/System/Applications") catch {};
    discoverDir(arena, io, &list, "/System/Applications/Utilities") catch {};
    discoverUserApplications(arena, io, env, &list) catch {};
    std.sort.block(App, list.items, {}, appLessThan);
    return list;
}

pub fn filter(arena: std.mem.Allocator, all_apps: []const App, query_lower: []const u8, matches: *std.ArrayList(usize)) void {
    matches.clearRetainingCapacity();
    for (all_apps, 0..) |app, i| {
        if (query_lower.len == 0 or std.mem.indexOf(u8, app.name_lower, query_lower) != null) {
            matches.append(arena, i) catch return;
        }
    }
}

fn discoverUserApplications(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map, list: *std.ArrayList(App)) !void {
    const home = env.get("HOME") orelse return;
    const path = try std.fs.path.join(arena, &.{ home, "Applications" });
    try discoverDir(arena, io, list, path);
}

fn discoverDir(arena: std.mem.Allocator, io: std.Io, list: *std.ArrayList(App), path: []const u8) !void {
    const dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.name, ".app")) continue;
        try addApplication(arena, list, path, entry.name);
    }
}

fn addApplication(arena: std.mem.Allocator, list: *std.ArrayList(App), dir_path: []const u8, bundle_name: []const u8) !void {
    const name = try arena.dupe(u8, bundle_name[0 .. bundle_name.len - 4]);
    const lower = try arena.alloc(u8, name.len);
    _ = std.ascii.lowerString(lower, name);
    const path = try std.fs.path.join(arena, &.{ dir_path, bundle_name });
    try list.append(arena, .{ .name = name, .name_lower = lower, .path = path });
}

fn appLessThan(_: void, lhs: App, rhs: App) bool {
    return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
}

test "filter matches substrings inside app names" {
    const test_apps = [_]App{
        .{ .name = "Microsoft Word", .name_lower = "microsoft word", .path = "" },
        .{ .name = "Pages", .name_lower = "pages", .path = "" },
        .{ .name = "WordService", .name_lower = "wordservice", .path = "" },
    };

    var matches: std.ArrayList(usize) = .empty;
    filter(std.testing.allocator, &test_apps, "word", &matches);
    defer matches.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, matches.items);
}

test "filter keeps empty query behavior" {
    const test_apps = [_]App{
        .{ .name = "Calculator", .name_lower = "calculator", .path = "" },
        .{ .name = "Messages", .name_lower = "messages", .path = "" },
    };

    var matches: std.ArrayList(usize) = .empty;
    filter(std.testing.allocator, &test_apps, "", &matches);
    defer matches.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, matches.items);
}
