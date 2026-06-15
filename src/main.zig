const std = @import("std");
const app_index = @import("app_index.zig");
const callbacks = @import("callbacks.zig");
const config = @import("config.zig");
const hotkey = @import("hotkey.zig");
const icon_cache = @import("icon_cache.zig");
const objc = @import("objc.zig");
const stats = @import("stats.zig");
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
    index: app_index.AppIndex,
    icons: icon_cache.IconCache,
    launch_stats: stats.Stats = .{},
    query: std.ArrayList(u8) = .empty,
    highlighted: usize = 0,
    scroll_offset: usize = 0,
    app: objc.Application = .{},
    panel: objc.Panel = .{},
    glass: objc.GlassSurface = .{},
    search_icon: objc.ImageView = .{},
    input: objc.TextField = .{},
    rows: ui.Rows = [_]ui.Row{.{}} ** ui.Layout.visible_rows,
    divider: objc.View = .{},
    mouse_target: objc.View = .{},
    mode: ui.Mode = .compact,
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
            .index = try app_index.AppIndex.init(arena, init_context.io, init_context.environ_map),
            .icons = icon_cache.IconCache.init(arena),
            .launch_stats = try stats.Stats.load(arena, init_context.io, init_context.environ_map),
            .app = app,
        };
    }

    fn buildUi(self: *Launcher) void {
        const elements = ui.build(self.app, self.delegate);
        self.panel = elements.panel;
        self.glass = elements.glass;
        self.search_icon = elements.search_icon;
        self.input = elements.input;
        self.rows = elements.rows;
        self.divider = elements.divider;
        self.mouse_target = elements.mouse_target;
    }

    fn show(self: *Launcher) void {
        objc.Cursor.arrow().set();
        self.applyTheme();
        self.releasePreviousApp();
        self.previous_app = objc.Workspace.shared().frontmostApplication().retain();
        self.dismissing = false;
        self.input.setStringValue(objc.String.fromUtf8(self.arena, ""));
        self.query.clearRetainingCapacity();
        self.setQuery("");
        self.setMode(.compact);
        self.positionPanel();
        self.panel.makeKeyAndOrderFront();
        self.app.activateIgnoringOtherApps(true);
        self.panel.makeFirstResponder(self.input.object);
        self.input.setInsertionPointColor(theme.Theme.current(self.app).cursor);
    }

    fn dismiss(self: *Launcher, behavior: DismissBehavior) void {
        if (self.dismissing) return;
        self.dismissing = true;
        self.panel.orderOut();
        objc.Cursor.arrow().set();
        self.input.setStringValue(objc.String.fromUtf8(self.arena, ""));
        self.query.clearRetainingCapacity();
        self.setQuery("");
        self.setMode(.compact);

        switch (behavior) {
            .return_to_previous_app => self.restorePreviousApp(),
            .leave_launched_app_active => self.releasePreviousApp(),
        }
    }

    fn applyTheme(self: *Launcher) void {
        ui.applyTheme(self.app, self.panel, self.glass, self.search_icon, self.input, self.rows, self.divider);
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
        ui.positionPanel(self.panel, self.mode);
    }

    fn setQueryFromInput(self: *Launcher) void {
        const value = self.input.stringValue();
        self.setQuery(std.mem.span(value.utf8()));
        self.syncModeWithMatches();
        self.updateRows();
    }

    fn setQuery(self: *Launcher, query: []const u8) void {
        self.query.clearRetainingCapacity();
        self.highlighted = 0;
        self.scroll_offset = 0;

        var lower_buf: [256]u8 = undefined;
        const lowered = lowerTrimmedQuery(query, &lower_buf);
        self.query.appendSlice(self.arena, lowered) catch return;
        self.index.search(lowered, self.launch_stats);
    }

    fn refreshAppsKeepingQuery(self: *Launcher) void {
        var query_buf: [256]u8 = undefined;
        const query = self.copyCurrentQuery(&query_buf);
        self.index.refresh() catch return;
        self.icons.clear();
        self.setQuery(query);
        self.syncModeWithMatches();
    }

    fn copyCurrentQuery(self: *Launcher, buffer: []u8) []const u8 {
        const n = @min(self.query.items.len, buffer.len);
        @memcpy(buffer[0..n], self.query.items[0..n]);
        return buffer[0..n];
    }

    fn moveHighlight(self: *Launcher, delta: i32) void {
        if (self.mode == .compact) return;
        if (self.index.count() == 0) return;
        if (delta < 0) {
            if (self.highlighted > 0) self.highlighted -= 1;
        } else if (self.highlighted + 1 < self.index.count()) {
            self.highlighted += 1;
        }
        self.keepHighlightVisible();
        self.updateRows();
    }

    fn hoverVisibleRow(self: *Launcher, visible_index: usize) void {
        if (self.mode == .compact) return;
        const match_index = self.scroll_offset + visible_index;
        if (match_index >= self.index.count()) return;
        if (match_index == self.highlighted) return;

        self.highlighted = match_index;
        self.updateRows();
    }

    fn keepHighlightVisible(self: *Launcher) void {
        self.scroll_offset = scrollOffsetForHighlight(self.highlighted, self.scroll_offset, ui.Layout.visible_rows);
    }

    fn launchHighlighted(self: *Launcher) void {
        if (self.mode == .compact) return;
        if (self.index.count() == 0) {
            self.dismiss(.return_to_previous_app);
            return;
        }

        self.launchMatch(self.highlighted);
    }

    fn launchVisibleRow(self: *Launcher, visible_index: usize) bool {
        if (self.mode == .compact) return false;
        const match_index = self.scroll_offset + visible_index;
        if (match_index >= self.index.count()) return false;
        self.launchMatch(match_index);
        return true;
    }

    fn launchMatch(self: *Launcher, match_index: usize) void {
        const selected_app = self.index.appForMatch(match_index) orelse return;
        if (!app_index.pathExists(self.io, selected_app.path)) {
            self.refreshAppsKeepingQuery();
            self.updateRows();
            return;
        }

        const launched = self.openApp(selected_app);
        if (!launched) {
            self.dismiss(.return_to_previous_app);
            return;
        }

        self.launch_stats.recordLaunch(selected_app.path) catch {};
        self.dismiss(.leave_launched_app_active);
    }

    fn openApp(self: *Launcher, selected_app: app_index.App) bool {
        var child = std.process.spawn(self.io, .{
            .argv = &.{ "/usr/bin/open", selected_app.path },
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch {
            return false;
        };
        const term: std.process.Child.Term = child.wait(self.io) catch .{ .unknown = 0 };
        return switch (term) {
            .exited => |code| code == 0,
            else => false,
        };
    }

    fn autocomplete(self: *Launcher) void {
        if (self.query.items.len == 0) return;
        const completion = self.index.longestCommonPrefix() orelse return;
        if (completion.len <= self.query.items.len) return;

        self.input.setStringValue(objc.String.fromUtf8(self.arena, completion));
        self.setQuery(completion);
        self.syncModeWithMatches();
        self.updateRows();
    }

    fn syncModeWithMatches(self: *Launcher) void {
        const next_mode: ui.Mode = if (self.query.items.len > 0 and self.index.count() > 0) .expanded else .compact;
        self.setMode(next_mode);
    }

    fn setMode(self: *Launcher, mode: ui.Mode) void {
        self.mode = mode;
        ui.setMode(self.panel, self.glass, self.search_icon, self.input, self.rows, self.divider, self.mouse_target, mode);
    }

    fn updateRows(self: *Launcher) void {
        self.updateRowsChecked(true);
    }

    fn updateRowsChecked(self: *Launcher, allow_refresh: bool) void {
        if (self.mode == .compact) {
            self.clearRows();
            return;
        }

        if (allow_refresh and self.visibleResultsAreStale()) {
            self.refreshAppsKeepingQuery();
            self.updateRowsChecked(false);
            return;
        }

        self.drawRows();
    }

    fn clearRows(self: *Launcher) void {
        for (self.rows) |row| row.clear(self.arena);
    }

    fn drawRows(self: *Launcher) void {
        objc.Transaction.begin();
        defer objc.Transaction.commit();
        objc.Transaction.setDisableActions(true);

        const colors = theme.Theme.current(self.app);
        for (self.rows, 0..) |row, i| {
            if (row.isEmpty()) continue;
            const match_index = self.scroll_offset + i;
            if (self.index.appForMatch(match_index)) |matched_app| {
                row.showApp(self.arena, i, matched_app.name, self.icons.iconForPath(matched_app.path));
                row.setSelected(match_index == self.highlighted, colors);
            } else {
                row.clear(self.arena);
            }
        }
    }

    fn visibleResultsAreStale(self: *Launcher) bool {
        return self.index.visibleMatchesContainMissingPath(self.scroll_offset, ui.Layout.visible_rows);
    }
};

var launcher: Launcher = undefined;

pub fn main(init_context: std.process.Init) !void {
    const options = try parseArgs(init_context);
    const app_config = try config.load(init_context.arena.allocator(), init_context.io, init_context.environ_map);
    launcher = try Launcher.init(init_context);
    launcher.setQuery("");

    launcher.delegate = callbacks.install(.{
        .context = &launcher,
        .text_changed = onTextChanged,
        .move_highlight = onMoveHighlight,
        .launch_highlighted = onLaunchHighlighted,
        .launch_visible_row = onLaunchVisibleRow,
        .hover_visible_row = onHoverVisibleRow,
        .autocomplete = onAutocomplete,
        .refresh_apps = onRefreshApps,
        .dismiss = onDismiss,
    });
    launcher.buildUi();
    hotkey.register(hotkeyHandler, app_config.hotkey);

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

fn onHoverVisibleRow(context: *anyopaque, visible_index: usize) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.hoverVisibleRow(visible_index);
}

fn onAutocomplete(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.autocomplete();
}

fn onRefreshApps(context: *anyopaque) void {
    const app_launcher: *Launcher = @ptrCast(@alignCast(context));
    app_launcher.refreshAppsKeepingQuery();
    app_launcher.updateRows();
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
