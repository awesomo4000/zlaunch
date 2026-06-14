const std = @import("std");
const apps = @import("apps.zig");
const hotkey = @import("hotkey.zig");
const objc = @import("objc.zig");
const theme = @import("theme.zig");

const Layout = struct {
    const panel_width: objc.CGFloat = 640;
    const panel_height: objc.CGFloat = 340;
    const margin: objc.CGFloat = 20;
    const input_height: objc.CGFloat = 50;
    const entry_font_size: objc.CGFloat = 18;
    const row_height: objc.CGFloat = 46;
    const selected_bar_width: objc.CGFloat = 2;
    const visible_rows = 5;
    const input_y: objc.CGFloat = panel_height - margin - input_height;
    const row_start_y: objc.CGFloat = input_y - margin - row_height;
};

const DismissBehavior = enum {
    return_to_previous_app,
    leave_launched_app_active,
};

const CliOptions = struct {
    show_now: bool = false,
};

const CommandSelectors = struct {
    move_up: objc.Selector,
    move_down: objc.Selector,
    insert_newline: objc.Selector,
    cancel_operation: objc.Selector,

    fn init() CommandSelectors {
        return .{
            .move_up = objc.sel("moveUp:"),
            .move_down = objc.sel("moveDown:"),
            .insert_newline = objc.sel("insertNewline:"),
            .cancel_operation = objc.sel("cancelOperation:"),
        };
    }
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
    rows: [Layout.visible_rows]objc.TextField = [_]objc.TextField{.{}} ** Layout.visible_rows,
    selected_bars: [Layout.visible_rows]objc.View = [_]objc.View{.{}} ** Layout.visible_rows,
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
        const colors = theme.Theme.current(self.app);
        self.panel = objc.Panel.create(.{
            .class_name = "ZLPanel",
            .content_rect = .{
                .origin = .{ .x = 0, .y = 0 },
                .size = .{ .width = Layout.panel_width, .height = Layout.panel_height },
            },
            .style = .{ .nonactivating = true },
        });

        self.panel.setOpaque(true);
        self.panel.setBackgroundColor(colors.panel);
        self.panel.setMovableByWindowBackground(true);
        self.panel.setHidesOnDeactivate(true);
        self.panel.setLevel(.floating);
        self.panel.setDelegate(self.delegate);

        const content = self.panel.contentView();
        content.setWantsLayer(true);
        content.layer().setBackgroundColor(colors.panel.cgColor());
        content.layer().setCornerRadius(0);

        self.input = makeTextField(.{
            .origin = .{ .x = Layout.margin, .y = Layout.input_y },
            .size = .{ .width = Layout.panel_width - Layout.margin * 2, .height = Layout.input_height },
        }, colors.text, colors.input, true);
        self.input.setBorder(1.5, colors.accent);
        self.input.setDelegate(self.delegate);
        content.addSubview(self.input);

        var y: objc.CGFloat = Layout.row_start_y;
        for (&self.rows, &self.selected_bars) |*row, *selected_bar| {
            row.* = makeTextField(.{
                .origin = .{ .x = Layout.margin, .y = y },
                .size = .{ .width = Layout.panel_width - Layout.margin * 2, .height = Layout.row_height },
            }, colors.text, objc.Color.clear(), false);
            content.addSubview(row.*);

            selected_bar.* = objc.View.create(.{
                .origin = .{ .x = Layout.margin, .y = y },
                .size = .{ .width = Layout.selected_bar_width, .height = Layout.row_height },
            }, colors.accent);
            selected_bar.setHidden(true);
            content.addSubview(selected_bar.*);

            y -= Layout.row_height;
        }
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
        const colors = theme.Theme.current(self.app);
        self.panel.setBackgroundColor(colors.panel);
        self.panel.contentView().layer().setBackgroundColor(colors.panel.cgColor());
        self.input.setTextColor(colors.text);
        self.input.setFillColor(colors.input);
        self.input.setBorder(1.5, colors.accent);
        for (self.selected_bars) |selected_bar| {
            selected_bar.setFillColor(colors.accent);
        }
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
        const frame = objc.Screen.main().visibleFrame();
        self.panel.setFrameOrigin(.{
            .x = frame.origin.x + (frame.size.width - Layout.panel_width) / 2,
            .y = frame.origin.y + frame.size.height * 0.62 - Layout.panel_height / 2,
        });
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
        const n = @min(query.len, lower_buf.len);
        const lowered = std.ascii.lowerString(lower_buf[0..n], query[0..n]);
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
        self.scroll_offset = scrollOffsetForHighlight(self.highlighted, self.scroll_offset, Layout.visible_rows);
    }

    fn launchHighlighted(self: *Launcher) void {
        if (self.matches.items.len == 0) {
            self.dismiss(.return_to_previous_app);
            return;
        }

        const app_index = self.matches.items[self.highlighted];
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

    fn updateRows(self: *Launcher) void {
        const colors = theme.Theme.current(self.app);
        for (self.rows, self.selected_bars, 0..) |row, selected_bar, i| {
            if (row.isNil()) continue;
            const match_index = self.scroll_offset + i;
            const is_match = match_index < self.matches.items.len;
            if (match_index < self.matches.items.len) {
                const app = self.all_apps.items[self.matches.items[match_index]];
                row.setStringValue(objc.String.fromUtf8(self.arena, app.name));
            } else {
                row.setStringValue(objc.String.fromUtf8(self.arena, ""));
            }

            if (match_index == self.highlighted and is_match) {
                row.setFillColor(colors.selected);
                row.setTextColor(colors.selected_text);
                selected_bar.setHidden(false);
            } else {
                row.setFillColor(objc.Color.clear());
                row.setTextColor(colors.muted);
                selected_bar.setHidden(true);
            }
        }
    }
};

