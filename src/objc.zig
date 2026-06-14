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

const Super = extern struct {
    receiver: Id,
    super_class: Class,
};

extern "c" fn objc_getClass(name: [*:0]const u8) Class;
extern "c" fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Class;
extern "c" fn objc_registerClassPair(class: Class) void;
extern "c" fn sel_registerName(name: [*:0]const u8) Selector;
extern "c" fn class_addMethod(class: Class, name: Selector, imp: IMP, types: [*:0]const u8) bool;
extern "c" fn objc_msgSend() void;
extern "c" fn objc_msgSendSuper() void;

var text_field_cell_class_registered = false;

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

    pub fn retain(self: Object) Object {
        if (self.isNil()) return self;
        return .wrap(msgSendId0(self.id, sel("retain")));
    }

    pub fn release(self: Object) void {
        if (self.isNil()) return;
        msgSendVoid0(self.id, sel("release"));
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

    pub fn fromStatic(text: [*:0]const u8) String {
        return .{ .object = .wrap(msgSendIdCString(cls("NSString"), sel("stringWithUTF8String:"), text)) };
    }

    pub fn fromUtf8(allocator: std.mem.Allocator, text: []const u8) String {
        const z = allocator.dupeZ(u8, text) catch unreachable;
        return .{ .object = .wrap(msgSendIdCString(cls("NSString"), sel("stringWithUTF8String:"), z.ptr)) };
    }

    pub fn utf8(self: String) [*:0]const u8 {
        return msgSendCString0(self.object.id, sel("UTF8String"));
    }

    pub fn isEqualToString(self: String, other: String) BOOL {
        return msgSendBoolId(self.object.id, sel("isEqualToString:"), other.object.id);
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

    pub fn monospacedSystem(size: CGFloat, weight: CGFloat) Font {
        const Fn = *const fn (Id, Selector, CGFloat, CGFloat) callconv(.c) Id;
        const f: Fn = @ptrCast(&objc_msgSend);
        return .{ .object = .wrap(f(cls("NSFont"), sel("monospacedSystemFontOfSize:weight:"), size, weight)) };
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

    pub fn isDarkMode(self: Application) BOOL {
        const appearance = Object.wrap(msgSendId0(self.object.id, sel("effectiveAppearance")));
        const names = Array.withObjects(&.{
            String.fromStatic("NSAppearanceNameDarkAqua").object,
            String.fromStatic("NSAppearanceNameAqua").object,
        });
        const matched = String{ .object = .wrap(msgSendIdId(appearance.id, sel("bestMatchFromAppearancesWithNames:"), names.object.id)) };
        return matched.isEqualToString(String.fromStatic("NSAppearanceNameDarkAqua"));
    }

    pub fn activateIgnoringOtherApps(self: Application, value: BOOL) void {
        msgSendVoidBool(self.object.id, sel("activateIgnoringOtherApps:"), value);
    }

    pub fn run(self: Application) noreturn {
        msgSendVoid0(self.object.id, sel("run"));
        unreachable;
    }
};

pub const Array = struct {
    object: Object = .{},

    pub fn withObjects(objects: []const Object) Array {
        switch (objects.len) {
            0 => return .{ .object = .wrap(msgSendId0(cls("NSArray"), sel("array"))) },
            1 => return .{ .object = .wrap(msgSendIdId(cls("NSArray"), sel("arrayWithObject:"), objects[0].id)) },
            2 => {
                var ids = [_]Id{ objects[0].id, objects[1].id };
                const allocated = Object.alloc("NSArray");
                return .{ .object = .wrap(msgSendIdObjectBufferCount(allocated.id, sel("initWithObjects:count:"), &ids, ids.len)) };
            },
            else => @panic("Array.withObjects currently supports at most two objects"),
        }
    }
};

pub const Workspace = struct {
    object: Object = .{},

    pub fn shared() Workspace {
        return .{ .object = .wrap(msgSendId0(cls("NSWorkspace"), sel("sharedWorkspace"))) };
    }

    pub fn frontmostApplication(self: Workspace) RunningApplication {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("frontmostApplication"))) };
    }
};

