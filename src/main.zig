const std = @import("std");
const apps = @import("apps.zig");
const callbacks = @import("callbacks.zig");
const hotkey = @import("hotkey.zig");
const objc = @import("objc.zig");
const theme = @import("theme.zig");
const ui = @import("ui.zig");

const DismissBehavior = enum {
    return_to_previous_app,
    leave_launched_app_active,
};

const CliOptions = struct {
    show_now: bool = false,
};

const Launcher = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    all_apps: std.ArrayList(apps.App) = .empty,
    matches: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    highlighted: usize = 0,
    scroll_offset: usize = 0,
    app: objc.Application = .{},
    panel: objc.Panel = .{},
    input: objc.TextField = .{},
    rows: ui.Rows = [_]ui.Row{.{}} ** ui.Layout.visible_rows,
    divider: objc.View = .{},
    delegate: objc.Object = .{},
    previous_app: objc.RunningApplication = .{},
    dismissing: bool = false,

    fn init(init_context: std.process.Init) !Launcher {
        const arena = init_context.arena.allocator();
        const app = objc.Application.shared();
        app.setActivationPolicy(.accessory);

        return .{
            .arena = arena,
            .io = init_context.io,
            .all_apps = try apps.discover(arena, init_context.io, init_context.environ_map),
            .app = app,
        };
    }

    fn buildUi(self: *Launcher) void {
        const elements = ui.build(self.app, self.delegate);
        self.panel = elements.panel;
        self.input = elements.input;
        self.rows = elements.rows;
        self.divider = elements.divider;
    }

    fn show(self: *Launcher) void {
        objc.Cursor.arrow().set();
        self.applyTheme();
        self.releasePreviousApp();
        self.previous_app = objc.Workspace.shared().frontmostApplication().retain();
        self.dismissing = false;
        self.input.setStringValue(objc.String.fromUtf8(self.arena, ""));
        self.query.clearRetainingCapacity();
        self.filter("");
        self.updateRows();
        self.positionPanel();
        self.panel.makeKeyAndOrderFront();
        self.app.activateIgnoringOtherApps(true);
        self.panel.makeFirstResponder(self.input.object);
    }

    fn dismiss(self: *Launcher, behavior: DismissBehavior) void {
        if (self.dismissing) return;
        self.dismissing = true;
        self.panel.orderOut();
        objc.Cursor.arrow().set();
        self.input.setStringValue(objc.String.fromUtf8(self.arena, ""));
        self.query.clearRetainingCapacity();
        self.filter("");
        self.updateRows();

        switch (behavior) {
            .return_to_previous_app => self.restorePreviousApp(),
            .leave_launched_app_active => self.releasePreviousApp(),
        }
    }

    fn applyTheme(self: *Launcher) void {
        ui.applyTheme(self.app, self.panel, self.input, self.rows, self.divider);
    }

    fn restorePreviousApp(self: *Launcher) void {
        const previous = self.previous_app;
        self.previous_app = .{};
        if (previous.isNil()) return;
        previous.activate(.{ .ignoring_other_apps = true });
        previous.release();
    }

    fn releasePreviousApp(self: *Launcher) void {
        if (self.previous_app.isNil()) return;
        self.previous_app.release();
        self.previous_app = .{};
    }

    fn positionPanel(self: *Launcher) void {
        ui.positionPanel(self.panel);
    }

    fn setQueryFromInput(self: *Launcher) void {
        const value = self.input.stringValue();
        self.filter(std.mem.span(value.utf8()));
        self.updateRows();
    }

    fn filter(self: *Launcher, query: []const u8) void {
        self.query.clearRetainingCapacity();
        self.highlighted = 0;
        self.scroll_offset = 0;

        var lower_buf: [256]u8 = undefined;
        const lowered = lowerTrimmedQuery(query, &lower_buf);
        self.query.appendSlice(self.arena, lowered) catch return;
        apps.filter(self.arena, self.all_apps.items, lowered, &self.matches);
    }

    fn moveHighlight(self: *Launcher, delta: i32) void {
        if (self.matches.items.len == 0) return;
        if (delta < 0) {
            if (self.highlighted > 0) self.highlighted -= 1;
        } else if (self.highlighted + 1 < self.matches.items.len) {
            self.highlighted += 1;
        }
        self.keepHighlightVisible();
        self.updateRows();
    }

    fn keepHighlightVisible(self: *Launcher) void {
        self.scroll_offset = scrollOffsetForHighlight(self.highlighted, self.scroll_offset, ui.Layout.visible_rows);
    }

    fn launchHighlighted(self: *Launcher) void {
        if (self.matches.items.len == 0) {
            self.dismiss(.return_to_previous_app);
            return;
        }

        self.launchMatch(self.highlighted);
    }

    fn launchVisibleRow(self: *Launcher, visible_index: usize) bool {
        const match_index = self.scroll_offset + visible_index;
        if (match_index >= self.matches.items.len) return false;
        self.launchMatch(match_index);
        return true;
    }

    fn launchMatch(self: *Launcher, match_index: usize) void {
        const app_index = self.matches.items[match_index];
        const path = self.all_apps.items[app_index].path;
        var child = std.process.spawn(self.io, .{
            .argv = &.{ "/usr/bin/open", path },
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch {
            self.dismiss(.return_to_previous_app);
            return;
        };
        _ = child.wait(self.io) catch {};
        self.dismiss(.leave_launched_app_active);
    }

    fn autocomplete(self: *Launcher) void {
        const completion = longestCommonAppPrefix(self.all_apps.items, self.matches.items) orelse return;
        if (completion.len <= self.query.items.len) return;

        self.input.setStringValue(objc.String.fromUtf8(self.arena, completion));
        self.filter(completion);
        self.updateRows();
    }

    fn updateRows(self: *Launcher) void {
        const colors = theme.Theme.current(self.app);
        for (self.rows, 0..) |row, i| {
            if (row.isEmpty()) continue;
            const match_index = self.scroll_offset + i;
            const is_match = match_index < self.matches.items.len;
            if (is_match) {
                const app = self.all_apps.items[self.matches.items[match_index]];
                row.showApp(self.arena, i, app.name);
            } else {
                row.clear(self.arena);
            }

            row.setSelected(match_index == self.highlighted and is_match, colors);
        }
    }
};

var launcher: Launcher = undefined;

pub fn main(init_context: std.process.Init) !void {
    const options = try parseArgs(init_context);
    launcher = try Launcher.init(init_context);
    launcher.filter("");

    launcher.delegate = callbacks.install(.{
        .context = &launcher,
        .text_changed = onTextChanged,
        .move_highlight = onMoveHighlight,
        .launch_highlighted = onLaunchHighlighted,
        .launch_visible_row = onLaunchVisibleRow,
        .autocomplete = onAutocomplete,
        .dismiss = onDismiss,
    });
    launcher.buildUi();
    hotkey.register(hotkeyHandler);

    if (options.show_now) launcher.show();
    launcher.app.run();
}

fn parseArgs(init_context: std.process.Init) !CliOptions {
    var options: CliOptions = .{};
    const args = try init_context.minimal.args.toSlice(init_context.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--now")) options.show_now = true;
    }
    return options;
}

fn hotkeyHandler(_: hotkey.EventHandlerCallRef, _: hotkey.EventRef, _: ?*anyopaque) callconv(.c) hotkey.OSStatus {
    launcher.show();
    return 0;
}

fn onTextChanged(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.setQueryFromInput();
}

fn onMoveHighlight(context: *anyopaque, delta: i32) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.moveHighlight(delta);
}