var launcher: Launcher = undefined;
var command_selectors: CommandSelectors = undefined;

pub fn main(init_context: std.process.Init) !void {
    const options = try parseArgs(init_context);
    launcher = try Launcher.init(init_context);
    launcher.filter("");

    registerPanelClass();
    registerDelegateClass();
    command_selectors = .init();
    launcher.buildUi();
    hotkey.register(hotkeyHandler);

    if (options.show_now) launcher.show();
    launcher.app.run();
}

fn makeTextField(rect: objc.Rect, text_color: objc.Color, background_color: objc.Color, editable: objc.BOOL) objc.TextField {
    return objc.TextField.create(.{
        .frame = rect,
        .font = objc.Font.monospacedSystem(Layout.entry_font_size, 0),
        .text_color = text_color,
        .background_color = background_color,
        .editable = editable,
    });
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

fn registerPanelClass() void {
    const class = objc.allocateClassPair(objc.cls("NSPanel"), "ZLPanel");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("canBecomeKeyWindow"), &returnYes, "B@:");
        _ = objc.addMethod(class, objc.sel("canBecomeMainWindow"), &returnYes, "B@:");
        objc.registerClassPair(class);
    }
}

fn returnYes(_: objc.Id, _: objc.Selector) callconv(.c) objc.BOOL {
    return true;
}

fn registerDelegateClass() void {
    const class = objc.allocateClassPair(objc.cls("NSObject"), "ZLDelegate");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("controlTextDidChange:"), &controlTextDidChange, "v@:@");
        _ = objc.addMethod(class, objc.sel("control:textView:doCommandBySelector:"), &doCommandBySelector, "c@:@@:");
        _ = objc.addMethod(class, objc.sel("windowDidResignKey:"), &windowDidResignKey, "v@:@");
        objc.registerClassPair(class);
    }
    launcher.delegate = objc.Object.new("ZLDelegate");
}

fn controlTextDidChange(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    launcher.setQueryFromInput();
}

fn doCommandBySelector(_: objc.Id, _: objc.Selector, _: objc.Id, _: objc.Id, command: objc.Selector) callconv(.c) objc.BOOL {
    if (command == command_selectors.move_up) {
        launcher.moveHighlight(-1);
        return true;
    }
    if (command == command_selectors.move_down) {
        launcher.moveHighlight(1);
        return true;
    }
    if (command == command_selectors.insert_newline) {
        launcher.launchHighlighted();
        return true;
    }
    if (command == command_selectors.cancel_operation) {
        launcher.dismiss(.return_to_previous_app);
        return true;
    }
    return false;
}

fn windowDidResignKey(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    launcher.dismiss(.return_to_previous_app);
}

fn scrollOffsetForHighlight(highlighted: usize, scroll_offset: usize, visible_rows: usize) usize {
    std.debug.assert(visible_rows > 0);

    if (highlighted < scroll_offset) return highlighted;
    if (highlighted >= scroll_offset + visible_rows) return highlighted + 1 - visible_rows;
    return scroll_offset;
}

test "scroll offset advances after the fifth visible item" {
    try std.testing.expectEqual(@as(usize, 0), scrollOffsetForHighlight(4, 0, 5));
    try std.testing.expectEqual(@as(usize, 1), scrollOffsetForHighlight(5, 0, 5));
    try std.testing.expectEqual(@as(usize, 2), scrollOffsetForHighlight(6, 1, 5));
}

test "scroll offset moves back when highlight goes above the visible window" {
    try std.testing.expectEqual(@as(usize, 2), scrollOffsetForHighlight(2, 4, 5));
}