pub const RunningApplication = struct {
    object: Object = .{},

    pub const ActivationOptions = struct {
        all_windows: bool = false,
        ignoring_other_apps: bool = false,

        fn mask(self: ActivationOptions) NSUInteger {
            var value: NSUInteger = 0;
            if (self.all_windows) value |= 1 << 0;
            if (self.ignoring_other_apps) value |= 1 << 1;
            return value;
        }
    };

    pub fn isNil(self: RunningApplication) bool {
        return self.object.isNil();
    }

    pub fn retain(self: RunningApplication) RunningApplication {
        return .{ .object = self.object.retain() };
    }

    pub fn release(self: RunningApplication) void {
        self.object.release();
    }

    pub fn activate(self: RunningApplication, options: ActivationOptions) void {
        _ = msgSendBoolUInteger(self.object.id, sel("activateWithOptions:"), options.mask());
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

    pub fn setBorderColor(self: Layer, color: Object) void {
        msgSendVoidId(self.object.id, sel("setBorderColor:"), color.id);
    }

    pub fn setBorderWidth(self: Layer, width: CGFloat) void {
        const Fn = *const fn (Id, Selector, CGFloat) callconv(.c) void;
        const f: Fn = @ptrCast(&objc_msgSend);
        f(self.object.id, sel("setBorderWidth:"), width);
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
        font: Font,
        text_color: Color,
        background_color: Color,
        editable: BOOL,
        corner_radius: CGFloat = 0,
    };

    pub fn create(options: Options) TextField {
        ensureTextFieldCellClass();

        const allocated = Object.alloc("NSTextField");
        const field = TextField{ .object = .wrap(msgSendIdRect(allocated.id, sel("initWithFrame:"), options.frame)) };
        field.setCell(createTextFieldCell());
        field.setBordered(false);
        field.setBezeled(false);
        field.setEditable(options.editable);
        field.setSelectable(options.editable);
        field.setFont(options.font);
        field.setFocusRingType(.none);
        field.setTextColor(options.text_color);
        field.setDrawsBackground(false);
        field.setWantsLayer(true);
        field.layer().setCornerRadius(options.corner_radius);
        field.setFillColor(options.background_color);
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

    pub fn setFillColor(self: TextField, color: Color) void {
        self.layer().setBackgroundColor(color.cgColor());
    }

    pub fn setTextColor(self: TextField, color: Color) void {
        msgSendVoidId(self.object.id, sel("setTextColor:"), color.object.id);
    }

    pub fn setBorder(self: TextField, width: CGFloat, color: Color) void {
        const field_layer = self.layer();
        field_layer.setBorderWidth(width);
        field_layer.setBorderColor(color.cgColor());
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

    const FocusRingType = enum(NSUInteger) {
        default = 0,
        none = 1,
        exterior = 2,
    };

    fn setFocusRingType(self: TextField, value: FocusRingType) void {
        msgSendVoidUInteger(self.object.id, sel("setFocusRingType:"), @intFromEnum(value));
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

    fn setCell(self: TextField, cell: Object) void {
        msgSendVoidId(self.object.id, sel("setCell:"), cell.id);
    }

    fn layer(self: TextField) Layer {
        return .{ .object = .wrap(msgSendId0(self.object.id, sel("layer"))) };
    }
};

fn ensureTextFieldCellClass() void {
    if (text_field_cell_class_registered) return;
    text_field_cell_class_registered = true;

    const class = allocateClassPair(cls("NSTextFieldCell"), "ZLPaddedTextFieldCell");
    if (class != null) {
        const rect_types = "{CGRect={CGPoint=dd}{CGSize=dd}}@:{CGRect={CGPoint=dd}{CGSize=dd}}";
        _ = addMethod(class, sel("drawingRectForBounds:"), &paddedTextRect, rect_types);
        _ = addMethod(class, sel("titleRectForBounds:"), &paddedTextRect, rect_types);
        _ = addMethod(class, sel("editWithFrame:inView:editor:delegate:event:"), &editWithPaddedFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}@@@@");
        _ = addMethod(class, sel("selectWithFrame:inView:editor:delegate:start:length:"), &selectWithPaddedFrame, "v@:{CGRect={CGPoint=dd}{CGSize=dd}}@@@QQ");
        registerClassPair(class);
    }
}

fn createTextFieldCell() Object {
    const allocated = Object.alloc("ZLPaddedTextFieldCell");
    const empty = Object.wrap(msgSendIdCString(cls("NSString"), sel("stringWithUTF8String:"), ""));
    return .wrap(msgSendIdId(allocated.id, sel("initTextCell:"), empty.id));
}

fn paddedTextRect(self: Id, _: Selector, bounds: Rect) callconv(.c) Rect {
    return textRect(self, bounds);
}

fn textRect(self: Id, bounds: Rect) Rect {
    const padding: CGFloat = 10;
    var rect = bounds;
    rect.origin.x += padding;
    rect.size.width = @max(@as(CGFloat, 0), rect.size.width - padding * 2);

    const font = msgSendId0(self, sel("font"));
    const line_height = if (font == null) @as(CGFloat, 17) else msgSendCGFloat0(font, sel("defaultLineHeightForFont"));
    const inset = @max(@as(CGFloat, 0), (bounds.size.height - line_height) / 2);
    rect.origin.y += inset;
    rect.size.height = line_height;
    return rect;
}

fn editWithPaddedFrame(self: Id, _: Selector, frame: Rect, control_view: Id, editor: Id, delegate: Id, event: Id) callconv(.c) void {
    msgSendSuperVoidRectIdIdIdId(
        self,
        cls("NSTextFieldCell"),
        sel("editWithFrame:inView:editor:delegate:event:"),
        textRect(self, frame),
        control_view,
        editor,
        delegate,
        event,
    );
}

fn selectWithPaddedFrame(self: Id, _: Selector, frame: Rect, control_view: Id, editor: Id, delegate: Id, start: NSUInteger, length: NSUInteger) callconv(.c) void {
    msgSendSuperVoidRectIdIdIdUIntegerUInteger(
        self,
        cls("NSTextFieldCell"),
        sel("selectWithFrame:inView:editor:delegate:start:length:"),
        textRect(self, frame),
        control_view,
        editor,
        delegate,
        start,
        length,
    );
}

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

pub fn msgSendIdId(recv: Id, op: Selector, arg: Id) Id {
    const Fn = *const fn (Id, Selector, Id) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, arg);
}

pub fn msgSendIdObjectBufferCount(recv: Id, op: Selector, objects: [*]const Id, count: NSUInteger) Id {
    const Fn = *const fn (Id, Selector, [*]const Id, NSUInteger) callconv(.c) Id;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, objects, count);
}

pub fn msgSendBoolId(recv: Id, op: Selector, arg: Id) BOOL {
    const Fn = *const fn (Id, Selector, Id) callconv(.c) BOOL;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, arg);
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

pub fn msgSendVoidUInteger(recv: Id, op: Selector, arg: NSUInteger) void {
    const Fn = *const fn (Id, Selector, NSUInteger) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, arg);
}

pub fn msgSendBoolUInteger(recv: Id, op: Selector, arg: NSUInteger) BOOL {
    const Fn = *const fn (Id, Selector, NSUInteger) callconv(.c) BOOL;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op, arg);
}