fn onLaunchHighlighted(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.launchHighlighted();
}

fn onLaunchVisibleRow(context: *anyopaque, visible_index: usize) bool {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    return app_launcher.launchVisibleRow(visible_index);
}

fn onAutocomplete(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.autocomplete();
}

fn onDismiss(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.dismiss(.return_to_previous_app);
}

fn scrollOffsetForHighlight(highlighted: usize, scroll_offset: usize, visible_rows: usize) usize {
    std.debug.assert(visible_rows > 0);

    if (highlighted < scroll_offset) return highlighted;
    if (highlighted >= scroll_offset + visible_rows) return highlighted + 1 - visible_rows;
    return scroll_offset;
}

fn lowerTrimmedQuery(query: []const u8, buffer: []u8) []const u8 {
    const trimmed = std.mem.trim(u8, query, " \t\r\n");
    const n = @min(trimmed.len, buffer.len);
    return std.ascii.lowerString(buffer[0..n], trimmed[0..n]);
}

fn longestCommonAppPrefix(all_apps: []const apps.App, matches: []const usize) ?[]const u8 {
    if (matches.len == 0) return null;

    var prefix = all_apps[matches[0]].name_lower;
    for (matches[1..]) |app_index| {
        const candidate = all_apps[app_index].name_lower;
        prefix = prefix[0..commonPrefixLen(prefix, candidate)];
        if (prefix.len == 0) return prefix;
    }
    return prefix;
}

fn commonPrefixLen(lhs: []const u8, rhs: []const u8) usize {
    const n = @min(lhs.len, rhs.len);
    for (lhs[0..n], rhs[0..n], 0..) |a, b, i| {
        if (a != b) return i;
    }
    return n;
}

test "scroll offset advances after the fifth visible item" {
    try std.testing.expectEqual(@as(usize, 0), scrollOffsetForHighlight(4, 0, 5));
    try std.testing.expectEqual(@as(usize, 1), scrollOffsetForHighlight(5, 0, 5));
    try std.testing.expectEqual(@as(usize, 2), scrollOffsetForHighlight(6, 1, 5));
}

test "scroll offset moves back when highlight goes above the visible window" {
    try std.testing.expectEqual(@as(usize, 2), scrollOffsetForHighlight(2, 4, 5));
}

test "query matching ignores surrounding whitespace" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("calculator", lowerTrimmedQuery("Calculator   ", &buffer));
    try std.testing.expectEqualStrings("messages", lowerTrimmedQuery("   Messages", &buffer));
    try std.testing.expectEqualStrings("mail", lowerTrimmedQuery("  Mail   ", &buffer));
}

test "autocomplete uses longest common app prefix" {
    const test_apps = [_]apps.App{
        .{ .name = "Microsoft Excel", .name_lower = "microsoft excel", .path = "" },
        .{ .name = "Microsoft Word", .name_lower = "microsoft word", .path = "" },
        .{ .name = "Microsoft Teams", .name_lower = "microsoft teams", .path = "" },
    };
    const matches = [_]usize{ 0, 1, 2 };

    try std.testing.expectEqualStrings("microsoft ", longestCommonAppPrefix(&test_apps, &matches).?);
}

test "autocomplete returns null without matches" {
    const test_apps = [_]apps.App{};
    const matches = [_]usize{};

    try std.testing.expect(longestCommonAppPrefix(&test_apps, &matches) == null);
}

test "autocomplete can narrow to an exact single app" {
    const test_apps = [_]apps.App{
        .{ .name = "Calculator", .name_lower = "calculator", .path = "" },
    };
    const matches = [_]usize{0};

    try std.testing.expectEqualStrings("calculator", longestCommonAppPrefix(&test_apps, &matches).?);
}
