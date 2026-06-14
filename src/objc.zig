const std = @import("std");

pub const CGFloat = f64;
pub const NSInteger = isize;
pub const NSUInteger = usize;
pub const BOOL = bool;

pub const Id = ?*anyopaque;
pub const Class = ?*anyopaque;
pub const Selector = ?*anyopaque;
pub const IMP = *const fn () callconv(.c) void;

pub const Point = extern struct {
    x: CGFloat,
    y: CGFloat,
};

pub const Size = extern struct {
    width: CGFloat,
    height: CGFloat,
};

pub const Rect = extern struct {
    origin: Point,
    size: Size,
};

pub const Range = extern struct {
    location: NSUInteger,
    length: NSUInteger,
};

extern "c" fn objc_getClass(name: [*:0]const u8) Class;
extern "c" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class;
extern "c" fn objc_registerClassPair(class: Class) void;
extern "c" fn sel_registerName(name: [*:0]const u8) Selector;
extern "c" fn class_addMethod(class: Class, name: Selector, imp: IMP, types: [*:0]const u8) bool;
extern "c" fn objc_msgSend() void;

pub fn cls(name: [*:0]const u8) Class {
    return objc_getClass(name);
}

pub fn sel(name: [*:0]const u8) Selector {
    return sel_registerName(name);
}

pub fn allocateClassPair(superclass: Class, name: [*:0]const u8) Class {
    return objc_allocateClassPair(superclass, name, 0);
}

pub fn registerClassPair(class: Class) void {
    objc_registerClassPair(class);
}

pub fn addMethod(class: Class, name: Selector, imp: anytype, types: [*:0]const u8) bool {
    return class_addMethod(class, name, @ptrCast(imp), types);
}

pub const Object = struct {
    id: Id = null,

    pub fn wrap(id: Id) Object {
        return .{ .id = id };
    }

    pub fn nil() Object {
        return .{};
    }

    pub fn isNil(self: Object) bool {
        return self.id == null;
    }

    pub fn alloc(class_name: [*:0]const u8) Object {
        return .wrap(msgSendId0(cls(class_name), sel("alloc")));
    }

    pub fn new(class_name: [*:0]const u8) Object {
        return .wrap(msgSendId0(cls(class_name), sel("new")));
    }
};

pub const String = struct {
    object: Object = .{},

    pub fn fromUtf8(allocator: std.mem.Allocator, text: []const u8) String {
        const z = allocator.dupeZ(u8, text) catch unreachable;
        return .{ .object = .wrap(msgSendIdCString(cls("NSString"), sel("stringWithUTF8String:"), z.ptr)) };
    }

    pub fn utf8(self: String) [*:0]const u8 {
        return msgSendCString0(self.object.id, sel("UTF8String"));
    }
};

pub const Color = struct {
    object: Object = .{},

    pub fn windowBackground() Color {
        return named("windowBackgroundColor");
    }

    pub fn text() Color {
        return named("textColor");
    }

    pub fn textBackground() Color {
        return named("textBackgroundColor");
    }

    pub fn selectedContentBackground() Color {
        return named("selectedContentBackgroundColor");
    }

    pub fn selectedText() Color {
        return named("selectedTextColor");
    }

    pub fn alternateSelectedControlText() Color {
        return named("alternateSelectedControlTextColor");
    }

    pub fn clear() Color {
        return named("clearColor");
    }

    pub fn calibratedWhite(white: CGFloat, alpha: CGFloat) Color {
        const Fn = *const fn (Id, Selector, CGFloat, CGFloat) callconv(.c) Id;
        const f: Fn = @ptrCast(&objc_msgSend);
        return .{ .object = .wrap(f(cls("NSColor"), sel("colorWithCalibratedWhite:alpha:"), white, alpha)) };
    }

    pub fn rgb(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) Color {
        const Fn = *const fn (Id, Selector, CGFloat, CGFloat, CGFloat, CGFloat) callconv(.c) Id;
        const f: Fn = @ptrCast(&objc_msgSend);
        return .{ .object = .wrap(f(cls("NSColor"), sel("colorWithCalibratedRed:green:blue:alpha:"), red, green, blue, alpha)) };
    }

    pub fn cgColor(self: Color) Object {
        return .wrap(msgSendId0(self.object.id, sel("CGColor")));
    }

    fn named(selector_name: [*:0]const u8) Color {
        return .{ .object = .wrap(msgSendId0(cls("NSColor"), sel(selector_name))) };
    }
};

pub const Font = struct {
    object: Object = .{},

    pub fn system(size: CGFloat) Font {
        const Fn = *const fn (Id, Selector, CGFloat) callconv(.c) Id;
        const f: Fn = @ptrCast(&objc_msgSend);
        return .{ .object = .wrap(f(cls("NSFont"), sel("systemFontOfSize:"), size)) };
    }
};

