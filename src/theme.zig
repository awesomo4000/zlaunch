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
                .panel = hexColor(Palette.Dark.near_black),
                .input = hexColor(Palette.Dark.prompt_panel),
                .text = hexColor(Palette.Dark.ink),
                .muted = hexColor(Palette.Dark.quiet_ink),
                .selected = hexColor(Palette.Dark.selected_band),
                .selected_text = hexColor(Palette.Dark.selected_ink),
                .divider = hexColor(Palette.Dark.divider),
                .accent = hexColor(Palette.steel_cyan),
                .shortcut_fill = hexColor(Palette.amber),
                .shortcut_text = hexColor(Palette.Dark.near_black),
                .shortcut_border = hexColor(Palette.Dark.divider),
            };
        }

        return .{
            .panel = hexColor(Palette.Light.warm_paper),
            .input = hexColor(Palette.Light.prompt_panel),
            .text = hexColor(Palette.Light.ink),
            .muted = hexColor(Palette.Light.quiet_ink),
            .selected = hexColor(Palette.Light.selected_band),
            .selected_text = hexColor(Palette.Light.selected_ink),
            .divider = hexColor(Palette.Light.divider),
            .accent = hexColor(Palette.steel_cyan),
            .shortcut_fill = hexColor(Palette.amber),
            .shortcut_text = hexColor(Palette.Light.prompt_panel),
            .shortcut_border = hexColor(Palette.Light.divider),
        };
    }
};

fn hexColor(comptime value: u24) objc.Color {
    const r: objc.CGFloat = @floatFromInt((value >> 16) & 0xff);
    const g: objc.CGFloat = @floatFromInt((value >> 8) & 0xff);
    const b: objc.CGFloat = @floatFromInt(value & 0xff);
    return objc.Color.rgb(r / 255.0, g / 255.0, b / 255.0, 1.0);
}

const Palette = struct {
    const steel_cyan = 0x2e6f8e;
    const amber = 0xa8632f;

    const Light = struct {
        const warm_paper = 0xf4f1ea;
        const prompt_panel = 0xfdfcf8;
        const ink = 0x2e2e2b;
        const quiet_ink = 0x948f85;
        const selected_band = 0xebe6db;
        const selected_ink = 0x242527;
        const divider = 0xd8d2c4;
    };

    const Dark = struct {
        const near_black = 0x1a1b1e;
        const prompt_panel = 0x1f2225;
        const ink = 0xc2c7d1;
        const quiet_ink = 0x6b707a;
        const selected_band = 0x282a2e;
        const selected_ink = 0xe6ebf0;
        const divider = 0x34373c;
    };
};
