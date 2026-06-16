const std = @import("std");
const objc = @import("objc.zig");
const ui = @import("ui.zig");

const command_modifier: objc.NSUInteger = 1 << 20;
const precise_scroll_row_delta: objc.CGFloat = 36;
const wheel_scroll_row_delta: objc.CGFloat = 3;

pub const Handler = struct {
    context: *anyopaque,
    text_changed: *const fn (*anyopaque) void,
    move_highlight: *const fn (*anyopaque, i32) void,
    launch_highlighted: *const fn (*anyopaque) void,
    launch_visible_row: *const fn (*anyopaque, usize) bool,
    hover_visible_row: *const fn (*anyopaque, usize) void,
    scroll_results: *const fn (*anyopaque, i32) void,
    autocomplete: *const fn (*anyopaque) void,
    refresh_apps: *const fn (*anyopaque) void,
    dismiss: *const fn (*anyopaque) void,
};

const Command = enum {
    move_up,
    move_down,
    insert_newline,
    insert_tab,
    cancel_operation,
    unhandled,
};

const CommandSelectors = struct {
    move_up: objc.Selector,
    move_down: objc.Selector,
    insert_newline: objc.Selector,
    insert_tab: objc.Selector,
    cancel_operation: objc.Selector,

    fn init() CommandSelectors {
        return .{
            .move_up = objc.sel("moveUp:"),
            .move_down = objc.sel("moveDown:"),
            .insert_newline = objc.sel("insertNewline:"),
            .insert_tab = objc.sel("insertTab:"),
            .cancel_operation = objc.sel("cancelOperation:"),
        };
    }

    fn commandFor(self: CommandSelectors, selector: objc.Selector) Command {
        if (selector == self.move_up) return .move_up;
        if (selector == self.move_down) return .move_down;
        if (selector == self.insert_newline) return .insert_newline;
        if (selector == self.insert_tab) return .insert_tab;
        if (selector == self.cancel_operation) return .cancel_operation;
        return .unhandled;
    }
};

var handler: Handler = undefined;
var command_selectors: CommandSelectors = undefined;
var scroll_delta_remainder: objc.CGFloat = 0;

pub fn install(app_handler: Handler) objc.Object {
    handler = app_handler;
    command_selectors = .init();
    registerPanelClass();
    registerInputTextFieldClass();
    registerResultsMouseViewClass();
    return registerDelegateClass();
}

fn registerPanelClass() void {
    const class = objc.allocateClassPair(objc.cls("NSPanel"), "ZLPanel");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("canBecomeKeyWindow"), &returnYes, "B@:");
        _ = objc.addMethod(class, objc.sel("canBecomeMainWindow"), &returnYes, "B@:");
        _ = objc.addMethod(class, objc.sel("performKeyEquivalent:"), &panelPerformKeyEquivalent, "c@:@");
        objc.registerClassPair(class);
    }
}

fn returnYes(_: objc.Id, _: objc.Selector) callconv(.c) objc.BOOL {
    return true;
}

fn returnYesForEvent(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) objc.BOOL {
    return true;
}

fn registerInputTextFieldClass() void {
    const class = objc.allocateClassPair(objc.cls("NSTextField"), "ZLInputTextField");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("keyDown:"), &inputKeyDown, "v@:@");
        objc.registerClassPair(class);
    }
}

fn registerResultsMouseViewClass() void {
    const class = objc.allocateClassPair(objc.cls("NSView"), "ZLResultsMouseView");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("acceptsFirstMouse:"), &returnYesForEvent, "B@:@");
        _ = objc.addMethod(class, objc.sel("mouseMoved:"), &resultsMouseMoved, "v@:@");
        _ = objc.addMethod(class, objc.sel("mouseDown:"), &resultsMouseDown, "v@:@");
        _ = objc.addMethod(class, objc.sel("scrollWheel:"), &resultsScrollWheel, "v@:@");
        objc.registerClassPair(class);
    }
}

fn registerDelegateClass() objc.Object {
    const class = objc.allocateClassPair(objc.cls("NSObject"), "ZLDelegate");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("controlTextDidChange:"), &controlTextDidChange, "v@:@");
        _ = objc.addMethod(class, objc.sel("control:textView:doCommandBySelector:"), &doCommandBySelector, "c@:@@:");
        _ = objc.addMethod(class, objc.sel("windowDidResignKey:"), &windowDidResignKey, "v@:@");
        objc.registerClassPair(class);
    }
    return objc.Object.new("ZLDelegate");
}

