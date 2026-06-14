const std = @import("std");
const keymap = @import("keymap.zig");

pub const OSStatus = i32;

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
pub const EventHandlerCallRef = ?*opaque {};
pub const EventRef = ?*opaque {};
pub const HandlerProc = *const fn (EventHandlerCallRef, EventRef, ?*anyopaque) callconv(.c) OSStatus;

extern "c" fn RegisterEventHotKey(u32, u32, EventHotKeyID, EventTargetRef, u32, *EventHotKeyRef) OSStatus;
extern "c" fn GetApplicationEventTarget() EventTargetRef;
extern "c" fn InstallEventHandler(EventTargetRef, HandlerProc, usize, [*]const EventTypeSpec, ?*anyopaque, ?*EventHandlerRef) OSStatus;

var hotkey_ref: EventHotKeyRef = null;

pub fn register(handler: HandlerProc, binding: keymap.Key) void {
    const target = GetApplicationEventTarget();
    const event = [_]EventTypeSpec{.{ .eventClass = kEventClassKeyboard, .eventKind = kEventHotKeyPressed }};
    _ = InstallEventHandler(target, handler, 1, &event, null, null);
    _ = RegisterEventHotKey(binding.carbon_key_code, binding.carbon_modifiers, .{ .signature = fourcc("zlch"), .id = 1 }, target, 0, &hotkey_ref);
}

fn fourcc(comptime s: *const [4]u8) u32 {
    return std.mem.readInt(u32, s, .big);
}

const kEventClassKeyboard = fourcc("keyb");
const kEventHotKeyPressed: u32 = 5;
