const std = @import("std");

const OSStatus = i32;
const FourCharCode = u32;

const CGFloat = f64;
const NSInteger = isize;
const NSUInteger = usize;
const BOOL = bool;

const NSPoint = extern struct {
    x: CGFloat,
    y: CGFloat,
};

const NSSize = extern struct {
    width: CGFloat,
    height: CGFloat,
};

const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

const NSRange = extern struct {
    location: NSUInteger,
    length: NSUInteger,
};

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

const objc = struct {
    const id = ?*anyopaque;
    const Class = ?*anyopaque;
    const SEL = ?*anyopaque;
    const IMP = *const fn () callconv(.c) void;

    extern "c" fn objc_getClass(name: [*:0]const u8) Class;
    extern "c" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class;
    extern "c" fn objc_registerClassPair(cls: Class) void;
    extern "c" fn sel_registerName(name: [*:0]const u8) SEL;
    extern "c" fn class_addMethod(cls: Class, name: SEL, imp: IMP, types: [*:0]const u8) bool;
    extern "c" fn objc_msgSend() void;

    fn cls(name: [*:0]const u8) Class {
        return objc_getClass(name);
    }

    fn sel(name: [*:0]const u8) SEL {
        return sel_registerName(name);
    }
};

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
    app: objc.id = null,
    panel: objc.id = null,
    input: objc.id = null,
    rows: [max_visible_rows]objc.id = [_]objc.id{null} ** max_visible_rows,
    delegate: objc.id = null,
    scroll_offset: usize = 0,
};

var state: State = undefined;
var hotkey_ref: EventHotKeyRef = null;

var sel_move_up: objc.SEL = null;
var sel_move_down: objc.SEL = null;
var sel_insert_newline: objc.SEL = null;
var sel_cancel_operation: objc.SEL = null;

const kEventClassKeyboard = fourcc("keyb");
const kEventHotKeyPressed: u32 = 5;
const cmdKey: u32 = 0x0100;
const kVK_Space: u32 = 0x31;

const NSApplicationActivationPolicyAccessory: NSInteger = 1;
const NSBackingStoreBuffered: NSUInteger = 2;
const NSWindowStyleMaskBorderless: NSUInteger = 0;
const NSWindowStyleMaskNonactivatingPanel: NSUInteger = 1 << 7;
const NSFloatingWindowLevel: NSInteger = 3;
const NSUTF8StringEncoding: NSUInteger = 4;

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

fn msgSendId0(recv: objc.id, op: objc.SEL) objc.id {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op);
}

fn msgSendVoid0(recv: objc.id, op: objc.SEL) void {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op);
}

fn msgSendVoidId(recv: objc.id, op: objc.SEL, arg: objc.id) void {
    const Fn = *const fn (objc.id, objc.SEL, objc.id) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, arg);
}

fn msgSendVoidBool(recv: objc.id, op: objc.SEL, arg: BOOL) void {
    const Fn = *const fn (objc.id, objc.SEL, BOOL) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, arg);
}

fn msgSendVoidInt(recv: objc.id, op: objc.SEL, arg: NSInteger) void {
    const Fn = *const fn (objc.id, objc.SEL, NSInteger) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, arg);
}

fn msgSendVoidUInteger(recv: objc.id, op: objc.SEL, arg: NSUInteger) void {
    const Fn = *const fn (objc.id, objc.SEL, NSUInteger) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, arg);
}

fn msgSendVoidRect(recv: objc.id, op: objc.SEL, rect: NSRect) void {
    const Fn = *const fn (objc.id, objc.SEL, NSRect) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, rect);
}

fn msgSendVoidPoint(recv: objc.id, op: objc.SEL, point: NSPoint) void {
    const Fn = *const fn (objc.id, objc.SEL, NSPoint) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, point);
}

fn msgSendIdCString(recv: objc.id, op: objc.SEL, arg: [*:0]const u8) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, [*:0]const u8) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op, arg);
}

fn msgSendIdRect(recv: objc.id, op: objc.SEL, rect: NSRect) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, NSRect) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op, rect);
}

fn msgSendIdRectStyleBackingDefer(recv: objc.id, op: objc.SEL, rect: NSRect, style: NSUInteger, backing: NSUInteger, should_defer: BOOL) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, NSRect, NSUInteger, NSUInteger, BOOL) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op, rect, style, backing, should_defer);
}

fn msgSendVoidRange(recv: objc.id, op: objc.SEL, range: NSRange) void {
    const Fn = *const fn (objc.id, objc.SEL, NSRange) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(recv, op, range);
}

fn msgSendRect0(recv: objc.id, op: objc.SEL) NSRect {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) NSRect;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op);
}

fn msgSendCString0(recv: objc.id, op: objc.SEL) [*:0]const u8 {
    const Fn = *const fn (objc.id, objc.SEL) callconv(.c) [*:0]const u8;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(recv, op);
}

fn nsString(text: []const u8) objc.id {
    const s = &state;
    const z = s.arena.dupeZ(u8, text) catch unreachable;
    return msgSendIdCString(objc.cls("NSString"), objc.sel("stringWithUTF8String:"), z.ptr);
}