pub fn msgSendCGFloat0(recv: Id, op: Selector) CGFloat {
    const Fn = *const fn (Id, Selector) callconv(.c) CGFloat;
    const f: Fn = @ptrCast(&objc_msgSend);
    return f(recv, op);
}

pub fn msgSendVoidPoint(recv: Id, op: Selector, point: Point) void {
    const Fn = *const fn (Id, Selector, Point) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSend);
    f(recv, op, point);
}

pub fn msgSendSuperVoidRectIdIdIdId(recv: Id, superclass: Class, op: Selector, rect: Rect, arg1: Id, arg2: Id, arg3: Id, arg4: Id) void {
    var super = Super{ .receiver = recv, .super_class = superclass };
    const Fn = *const fn (*Super, Selector, Rect, Id, Id, Id, Id) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSendSuper);
    f(&super, op, rect, arg1, arg2, arg3, arg4);
}

pub fn msgSendSuperVoidRectIdIdIdUIntegerUInteger(recv: Id, superclass: Class, op: Selector, rect: Rect, arg1: Id, arg2: Id, arg3: Id, arg4: NSUInteger, arg5: NSUInteger) void {
    var super = Super{ .receiver = recv, .super_class = superclass };
    const Fn = *const fn (*Super, Selector, Rect, Id, Id, Id, NSUInteger, NSUInteger) callconv(.c) void;
    const f: Fn = @ptrCast(&objc_msgSendSuper);
    f(&super, op, rect, arg1, arg2, arg3, arg4, arg5);
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
