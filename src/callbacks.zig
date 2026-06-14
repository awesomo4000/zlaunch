const objc = @import("objc.zig");

pub const Handler = struct {
    context: *anyopaque,
    text_changed: *const fn (*anyopaque) void,
    move_highlight: *const fn (*anyopaque, i32) void,
    launch_highlighted: *const fn (*anyopaque) void,
    launch_visible_row: *const fn (*anyopaque, usize) bool,
    dismiss: *const fn (*anyopaque) void,
};

const Command = enum {
    move_up,
    move_down,
    insert_newline,
    cancel_operation,
    unhandled,
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

    fn commandFor(self: CommandSelectors, selector: objc.Selector) Command {
        if (selector == self.move_up) return .move_up;
        if (selector == self.move_down) return .move_down;
        if (selector == self.insert_newline) return .insert_newline;
        if (selector == self.cancel_operation) return .cancel_operation;
        return .unhandled;
    }
};

var handler: Handler = undefined;
var command_selectors: CommandSelectors = undefined;

pub fn install(app_handler: Handler) objc.Object {
    handler = app_handler;
    command_selectors = .init();
    registerPanelClass();
    registerInputTextFieldClass();
    return registerDelegateClass();
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

fn registerInputTextFieldClass() void {
    const class = objc.allocateClassPair(objc.cls("NSTextField"), "ZLInputTextField");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("keyDown:"), &inputKeyDown, "v@:@");
        objc.registerClassPair(class);
    }
}

fn registerDelegateClass() objc.Object {
    const class = objc.allocateClassPair(objc.cls("NSObject"), "ZLDelegate");
    if (class != null) {
        _ = objc.addMethod(class, objc.sel("controlTextDidChange:"), &controlTextDidChange, "v@:@");
        _ = objc.addMethod(class, objc.sel("control:textView:shouldChangeCharactersInRange:replacementString:"), &shouldChangeText, "c@:@@{_NSRange=QQ}@");
        _ = objc.addMethod(class, objc.sel("control:textView:doCommandBySelector:"), &doCommandBySelector, "c@:@@:");
        _ = objc.addMethod(class, objc.sel("windowDidResignKey:"), &windowDidResignKey, "v@:@");
        objc.registerClassPair(class);
    }
    return objc.Object.new("ZLDelegate");
}

fn controlTextDidChange(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    handler.text_changed(handler.context);
}

fn shouldChangeText(_: objc.Id, _: objc.Selector, _: objc.Id, _: objc.Id, _: objc.Range, replacement: objc.Id) callconv(.c) objc.BOOL {
    return !tryLaunchNumber(replacement);
}

fn doCommandBySelector(_: objc.Id, _: objc.Selector, _: objc.Id, _: objc.Id, selector: objc.Selector) callconv(.c) objc.BOOL {
    switch (command_selectors.commandFor(selector)) {
        .move_up => handler.move_highlight(handler.context, -1),
        .move_down => handler.move_highlight(handler.context, 1),
        .insert_newline => handler.launch_highlighted(handler.context),
        .cancel_operation => handler.dismiss(handler.context),
        .unhandled => return false,
    }
    return true;
}

fn windowDidResignKey(_: objc.Id, _: objc.Selector, _: objc.Id) callconv(.c) void {
    handler.dismiss(handler.context);
}

fn inputKeyDown(self: objc.Id, _: objc.Selector, event: objc.Id) callconv(.c) void {
    const characters = objc.msgSendId0(event, objc.sel("charactersIgnoringModifiers"));
    if (tryLaunchNumber(characters)) return;

    objc.msgSendSuperVoidId(self, objc.cls("NSTextField"), objc.sel("keyDown:"), event);
}

fn tryLaunchNumber(characters_id: objc.Id) bool {
    if (characters_id == null) return false;

    const characters = objc.String{ .object = .wrap(characters_id) };
    if (characters.length() == 1) {
        const character = characters.characterAtIndex(0);
        if (character >= '1' and character <= '5') {
            return handler.launch_visible_row(handler.context, character - '1');
        }
    }

    return false;
}