fn nsColor(calibrated_white: CGFloat, alpha: CGFloat) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, CGFloat, CGFloat) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(objc.cls("NSColor"), objc.sel("colorWithCalibratedWhite:alpha:"), calibrated_white, alpha);
}

fn nsColorRgb(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, CGFloat, CGFloat, CGFloat, CGFloat) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(objc.cls("NSColor"), objc.sel("colorWithCalibratedRed:green:blue:alpha:"), red, green, blue, alpha);
}

fn cgColor(color: objc.id) objc.id {
    return msgSendId0(color, objc.sel("CGColor"));
}

fn fontOfSize(size: CGFloat) objc.id {
    const Fn = *const fn (objc.id, objc.SEL, CGFloat) callconv(.c) objc.id;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    return f(objc.cls("NSFont"), objc.sel("systemFontOfSize:"), size);
}

fn initApplication() void {
    const app = msgSendId0(objc.cls("NSApplication"), objc.sel("sharedApplication"));
    msgSendVoidInt(app, objc.sel("setActivationPolicy:"), NSApplicationActivationPolicyAccessory);
    state.app = app;
}

fn buildPanel() void {
    var s = &state;
    const panel_rect = NSRect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 640, .height = 386 },
    };
    const style = NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel;
    const panel_alloc = msgSendId0(objc.cls("ZLPanel"), objc.sel("alloc"));
    const panel = msgSendIdRectStyleBackingDefer(panel_alloc, objc.sel("initWithContentRect:styleMask:backing:defer:"), panel_rect, style, NSBackingStoreBuffered, false);
    s.panel = panel;

    msgSendVoidBool(panel, objc.sel("setOpaque:"), false);
    msgSendVoidBool(panel, objc.sel("setMovableByWindowBackground:"), true);
    msgSendVoidBool(panel, objc.sel("setHidesOnDeactivate:"), true);
    msgSendVoidInt(panel, objc.sel("setLevel:"), NSFloatingWindowLevel);
    msgSendVoidId(panel, objc.sel("setDelegate:"), s.delegate);

    const content = msgSendId0(panel, objc.sel("contentView"));
    msgSendVoidBool(content, objc.sel("setWantsLayer:"), true);
    const layer = msgSendId0(content, objc.sel("layer"));
    msgSendVoidId(layer, objc.sel("setBackgroundColor:"), cgColor(nsColor(0.10, 0.96)));
    setLayerCornerRadius(layer, 14);

    const input = makeTextField(.{ .origin = .{ .x = 20, .y = 316 }, .size = .{ .width = 600, .height = 50 } }, 28, nsColor(0.93, 1.0), nsColor(0.16, 0.92), true);
    s.input = input;
    msgSendVoidId(input, objc.sel("setDelegate:"), s.delegate);
    msgSendVoidId(content, objc.sel("addSubview:"), input);

    var y: CGFloat = 266;
    for (0..max_visible_rows) |i| {
        const row = makeTextField(.{ .origin = .{ .x = 20, .y = y }, .size = .{ .width = 600, .height = 38 } }, 18, nsColor(0.87, 1.0), nsColor(0.0, 0.0), false);
        s.rows[i] = row;
        msgSendVoidId(content, objc.sel("addSubview:"), row);
        y -= 38;
    }

    updateRows();
}

fn makeTextField(rect: NSRect, font_size: CGFloat, text_color: objc.id, background_color: objc.id, editable: BOOL) objc.id {
    const alloc = msgSendId0(objc.cls("NSTextField"), objc.sel("alloc"));
    const field = msgSendIdRect(alloc, objc.sel("initWithFrame:"), rect);
    msgSendVoidBool(field, objc.sel("setBordered:"), false);
    msgSendVoidBool(field, objc.sel("setBezeled:"), false);
    msgSendVoidBool(field, objc.sel("setEditable:"), editable);
    msgSendVoidBool(field, objc.sel("setSelectable:"), editable);
    msgSendVoidId(field, objc.sel("setFont:"), fontOfSize(font_size));
    msgSendVoidId(field, objc.sel("setTextColor:"), text_color);
    msgSendVoidId(field, objc.sel("setBackgroundColor:"), background_color);
    msgSendVoidBool(field, objc.sel("setDrawsBackground:"), true);
    msgSendVoidBool(field, objc.sel("setWantsLayer:"), true);
    setLayerCornerRadius(msgSendId0(field, objc.sel("layer")), 7);
    return field;
}

fn setLayerCornerRadius(layer: objc.id, radius: CGFloat) void {
    const Fn = *const fn (objc.id, objc.SEL, CGFloat) callconv(.c) void;
    const f: Fn = @ptrCast(&objc.objc_msgSend);
    f(layer, objc.sel("setCornerRadius:"), radius);
}

