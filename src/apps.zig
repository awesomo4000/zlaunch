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

pub fn sortMatchesByLaunchCount(all_apps: []const App, matches: []usize, launch_counts: anytype) void {
    const Context = struct {
        all_apps: []const App,
        launch_counts: @TypeOf(launch_counts),

        fn lessThan(context: @This(), lhs_index: usize, rhs_index: usize) bool {
            const lhs = context.all_apps[lhs_index];
            const rhs = context.all_apps[rhs_index];
            const lhs_count = context.launch_counts.count(lhs.path);
            const rhs_count = context.launch_counts.count(rhs.path);

            if (lhs_count != rhs_count) return lhs_count > rhs_count;
            return lhs_index < rhs_index;
        }
    };

    std.sort.block(usize, matches, Context{
        .all_apps = all_apps,
        .launch_counts = launch_counts,
    }, Context.lessThan);
}

fn discoverUserApplications(arena: std.mem.Allocator, io: std.Io, env: *std.process.Environ.Map, list: *std.ArrayList(App)) !void {
    const home = env.get("HOME") orelse return;
    const path = try std.fs.path.join(arena, &.{ home, "Applications" });
    discoverDir(arena, io, list, path) catch {};

    const chrome_apps_path = try std.fs.path.join(arena, &.{ path, "Chrome Apps.localized" });
    discoverDir(arena, io, list, chrome_apps_path) catch {};
}

fn discoverDir(arena: std.mem.Allocator, io: std.Io, list: *std.ArrayList(App), path: []const u8) !void {
    const dir = try std.Io.Dir.openDirAbsolute(io, path, .{ .iterate = true });
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (!isApplicationBundleEntry(entry.kind, entry.name)) continue;
        try addApplication(arena, list, path, entry.name);
    }
}

fn isApplicationBundleEntry(kind: std.Io.File.Kind, name: []const u8) bool {
    switch (kind) {
        .directory, .sym_link => {},
        else => return false,
    }

    return std.mem.endsWith(u8, name, ".app");
}

fn addApplication(arena: std.mem.Allocator, list: *std.ArrayList(App), dir_path: []const u8, bundle_name: []const u8) !void {
    if (containsApplication(list.items, bundle_name)) return;

    const name = try arena.dupe(u8, bundle_name[0 .. bundle_name.len - 4]);
    const lower = try arena.alloc(u8, name.len);
    _ = std.ascii.lowerString(lower, name);
    const path = try std.fs.path.join(arena, &.{ dir_path, bundle_name });
    try list.append(arena, .{ .name = name, .name_lower = lower, .path = path });
}

fn containsApplication(app_list: []const App, bundle_name: []const u8) bool {
    const name = bundle_name[0 .. bundle_name.len - 4];
    for (app_list) |app| {
        if (std.ascii.eqlIgnoreCase(app.name, name)) return true;
    }
    return false;
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

test "discovery accepts symlinked app bundles" {
    try std.testing.expect(isApplicationBundleEntry(.directory, "Messages.app"));
    try std.testing.expect(isApplicationBundleEntry(.sym_link, "Safari.app"));
    try std.testing.expect(!isApplicationBundleEntry(.file, "Notes.app"));
    try std.testing.expect(!isApplicationBundleEntry(.sym_link, "README"));
}

test "duplicate app bundle names are skipped" {
    const test_apps = [_]App{
        .{ .name = "Safari", .name_lower = "safari", .path = "/Applications/Safari.app" },
    };

    try std.testing.expect(containsApplication(&test_apps, "Safari.app"));
    try std.testing.expect(containsApplication(&test_apps, "safari.app"));
    try std.testing.expect(!containsApplication(&test_apps, "Safari Technology Preview.app"));
}

test "sort matches ranks launch counts before alphabetical order" {
    const test_apps = [_]App{
        .{ .name = "Calendar", .name_lower = "calendar", .path = "/Applications/Calendar.app" },
        .{ .name = "Calculator", .name_lower = "calculator", .path = "/Applications/Calculator.app" },
        .{ .name = "Camera", .name_lower = "camera", .path = "/Applications/Camera.app" },
    };
    var matches = [_]usize{ 0, 1, 2 };

    const LaunchCounts = struct {
        fn count(_: @This(), path: []const u8) u64 {
            if (std.mem.eql(u8, path, "/Applications/Camera.app")) return 3;
            if (std.mem.eql(u8, path, "/Applications/Calendar.app")) return 1;
            return 0;
        }
    };

    sortMatchesByLaunchCount(&test_apps, &matches, LaunchCounts{});
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 1 }, &matches);
}

test "sort matches keeps alphabetical order for equal counts" {
    const test_apps = [_]App{
        .{ .name = "Calendar", .name_lower = "calendar", .path = "/Applications/Calendar.app" },
        .{ .name = "Calculator", .name_lower = "calculator", .path = "/Applications/Calculator.app" },
        .{ .name = "Camera", .name_lower = "camera", .path = "/Applications/Camera.app" },
    };
    var matches = [_]usize{ 0, 1, 2 };

    const LaunchCounts = struct {
        fn count(_: @This(), _: []const u8) u64 {
            return 2;
        }
    };

    sortMatchesByLaunchCount(&test_apps, &matches, LaunchCounts{});
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &matches);
}
