const objc = @import("objc.zig");

pub const Theme = struct {
    glass_style: objc.GlassSurface.Style,
    panel: objc.Color,
    input: objc.Color,
    text: objc.Color,
    muted: objc.Color,
    selected: objc.Color,
    selected_text: objc.Color,
    divider: objc.Color,
    accent: objc.Color,
    cursor: objc.Color,
    shortcut_fill: objc.Color,
    shortcut_text: objc.Color,
    shortcut_border: objc.Color,

    pub fn current(app: objc.Application) Theme {
        if (app.isDarkMode()) {
            return .{
                .glass_style = Glass.style,
                .panel = hexColorAlpha(Palette.Dark.glass_tint, Alpha.Dark.panel),
                .input = objc.Color.clear(),
                .text = hexColor(Palette.Dark.ink),
                .muted = hexColor(Palette.Dark.quiet_ink),
                .selected = hexColorAlpha(Palette.Dark.selected_band, Alpha.Dark.selected),
                .selected_text = hexColor(Palette.Dark.selected_ink),
                .divider = hexColorAlpha(Palette.Dark.divider, Alpha.Dark.divider),
                .accent = hexColorAlpha(Palette.glass_edge, Alpha.glass_edge),
                .cursor = hexColorAlpha(Palette.cursor, Alpha.cursor),
                .shortcut_fill = hexColor(Palette.Dark.key_fill),
                .shortcut_text = hexColor(Palette.Dark.key_text),
                .shortcut_border = hexColorAlpha(Palette.Dark.key_fill, Alpha.Dark.shortcut_border),
            };
        }

        return .{
            .glass_style = Glass.style,
            .panel = hexColorAlpha(Palette.Light.glass_tint, Alpha.Light.panel),
            .input = objc.Color.clear(),
            .text = hexColor(Palette.Light.ink),
            .muted = hexColor(Palette.Light.quiet_ink),
            .selected = hexColorAlpha(Palette.Light.selected_band, Alpha.Light.selected),
            .selected_text = hexColor(Palette.Light.selected_ink),
            .divider = hexColorAlpha(Palette.Light.divider, Alpha.Light.divider),
            .accent = hexColorAlpha(Palette.glass_edge, Alpha.glass_edge),
            .cursor = hexColorAlpha(Palette.cursor, Alpha.cursor),
            .shortcut_fill = hexColor(Palette.Light.key_fill),
            .shortcut_text = hexColor(Palette.Light.key_text),
            .shortcut_border = hexColorAlpha(Palette.Light.key_fill, Alpha.Light.shortcut_border),
        };
    }
};

pub const Glass = struct {
    pub const style: objc.GlassSurface.Style = .regular;
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
    const cursor = 0xd1dbef;

    const Light = struct {
        const glass_tint = 0x3f4f93;
        const ink = 0xffffff;
        const quiet_ink = 0xd9ddf2;
        const selected_band = 0x93a0f0;
        const selected_ink = 0xffffff;
        const divider = 0xffffff;
        const key_fill = 0xffffff;
        const key_text = 0x272d48;
    };

    const Dark = struct {
        const glass_tint = 0x303f78;
        const ink = 0xf7f8ff;
        const quiet_ink = 0xc5cae2;
        const selected_band = 0x8190ec;
        const selected_ink = 0xffffff;
        const divider = 0xffffff;
        const key_fill = 0xffffff;
        const key_text = 0x252b46;
    };
};

const Alpha = struct {
    const glass_edge: objc.CGFloat = 0.70;
    const cursor: objc.CGFloat = 0.72;

    const Light = struct {
        const panel: objc.CGFloat = 0.52;
        const selected: objc.CGFloat = 0.76;
        const divider: objc.CGFloat = 0.44;
        const shortcut_border: objc.CGFloat = 0.25;
    };

    const Dark = struct {
        const panel: objc.CGFloat = 0.68;
        const selected: objc.CGFloat = 0.74;
        const divider: objc.CGFloat = 0.42;
        const shortcut_border: objc.CGFloat = 0.20;
    };
};
