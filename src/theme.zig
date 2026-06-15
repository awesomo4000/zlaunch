const objc = @import("objc.zig");

pub const Theme = struct {
    panel: objc.Color,
    input: objc.Color,
    text: objc.Color,
    muted: objc.Color,
    selected: objc.Color,
    selected_text: objc.Color,
    divider: objc.Color,
    accent: objc.Color,
    shortcut_fill: objc.Color,
    shortcut_text: objc.Color,
    shortcut_border: objc.Color,

    pub fn current(app: objc.Application) Theme {
        if (app.isDarkMode()) {
            return .{
                .panel = hexColorAlpha(Palette.Dark.glass_tint, 0.78),
                .input = objc.Color.clear(),
                .text = hexColor(Palette.Dark.ink),
                .muted = hexColor(Palette.Dark.quiet_ink),
                .selected = hexColorAlpha(Palette.Dark.selected_band, 0.62),
                .selected_text = hexColor(Palette.Dark.selected_ink),
                .divider = hexColorAlpha(Palette.Dark.divider, 0.42),
                .accent = hexColorAlpha(Palette.glass_edge, 0.70),
                .shortcut_fill = hexColor(Palette.Dark.key_fill),
                .shortcut_text = hexColor(Palette.Dark.key_text),
                .shortcut_border = hexColorAlpha(Palette.Dark.key_fill, 0.20),
            };
        }

        return .{
            .panel = hexColorAlpha(Palette.Light.glass_tint, 0.62),
            .input = objc.Color.clear(),
            .text = hexColor(Palette.Light.ink),
            .muted = hexColor(Palette.Light.quiet_ink),
            .selected = hexColorAlpha(Palette.Light.selected_band, 0.66),
            .selected_text = hexColor(Palette.Light.selected_ink),
            .divider = hexColorAlpha(Palette.Light.divider, 0.44),
            .accent = hexColorAlpha(Palette.glass_edge, 0.70),
            .shortcut_fill = hexColor(Palette.Light.key_fill),
            .shortcut_text = hexColor(Palette.Light.key_text),
            .shortcut_border = hexColorAlpha(Palette.Light.key_fill, 0.25),
        };
    }
};

fn hexColor(comptime value: u24) objc.Color {
    return hexColorAlpha(value, 1.0);
}

fn hexColorAlpha(comptime value: u24, alpha: objc.CGFloat) objc.Color {
    const r: objc.CGFloat = @floatFromInt((value >> 16) & 0xff);
    const g: objc.CGFloat = @floatFromInt((value >> 8) & 0xff);
    const b: objc.CGFloat = @floatFromInt(value & 0xff);
    return objc.Color.rgb(r / 255.0, g / 255.0, b / 255.0, alpha);
}

const Palette = struct {
    const glass_edge = 0xc5cdfc;

    const Light = struct {
        const glass_tint = 0x3f4f93;
        const ink = 0xffffff;
        const quiet_ink = 0xd9ddf2;
        const selected_band = 0x6777d9;
        const selected_ink = 0xffffff;
        const divider = 0xffffff;
        const key_fill = 0xffffff;
        const key_text = 0x272d48;
    };

    const Dark = struct {
        const glass_tint = 0x303f78;
        const ink = 0xf7f8ff;
        const quiet_ink = 0xc5cae2;
        const selected_band = 0x5364c8;
        const selected_ink = 0xffffff;
        const divider = 0xffffff;
        const key_fill = 0xffffff;
        const key_text = 0x252b46;
    };
};
