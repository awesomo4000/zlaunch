const std = @import("std");
const objc = @import("objc.zig");

const OSStatus = i32;
const FourCharCode = u32;

const EventHotKeyID = extern struct {
    signature: FourCharCode,
    id: u32,
};

const EventTypeSpec = extern struct {
    eventClass: FourCharCode,
    eventKind: u32,
};

const EventTargetRef = ?*opaque {};
const EventHotKeyRef = ?*opaque {};
const EventHandlerRef = ?*opaque {};
const EventHandlerCallRef = ?*opaque {};
const EventRef = ?*opaque {};
const EventHandlerProc = *const fn (EventHandlerCallRef, EventRef, ?*anyopaque) callconv(.c) OSStatus;

extern "c" fn RegisterEventHotKey(u32, u32, EventHotKeyID, EventTargetRef, u32, *EventHotKeyRef) OSStatus;
extern "c" fn GetApplicationEventTarget() EventTargetRef;
extern "c" fn InstallEventHandler(EventTargetRef, EventHandlerProc, usize, [*]const EventTypeSpec, ?*anyopaque, ?*EventHandlerRef) OSStatus;

const App = struct {
    name: []const u8,
    name_lower: []const u8,
    path: []const u8,
};

const max_visible_rows = 8;

const State = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    env: *std.process.Environ.Map,
    apps: std.ArrayList(App) = .empty,
    matches: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    highlighted: usize = 0,
    app: objc.Application = .{},
    panel: objc.Panel = .{},
    input: objc.TextField = .{},
    rows: [max_visible_rows]objc.TextField = [_]objc.TextField{.{}} ** max_visible_rows,
    delegate: objc.Object = .{},
    scroll_offset: usize = 0,
};

var state: State = undefined;
var hotkey_ref: EventHotKeyRef = null;

var sel_move_up: objc.Selector = null;
var sel_move_down: objc.Selector = null;
var sel_insert_newline: objc.Selector = null;
var sel_cancel_operation: objc.Selector = null;

const kEventClassKeyboard = fourcc("keyb");
const kEventHotKeyPressed: u32 = 5;
const cmdKey: u32 = 0x0100;
const kVK_Space: u32 = 0x31;

fn fourcc(comptime s: *const [4]u8) u32 {
    return std.mem.readInt(u32, s, .big);
}

pub fn main(init: std.process.Init) !void {
    const s = State{ .arena = init.arena.allocator(), .io = init.io, .env = init.environ_map };
    state = s;

    try discoverApplications();
    filter("");
    registerPanelClass();
    registerDelegateClass();
    initSelectors();
    initApplication();
    buildPanel();
    registerHotkey();
    runApplication();
}

fn initSelectors() void {
    sel_move_up = objc.sel("moveUp:");
    sel_move_down = objc.sel("moveDown:");
    sel_insert_newline = objc.sel("insertNewline:");
    sel_cancel_operation = objc.sel("cancelOperation:");
}

fn initApplication() void {
    const app = objc.Application.shared();
    app.setActivationPolicy(.accessory);
    state.app = app;
}

fn buildPanel() void {
    var s = &state;
    const panel_rect = objc.Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 640, .height = 386 },
    };
    const panel = objc.Panel.create(.{
        .class_name = "ZLPanel",
        .content_rect = panel_rect,
        .style = .{ .nonactivating = true },
    });
    s.panel = panel;

    panel.setOpaque(false);
    panel.setMovableByWindowBackground(true);
    panel.setHidesOnDeactivate(true);
    panel.setLevel(.floating);
    panel.setDelegate(s.delegate);

    const content = panel.contentView();
    content.setWantsLayer(true);
    const layer = content.layer();
    layer.setBackgroundColor(objc.Color.calibratedWhite(0.10, 0.96).cgColor());
    layer.setCornerRadius(14);

    const input = makeTextField(.{ .origin = .{ .x = 20, .y = 316 }, .size = .{ .width = 600, .height = 50 } }, 28, objc.Color.calibratedWhite(0.93, 1.0), objc.Color.calibratedWhite(0.16, 0.92), true);
    s.input = input;
    input.setDelegate(s.delegate);
    content.addSubview(input);

    var y: objc.CGFloat = 266;
    for (0..max_visible_rows) |i| {
        const row = makeTextField(.{ .origin = .{ .x = 20, .y = y }, .size = .{ .width = 600, .height = 38 } }, 18, objc.Color.calibratedWhite(0.87, 1.0), objc.Color.calibratedWhite(0.0, 0.0), false);
        s.rows[i] = row;
        content.addSubview(row);
        y -= 38;
    }

    updateRows();
}