pub const Application = struct {
    object: Object = .{},

    pub const ActivationPolicy = enum(NSInteger) {
        regular = 0,
        accessory = 1,
        prohibited = 2,
    };

    pub fn shared() Application {
        return .{ .object = .wrap(msgSendId0(cls("NSApplication"), sel("sharedApplication"))) };
    }

    pub fn setActivationPolicy(self: Application, policy: ActivationPolicy) void {
        msgSendVoidInt(self.object.id, sel("setActivationPolicy:"), @intFromEnum(policy));
    }

    pub fn activateIgnoringOtherApps(self: Application, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("activateIgnoringOtherApps:"), value);
    }

    pub fn run(self: Application) noreturn {
        msgSendVoid0(self.object.id, sel("run"));
        unreachable;
    }
};

pub const Panel = struct {
    object: Object = .{},

    pub const BackingStore = enum(NSUInteger) {
        buffered = 2,
    };

    pub const Level = enum(NSInteger) {
        floating = 3,
    };

    pub const Style = struct {
        titled: bool = false,
        closable: bool = false,
        miniaturizable: bool = false,
        resizable: bool = false,
        nonactivating: bool = false,

        pub fn mask(self: Style) NSUInteger {
            var value: NSUInteger = 0;
            if (self.titled) value |= 1 << 0;
            if (self.closable) value |= 1 << 1;
            if (self.miniaturizable) value |= 1 << 2;
            if (self.resizable) value |= 1 << 3;
            if (self.nonactivating) value |= 1 << 7;
            return value;
        }
    };

    pub const Options = struct {
        class_name: [*:0]const u8 = "NSPanel",
        content_rect: Rect,
        style: Style = .{},
        backing: BackingStore = .buffered,
        should_defer: BOOL = false,
    };

    pub fn create(options: Options) Panel {
        const allocated = Object.alloc(options.class_name);
        return .{ .object = .wrap(msgSendIdRectStyleBackingDefer(
            allocated.id,
            sel("initWithContentRect:styleMask:backing:defer:"),
            options.content_rect,
            options.style.mask(),
            @intFromEnum(options.backing),
            options.should_defer,
        )) };
    }

    pub fn setOpaque(self: Panel, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setOpaque:"), value);
    }

    pub fn setBackgroundColor(self: Panel, color: Color) void {
        msgSendVoidId(self.object.id, sel("setBackgroundColor:"), color.object.id);
    }

    pub fn setMovableByWindowBackground(self: Panel, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setMovableByWindowBackground:"), value);
    }

    pub fn setHidesOnDeactivate(self: Panel, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setHidesOnDeactivate:"), value);
    }

    pub fn setLevel(self: Panel, level: Level) void {
        msgSendVoidInt(self.object.id, sel("setLevel:"), @intFromEnum(level));
    }

    pub fn setDelegate(self: Panel, delegate: Object) void {
        msgSendVoidId(self.object.id, sel("setDelegate:"), delegate.id);
    }

    pub fn contentView(self: Panel) View {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("contentView"))) };
    }

    pub fn makeKeyAndOrderFront(self: Panel) void {
        msgSendVoidId(self.object.id, sel("makeKeyAndOrderFront:"), null);
    }

    pub fn makeFirstResponder(self: Panel, object: Object) void {
        msgSendVoidId(self.object.id, sel("makeFirstResponder:"), object.id);
    }

    pub fn orderOut(self: Panel) void {
        msgSendVoidId(self.object.id, sel("orderOut:"), null);
    }

    pub fn setFrameOrigin(self: Panel, point: Point) void {
        msgSendVoidPoint(self.object.id, sel("setFrameOrigin:"), point);
    }
};

pub const View = struct {
    object: Object = .{},

    pub fn setWantsLayer(self: View, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setWantsLayer:"), value);
    }

    pub fn layer(self: View) Layer {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("layer"))) };
    }

    pub fn addSubview(self: View, view: anytype) void {
        msgSendVoidId(self.object.id, sel("addSubview:"), view.object.id);
    }
};

pub const Layer = struct {
    object: Object = .{},

    pub fn setBackgroundColor(self: Layer, color: Object) void {
        msgSendVoidId(self.object.id, sel("setBackgroundColor:"), color.id);
    }

    pub fn setCornerRadius(self: Layer, radius: CGFloat) void {
        const Fn = *const fn (Id, Selector, CGFloat) callconv(.c) void;
        const f: Fn = @ptrCast(&objc_msgSend);
        f(self.object.id, sel("setCornerRadius:"), radius);
    }
};