fn resultsMouseMoved(self: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) void {
    const visible_index = visibleRowForMouseEvent(self, event) orelse return;
    handler.hover_visible_row(handler.context, visible_index);
}

fn resultsMouseDown(self: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) void {
    const visible_index = visibleRowForMouseEvent(self, event) orelse return;
    _ = handler.launch_visible_row(handler.context, visible_index);
}

fn resultsScrollWheel(_: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) void {
    if (event == null) return;
    const delta_y = objc.msgSendCGFloat0(event, objc.sel("scrollingDeltaY"));
    const row_delta = if (objc.msgSendBool0(event, objc.sel("hasPreciseScrollingDeltas"))) precise_scroll_row_delta else wheel_scroll_row_delta;

    if (delta_y == 0) return;
    if (scroll_delta_remainder != 0 and (scroll_delta_remainder < 0) != (delta_y < 0)) {
        scroll_delta_remainder = 0;
    }
    scroll_delta_remainder += delta_y;

    if (scroll_delta_remainder <= -row_delta) {
        scroll_delta_remainder += row_delta;
        handler.scroll_results(handler.context, 1);
    } else if (scroll_delta_remainder >= row_delta) {
        scroll_delta_remainder -= row_delta;
        handler.scroll_results(handler.context, -1);
    }
}

fn visibleRowForMouseEvent(view: objc.Id, event: objc.Id) ?usize {
    if (view == null or event == null) return null;

    const window_point = objc.msgSendPoint0(event, objc.sel("locationInWindow"));
    const local_point = objc.msgSendPointPointId(view, objc.sel("convertPoint:fromView:"), window_point, null);
    return ui.visibleRowAtY(local_point.y);
}

fn controlTextDidChange(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    handler.text_changed(handler.context);
}

fn doCommandBySelector(_: objc.Id, _: objc.Selector, _: objc.Id, _: objc.Id, selector: objc.Selector) callconv(.c) objc.BOOL {
    switch (command_selectors.commandFor(selector)) {
        .move_up => handler.move_highlight(handler.context, -1),
        .move_down => handler.move_highlight(handler.context, 1),
        .insert_newline => handler.launch_highlighted(handler.context),
        .insert_tab => handler.autocomplete(handler.context),
        .cancel_operation => handler.dismiss(handler.context),
        .unhandled => return false,
    }
    return true;
}

fn windowDidResignKey(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    handler.dismiss(handler.context);
}

fn panelPerformKeyEquivalent(self: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) objc.BOOL {
    if (tryRefreshEvent(event)) return true;
    if (tryLaunchNumberEvent(event)) return true;
    return objc.msgSendSuperBoolId(self, objc.cls("NSPanel"), objc.sel("performKeyEquivalent:"), event);
}

fn inputKeyDown(self: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) void {
    if (tryRefreshEvent(event)) return;
    if (tryLaunchNumberEvent(event)) return;

    objc.msgSendSuperVoidId(self, objc.cls("NSTextField"), objc.sel("keyDown:"), event);
}

fn tryRefreshEvent(event: objc.Id) bool {
    if (!isCommandCharacter(event, 'r')) return false;
    handler.refresh_apps(handler.context);
    return true;
}

fn tryLaunchNumberEvent(event: objc.Id) bool {
    const character = commandCharacter(event) orelse return false;
    if (character >= '1' and character <= '5') {
        return handler.launch_visible_row(handler.context, character - '1');
    }
    return false;
}

fn isCommandCharacter(event: objc.Id, expected: u8) bool {
    const character = commandCharacter(event) orelse return false;
    if (character > std.math.maxInt(u8)) return false;
    return std.ascii.toLower(@as(u8, @intCast(character))) == expected;
}

fn commandCharacter(event: objc.Id) ?u16 {
    if (event == null) return null;
    const flags = objc.msgSendUInteger0(event, objc.sel("modifierFlags"));
    if (flags & command_modifier == 0) return null;

    const characters_id = objc.msgSendId0(event, objc.sel("charactersIgnoringModifiers"));
    if (characters_id == null) return null;
    const characters = objc.String{ .object = .wrap(characters_id) };
    if (characters.length() == 1) {
        return characters.characterAtIndex(0);
    }

    return null;
}