fn registerHotkey() void {
    const target = GetApplicationEventTarget();
    const event = [_]EventTypeSpec{.{ .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed }};
    _ = InstallEventHandler(target, hotkeyHandler, 1, &event, null, null);
    _ = RegisterEventHotKey(kVK_Space, cmdKey, .{ .signature = fourcc("zlch"), .id = 1 }, target, 0, &hotkey_ref);
}

fn runApplication() noreturn {
    msgSendVoid0(state.app, objc.sel("run"));
    unreachable;
}

fn hotkeyHandler(_: EventHandlerCallRef, _: EventRef, _: ?*anyopaque) callconv(.c) OSStatus {
    showLauncher();
    return 0;
}

fn showLauncher() void {
    var s = &state;
    resetCursor();
    msgSendVoidId(s.input, objc.sel("setStringValue:"), nsString(""));
    s.query.clearRetainingCapacity();
    filter("");
    updateRows();
    positionPanel();
    msgSendVoidId(s.panel, objc.sel("makeKeyAndOrderFront:"), null);
    msgSendVoidBool(s.app, objc.sel("activateIgnoringOtherApps:"), true);
    msgSendVoidId(s.panel, objc.sel("makeFirstResponder:"), s.input);
}

fn dismissLauncher() void {
    var s = &state;
    msgSendVoidId(s.panel, objc.sel("orderOut:"), null);
    resetCursor();
    msgSendVoidId(s.input, objc.sel("setStringValue:"), nsString(""));
    s.query.clearRetainingCapacity();
    filter("");
    updateRows();
}

fn resetCursor() void {
    const cursor = msgSendId0(objc.cls("NSCursor"), objc.sel("arrowCursor"));
    msgSendVoid0(cursor, objc.sel("set"));
}

fn positionPanel() void {
    const screen = msgSendId0(objc.cls("NSScreen"), objc.sel("mainScreen"));
    const frame = msgSendRect0(screen, objc.sel("visibleFrame"));
    const width: CGFloat = 640;
    const height: CGFloat = 386;
    const origin = NSPoint{
        .x = frame.origin.x + (frame.size.width - width) / 2,
        .y = frame.origin.y + frame.size.height * 0.62 - height / 2,
    };
    msgSendVoidPoint(state.panel, objc.sel("setFrameOrigin:"), origin);
}

fn registerPanelClass() void {
    const superclass = objc.cls("NSPanel");
    const klass = objc.objc_allocateClassPair(superclass, "ZLPanel", 0);
    if (klass != null) {
        _ = objc.class_addMethod(klass, objc.sel("canBecomeKeyWindow"), @ptrCast(&returnYes), "B@:");
        _ = objc.class_addMethod(klass, objc.sel("canBecomeMainWindow"), @ptrCast(&returnYes), "B@:");
        objc.objc_registerClassPair(klass);
    }
}

fn returnYes(_: objc.id, _: objc.SEL) callconv(.c) BOOL {
    return true;
}

fn registerDelegateClass() void {
    const superclass = objc.cls("NSObject");
    const klass = objc.objc_allocateClassPair(superclass, "ZLDelegate", 0);
    if (klass != null) {
        _ = objc.class_addMethod(klass, objc.sel("controlTextDidChange:"), @ptrCast(&controlTextDidChange), "v@:@");
        _ = objc.class_addMethod(klass, objc.sel("control:textView:doCommandBySelector:"), @ptrCast(&doCommandBySelector), "c@:@@:");
        _ = objc.class_addMethod(klass, objc.sel("windowDidResignKey:"), @ptrCast(&windowDidResignKey), "v@:@");
        objc.objc_registerClassPair(klass);
    }
    const delegate = msgSendId0(objc.cls("ZLDelegate"), objc.sel("new"));
    state.delegate = delegate;
}

fn controlTextDidChange(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
    const s = &state;
    const value = msgSendId0(s.input, objc.sel("stringValue"));
    const utf8 = msgSendCString0(value, objc.sel("UTF8String"));
    const query = std.mem.span(utf8);
    filter(query);
    updateRows();
}

fn doCommandBySelector(_: objc.id, _: objc.SEL, _: objc.id, _: objc.id, command: objc.SEL) callconv(.c) BOOL {
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

fn windowDidResignKey(_: objc.id, _: objc.SEL, _: objc.id) callconv(.c) void {
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
    const selected_color = nsColorRgb(0.18, 0.38, 0.86, 0.94);
    const clear_color = nsColor(0.0, 0.0);
    for (s.rows, 0..) |row, i| {
        if (row == null) continue;
        const match_index = s.scroll_offset + i;
        if (match_index < s.matches.items.len) {
            const app = s.apps.items[s.matches.items[match_index]];
            msgSendVoidId(row, objc.sel("setStringValue:"), nsString(app.name));
        } else {
            msgSendVoidId(row, objc.sel("setStringValue:"), nsString(""));
        }
        if (match_index == s.highlighted and match_index < s.matches.items.len) {
            msgSendVoidId(row, objc.sel("setBackgroundColor:"), selected_color);
        } else {
            msgSendVoidId(row, objc.sel("setBackgroundColor:"), clear_color);
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