fn makeTextField(rect: objc.Rect, font_size: objc.CGFloat, text_color: objc.Color, background_color: objc.Color, editable: objc.BOOL) objc.TextField {
    return objc.TextField.create(.{
        .frame = rect,
        .font_size = font_size,
        .text_color = text_color,
        .background_color = background_color,
        .editable = editable,
    });
}

fn registerHotkey() void {
    const target = GetApplicationEventTarget();
    const event = [_]EventTypeSpec{.{ .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed }};
    _ = InstallEventHandler(target, hotkeyHandler, 1, &event, null, null);
    _ = RegisterEventHotKey(kVK_Space, cmdKey, .{ .signature = fourcc("zlch"), .id = 1 }, target, 0, &hotkey_ref);
}

fn runApplication() noreturn {
    state.app.run();
}

fn hotkeyHandler(_: EventHandlerCallRef, _: EventRef, _: ?*anyopaque) callconv(.c) OSStatus {
    showLauncher();
    return 0;
}

fn showLauncher() void {
    var s = &state;
    resetCursor();
    s.input.setStringValue(objc.String.fromUtf8(s.arena, ""));
    s.query.clearRetainingCapacity();
    filter("");
    updateRows();
    positionPanel();
    s.panel.makeKeyAndOrderFront();
    s.app.activateIgnoringOtherApps(true);
    s.panel.makeFirstResponder(s.input.object);
}

fn dismissLauncher() void {
    var s = &state;
    s.panel.orderOut();
    resetCursor();
    s.input.setStringValue(objc.String.fromUtf8(s.arena, ""));
    s.query.clearRetainingCapacity();
    filter("");
    updateRows();
}

fn resetCursor() void {
    objc.Cursor.arrow().set();
}

fn positionPanel() void {
    const frame = objc.Screen.main().visibleFrame();
    const width: objc.CGFloat = 640;
    const height: objc.CGFloat = 386;
    const origin = objc.Point{
        .x = frame.origin.x + (frame.size.width - width) / 2,
        .y = frame.origin.y + frame.size.height * 0.62 - height / 2,
    };
    state.panel.setFrameOrigin(origin);
}

fn registerPanelClass() void {
    const superclass = objc.cls("NSPanel");
    const klass = objc.allocateClassPair(superclass, "ZLPanel");
    if (klass != null) {
        _ = objc.addMethod(klass, objc.sel("canBecomeKeyWindow"), &returnYes, "B@:");
        _ = objc.addMethod(klass, objc.sel("canBecomeMainWindow"), &returnYes, "B@:");
        objc.registerClassPair(klass);
    }
}

fn returnYes(_: objc.Id, _: objc.Selector) callconv(.c) objc.BOOL {
    return true;
}

fn registerDelegateClass() void {
    const superclass = objc.cls("NSObject");
    const klass = objc.allocateClassPair(superclass, "ZLDelegate");
    if (klass != null) {
        _ = objc.addMethod(klass, objc.sel("controlTextDidChange:"), &controlTextDidChange, "v@:@");
        _ = objc.addMethod(klass, objc.sel("control:textView:doCommandBySelector:"), &doCommandBySelector, "c@:@@:");
        _ = objc.addMethod(klass, objc.sel("windowDidResignKey:"), &windowDidResignKey, "v@:@");
        objc.registerClassPair(klass);
    }
    state.delegate = objc.Object.new("ZLDelegate");
}

fn controlTextDidChange(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    const s = &state;
    const value = s.input.stringValue();
    const utf8 = value.utf8();
    const query = std.mem.span(utf8);
    filter(query);
    updateRows();
}

fn doCommandBySelector(_: objc.Id, _: objc.Selector, _: objc.Id, _: objc.Id, command: objc.Selector) callconv(.c) objc.BOOL {
    if (command == sel_move_up) {
        moveHighlight(-1);
        return true;
    }
    if (command == sel_move_down) {
        moveHighlight(1);
        return true;
    }
    if (command == sel_insert_newline) {
        launchHighlighted();
        return true;
    }
    if (command == sel_cancel_operation) {
        dismissLauncher();
        return true;
    }
    return false;
}

