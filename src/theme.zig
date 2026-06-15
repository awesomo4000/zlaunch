const objc = @import("objc.zig");

pub const Theme = struct {
    glass: GlassTheme,
    search: SearchTheme,
    row: RowTheme,
    shortcut: ShortcutTheme,
    divider: objc.Color,

    pub fn current(app: objc.Application) Theme {
        if (app.isDarkMode()) {
            return .{
                .glass = .{
                    .style = Glass.style,
                    .variant = Glass.variant,
                    .tint = hexColorAlpha(Palette.Dark.glass_tint, Alpha.Dark.panel),
                    .gradient_start = hexColorAlpha(Palette.Dark.gradient_start, Alpha.Dark.gradient_start),
                    .gradient_end = hexColorAlpha(Palette.Dark.gradient_end, Alpha.Dark.gradient_end),
                },
                .search = .{
                    .fill = objc.Color.clear(),
                    .text = hexColor(Palette.Dark.ink),
                    .icon = hexColor(Palette.Dark.quiet_ink),
                    .accent = hexColorAlpha(Palette.glass_edge, Alpha.glass_edge),
                    .cursor = hexColorAlpha(Palette.cursor, Alpha.cursor),
                },
                .row = .{
                    .text = hexColor(Palette.Dark.ink),
                    .muted = hexColor(Palette.Dark.quiet_ink),
                    .selected = hexColorAlpha(Palette.Dark.selected_band, Alpha.Dark.selected),
                    .selected_text = hexColor(Palette.Dark.selected_ink),
                },
                .shortcut = .{
                    .fill = hexColor(Palette.Dark.key_fill),
                    .text = hexColor(Palette.Dark.key_text),
                    .border = hexColorAlpha(Palette.Dark.key_fill, Alpha.Dark.shortcut_border),
                },
                .divider = hexColorAlpha(Palette.Dark.divider, Alpha.Dark.divider),
            };
        }

        return .{
            .glass = .{
                .style = Glass.style,
                .variant = Glass.variant,
                .tint = hexColorAlpha(Palette.Light.glass_tint, Alpha.Light.panel),
                .gradient_start = hexColorAlpha(Palette.Light.gradient_start, Alpha.Light.gradient_start),
                .gradient_end = hexColorAlpha(Palette.Light.gradient_end, Alpha.Light.gradient_end),
            },
            .search = .{
                .fill = objc.Color.clear(),
                .text = hexColor(Palette.Light.ink),
                .icon = hexColor(Palette.Light.quiet_ink),
                .accent = hexColorAlpha(Palette.glass_edge, Alpha.glass_edge),
                .cursor = hexColorAlpha(Palette.cursor, Alpha.cursor),
            },
            .row = .{
                .text = hexColor(Palette.Light.ink),
                .muted = hexColor(Palette.Light.quiet_ink),
                .selected = hexColorAlpha(Palette.Light.selected_band, Alpha.Light.selected),
                .selected_text = hexColor(Palette.Light.selected_ink),
            },
            .shortcut = .{
                .fill = hexColor(Palette.Light.key_fill),
                .text = hexColor(Palette.Light.key_text),
                .border = hexColorAlpha(Palette.Light.key_fill, Alpha.Light.shortcut_border),
            },
            .divider = hexColorAlpha(Palette.Light.divider, Alpha.Light.divider),
        };
    }
};

pub const GlassTheme = struct {
    style: objc.GlassSurface.NativeStyle,
    variant: objc.GlassSurface.MaterialVariant,
    tint: objc.Color,
    gradient_start: objc.Color,
    gradient_end: objc.Color,
};

pub const SearchTheme = struct {
    fill: objc.Color,
    text: objc.Color,
    icon: objc.Color,
    accent: objc.Color,
    cursor: objc.Color,
};

pub const RowTheme = struct {
    text: objc.Color,
    muted: objc.Color,
    selected: objc.Color,
    selected_text: objc.Color,
};

pub const ShortcutTheme = struct {
    fill: objc.Color,
    text: objc.Color,
    border: objc.Color,
};

pub const Glass = struct {
    pub const style: objc.GlassSurface.NativeStyle = .regular;
    pub const variant: objc.GlassSurface.MaterialVariant = .dock;
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
        const gradient_start = 0xaab6e5;
        const gradient_end = 0x5165c9;
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
        const gradient_start = 0xa0ace0;
        const gradient_end = 0x4559be;
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
        const gradient_start: objc.CGFloat = 0.34;
        const gradient_end: objc.CGFloat = 0.46;
        const selected: objc.CGFloat = 0.76;
        const divider: objc.CGFloat = 0.44;
        const shortcut_border: objc.CGFloat = 0.25;
    };

    const Dark = struct {
        const panel: objc.CGFloat = 0.68;
        const gradient_start: objc.CGFloat = 0.30;
        const gradient_end: objc.CGFloat = 0.44;
        const selected: objc.CGFloat = 0.74;
        const divider: objc.CGFloat = 0.42;
        const shortcut_border: objc.CGFloat = 0.20;
    };
};
