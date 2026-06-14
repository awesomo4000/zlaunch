const std = @import("std");

pub const Key = struct {
    carbon_key_code: u32,
    carbon_modifiers: u32,
};

const carbon_cmd: u32 = 1 << 8;
const carbon_shift: u32 = 1 << 9;
const carbon_option: u32 = 1 << 11;
const carbon_control: u32 = 1 << 12;

pub const default_show_launcher = parse("cmd-space") orelse unreachable;

pub fn parse(text: []const u8) ?Key {
    var key_code: ?u32 = null;
    var modifiers: u32 = 0;

    var parts = std.mem.splitScalar(u8, text, '-');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) return null;

        if (modifierMask(part)) |mask| {
            modifiers |= mask;
            continue;
        }

        if (key_code != null) return null;
        key_code = keyCode(part) orelse return null;
    }

    return .{
        .carbon_key_code = key_code orelse return null,
        .carbon_modifiers = modifiers,
    };
}

fn modifierMask(part: []const u8) ?u32 {
    if (std.ascii.eqlIgnoreCase(part, "cmd") or
        std.ascii.eqlIgnoreCase(part, "command") or
        std.ascii.eqlIgnoreCase(part, "apple"))
    {
        return carbon_cmd;
    }
    if (std.ascii.eqlIgnoreCase(part, "shift")) return carbon_shift;
    if (std.ascii.eqlIgnoreCase(part, "option") or std.ascii.eqlIgnoreCase(part, "alt")) return carbon_option;
    if (std.ascii.eqlIgnoreCase(part, "ctrl") or std.ascii.eqlIgnoreCase(part, "control")) return carbon_control;
    return null;
}

fn keyCode(part: []const u8) ?u32 {
    if (std.ascii.eqlIgnoreCase(part, "space")) return 0x31;
    if (std.ascii.eqlIgnoreCase(part, "tab")) return 0x30;
    if (std.ascii.eqlIgnoreCase(part, "enter") or std.ascii.eqlIgnoreCase(part, "return")) return 0x24;
    if (std.ascii.eqlIgnoreCase(part, "esc") or std.ascii.eqlIgnoreCase(part, "escape")) return 0x35;

    if (part.len == 1) {
        return switch (std.ascii.toLower(part[0])) {
            'a' => 0x00,
            's' => 0x01,
            'd' => 0x02,
            'f' => 0x03,
            'h' => 0x04,
            'g' => 0x05,
            'z' => 0x06,
            'x' => 0x07,
            'c' => 0x08,
            'v' => 0x09,
            'b' => 0x0b,
            'q' => 0x0c,
            'w' => 0x0d,
            'e' => 0x0e,
            'r' => 0x0f,
            'y' => 0x10,
            't' => 0x11,
            '1' => 0x12,
            '2' => 0x13,
            '3' => 0x14,
            '4' => 0x15,
            '6' => 0x16,
            '5' => 0x17,
            '9' => 0x19,
            '7' => 0x1a,
            '8' => 0x1c,
            '0' => 0x1d,
            'o' => 0x1f,
            'u' => 0x20,
            'i' => 0x22,
            'p' => 0x23,
            'l' => 0x25,
            'j' => 0x26,
            'k' => 0x28,
            'n' => 0x2d,
            'm' => 0x2e,
            else => null,
        };
    }

    return null;
}

test "parse command space" {
    const key = parse("cmd-space").?;
    try std.testing.expectEqual(@as(u32, 0x31), key.carbon_key_code);
    try std.testing.expectEqual(@as(u32, carbon_cmd), key.carbon_modifiers);
}

test "parse aliases and digits" {
    const key = parse("apple-1").?;
    try std.testing.expectEqual(@as(u32, 0x12), key.carbon_key_code);
    try std.testing.expectEqual(@as(u32, carbon_cmd), key.carbon_modifiers);
}

test "parse multiple modifiers" {
    const key = parse("ctrl-option-m").?;
    try std.testing.expectEqual(@as(u32, 0x2e), key.carbon_key_code);
    try std.testing.expectEqual(@as(u32, carbon_control | carbon_option), key.carbon_modifiers);
}

test "reject unknown or ambiguous keys" {
    try std.testing.expect(parse("cmd-notakey") == null);
    try std.testing.expect(parse("cmd-m-space") == null);
}