fn windowDidResignKey(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    dismissLauncher();
}

fn moveHighlight(delta: i32) void {
    var s = &state;
    if (s.matches.items.len == 0) return;
    if (delta < 0) {
        if (s.highlighted > 0) s.highlighted -= 1;
    } else if (s.highlighted + 1 < s.matches.items.len) {
        s.highlighted += 1;
    }
    keepHighlightVisible();
    updateRows();
}

fn launchHighlighted() void {
    const s = &state;
    if (s.matches.items.len == 0) {
        dismissLauncher();
        return;
    }
    const app_index = s.matches.items[s.highlighted];
    const path = s.apps.items[app_index].path;
    var child = std.process.spawn(s.io, .{
        .argv = &.{ "/usr/bin/open", path },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch {
        dismissLauncher();
        return;
    };
    _ = child.wait(s.io) catch {};
    dismissLauncher();
}

fn updateRows() void {
    const s = &state;
    const selected_color = objc.Color.rgb(0.18, 0.38, 0.86, 0.94);
    const clear_color = objc.Color.calibratedWhite(0.0, 0.0);
    for (s.rows, 0..) |row, i| {
        if (row.isNil()) continue;
        const match_index = s.scroll_offset + i;
        if (match_index < s.matches.items.len) {
            const app = s.apps.items[s.matches.items[match_index]];
            row.setStringValue(objc.String.fromUtf8(s.arena, app.name));
        } else {
            row.setStringValue(objc.String.fromUtf8(s.arena, ""));
        }
        if (match_index == s.highlighted and match_index < s.matches.items.len) {
            row.setBackgroundColor(selected_color);
        } else {
            row.setBackgroundColor(clear_color);
        }
    }
}

fn filter(query: []const u8) void {
    var s = &state;
    s.matches.clearRetainingCapacity();
    s.query.clearRetainingCapacity();
    s.highlighted = 0;
    s.scroll_offset = 0;

    var lower_buf: [256]u8 = undefined;
    const n = @min(query.len, lower_buf.len);
    const lowered = std.ascii.lowerString(lower_buf[0..n], query[0..n]);
    s.query.appendSlice(s.arena, lowered) catch return;
    for (s.apps.items, 0..) |app, i| {
        if (lowered.len == 0 or std.mem.startsWith(u8, app.name_lower, lowered)) {
            s.matches.append(s.arena, i) catch return;
        }
    }
}

fn keepHighlightVisible() void {
    var s = &state;
    if (s.highlighted < s.scroll_offset) {
        s.scroll_offset = s.highlighted;
    } else if (s.highlighted >= s.scroll_offset + max_visible_rows) {
        s.scroll_offset = s.highlighted + 1 - max_visible_rows;
    }
}

fn discoverApplications() !void {
    try discoverDir("/Applications");
    discoverDir("/Applications/Utilities") catch {};
    discoverDir("/System/Applications") catch {};
    discoverDir("/System/Applications/Utilities") catch {};
    discoverUserApplications() catch {};
    std.sort.block(App, state.apps.items, {}, appLessThan);
}

fn discoverUserApplications() !void {
    const s = &state;
    const home = s.env.get("HOME") orelse return;
    const path = try std.fs.path.join(s.arena, &.{ home, "Applications" });
    try discoverDir(path);
}

fn discoverDir(path: []const u8) !void {
    const s = &state;
    const dir = try std.Io.Dir.openDirAbsolute(s.io, path, .{ .iterate = true });
    defer dir.close(s.io);

    var iter = dir.iterate();
    while (try iter.next(s.io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.endsWith(u8, entry.name, ".app")) continue;
        try addApplication(path, entry.name);
    }
}

fn addApplication(dir_path: []const u8, bundle_name: []const u8) !void {
    var s = &state;
    const name = try s.arena.dupe(u8, bundle_name[0 .. bundle_name.len - 4]);
    const lower = try s.arena.alloc(u8, name.len);
    _ = std.ascii.lowerString(lower, name);
    const path = try std.fs.path.join(s.arena, &.{ dir_path, bundle_name });
    try s.apps.append(s.arena, .{ .name = name, .name_lower = lower, .path = path });
}

fn appLessThan(_: void, lhs: App, rhs: App) bool {
    return std.ascii.lessThanIgnoreCase(lhs.name, rhs.name);
}