pub const TextField = struct {
    object: Object = .{},

    pub const Options = struct {
        frame: Rect,
        font_size: CGFloat,
        text_color: Color,
        background_color: Color,
        editable: BOOL,
        corner_radius: CGFloat = 0,
    };

    pub fn create(options: Options) TextField {
        const allocated = Object.alloc("NSTextField");
        const field = TextField{ .object = .wrap(msgSendIdRect(allocated.id, sel("initWithFrame:"), options.frame)) };
        field.setBordered(false);
        field.setBezeled(false);
        field.setEditable(options.editable);
        field.setSelectable(options.editable);
        field.setFont(Font.system(options.font_size));
        field.setTextColor(options.text_color);
        field.setBackgroundColor(options.background_color);
        field.setDrawsBackground(true);
        field.setWantsLayer(true);
        field.layer().setCornerRadius(options.corner_radius);
        return field;
    }

    pub fn isNil(self: TextField) bool {
        return self.object.isNil();
    }

    pub fn setDelegate(self: TextField, delegate: Object) void {
        msgSendVoidId(self.object.id, sel("setDelegate:"), delegate.id);
    }

    pub fn setStringValue(self: TextField, value: String) void {
        msgSendVoidId(self.object.id, sel("setStringValue:"), value.object.id);
    }

    pub fn stringValue(self: TextField) String {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("stringValue"))) };
    }

    pub fn setBackgroundColor(self: TextField, color: Color) void {
        msgSendVoidId(self.object.id, sel("setBackgroundColor:"), color.object.id);
    }

    pub fn setTextColor(self: TextField, color: Color) void {
        msgSendVoidId(self.object.id, sel("setTextColor:"), color.object.id);
    }

    fn setBordered(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setBordered:"), value);
    }

    fn setBezeled(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setBezeled:"), value);
    }

    fn setEditable(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setEditable:"), value);
    }

    fn setSelectable(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setSelectable:"), value);
    }

    fn setFont(self: TextField, font: Font) void {
        msgSendVoidId(self.object.id, sel("setFont:"), font.object.id);
    }

    fn setDrawsBackground(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setDrawsBackground:"), value);
    }

    fn setWantsLayer(self: TextField, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("setWantsLayer:"), value);
    }

    fn layer(self: TextField) Layer {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("layer"))) };
    }
};

pub const Screen = struct {
    object: Object = .{},

    pub fn main() Screen {
        return .{ .object = .wrap(msgSendId0(cls("NSScreen"), sel("mainScreen"))) };
    }

    pub fn visibleFrame(self: Screen) Rect {
        return msgSendRect0(self.object.id, sel("visibleFrame"));
    }
};

pub const Cursor = struct {
    object: Object = .{},

    pub fn arrow() Cursor {
        return .{ .object = .wrap(msgSendId0(cls("NSCursor"), sel("arrowCursor"))) };
    }

    pub fn set(self: Cursor) void {
        msgSendVoid0(self.object.id, sel("set"));
    }
};

pub fn msgSendId0(recv: Id, op: Selector) Id {
    const Fn = *const fn (Id, Selector) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op);
}

pub fn msgSendVoid0(recv: Id, op: Selector) void {
    const Fn = *const fn (Id, Selector) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op);
}

pub fn msgSendVoidId(recv: Id, op: Selector, arg: Id) void {
    const Fn = *const fn (Id, Selector, Id) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, arg);
}

pub fn msgSendVoidBool(recv: Id, op: Selector, arg: BOOL) void {
    const Fn = *const fn (Id, Selector, BOOL) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, arg);
}

pub fn msgSendVoidInt(recv: Id, op: Selector, arg: NSInteger) void {
    const Fn = *const fn (Id, Selector, NSInteger) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, arg);
}

pub fn msgSendVoidPoint(recv: Id, op: Selector, point: Point) void {
    const Fn = *const fn (Id, Selector, Point) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, point);
}

pub fn msgSendIdCString(recv: Id, op: Selector, arg: [*:0]const u8) Id {
    const Fn = *const fn (Id, Selector, [*:0]const u8) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, arg);
}

pub fn msgSendIdRect(recv: Id, op: Selector, rect: Rect) Id {
    const Fn = *const fn (Id, Selector, Rect) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, rect);
}

pub fn msgSendIdRectStyleBackingDefer(recv: Id, op: Selector, rect: Rect, style: NSUInteger, backing: NSUInteger, should_defer: BOOL) Id {
    const Fn = *const fn (Id, Selector, Rect, NSUInteger, NSUInteger, BOOL) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, rect, style, backing, should_defer);
}

pub fn msgSendRect0(recv: Id, op: Selector) Rect {
    const Fn = *const fn (Id, Selector) callconv(.c) Rect;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op);
}

pub fn msgSendCString0(recv: Id, op: Selector) [*:0]const u8 {
    const Fn = *const fn (Id, Selector) callconv(.c) [*:0]const u8;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op);
}
