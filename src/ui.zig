const std = @import("std");
const objc = @import("objc.zig");
const theme = @import("theme.zig");

pub const Layout = struct {
    pub const panel_width: objc.CGFloat = 560;
    pub const panel_height: objc.CGFloat = expanded_panel_height;
    pub const expanded_panel_height: objc.CGFloat = 344;
    pub const margin: objc.CGFloat = 16;
    pub const top_padding: objc.CGFloat = 30;
    pub const bottom_padding: objc.CGFloat = top_padding;
    pub const compact_panel_height: objc.CGFloat = top_padding + input_height + bottom_padding;
    pub const side_padding: objc.CGFloat = 28;
    pub const input_x: objc.CGFloat = side_padding;
    pub const input_width: objc.CGFloat = panel_width - side_padding * 2;
    pub const list_x: objc.CGFloat = side_padding;
    pub const list_width: objc.CGFloat = panel_width - side_padding * 2;
    pub const input_height: objc.CGFloat = 52;
    pub const query_font_size: objc.CGFloat = 22;
    pub const entry_font_size: objc.CGFloat = 17;
    pub const row_number_font_size: objc.CGFloat = 12;
    pub const row_height: objc.CGFloat = 46;
    pub const selected_bar_width: objc.CGFloat = 0;
    pub const row_number_width: objc.CGFloat = 24;
    pub const row_number_height: objc.CGFloat = 22;
    pub const row_number_x_offset: objc.CGFloat = 18;
    pub const row_number_y_offset: objc.CGFloat = (row_height - row_number_height) / 2;
    pub const icon_x_offset: objc.CGFloat = 62;
    pub const icon_size: objc.CGFloat = 34;
    pub const icon_y_offset: objc.CGFloat = (row_height - icon_size) / 2;
    pub const row_label_x_offset: objc.CGFloat = 112;
    pub const panel_corner_radius: objc.CGFloat = 30;
    pub const input_corner_radius: objc.CGFloat = 20;
    pub const row_corner_radius: objc.CGFloat = 12;
    pub const visible_rows = 5;
    pub const input_y: objc.CGFloat = inputY(.expanded);
    pub const divider_gap: objc.CGFloat = 8;
    pub const row_start_y: objc.CGFloat = input_y - margin - divider_gap - row_height;
    pub const divider_height: objc.CGFloat = 1;
    pub const list_bottom_y: objc.CGFloat = row_start_y - row_height * (visible_rows - 1);
    pub const divider_y: objc.CGFloat = bottom_padding;
    pub const divider_top_y: objc.CGFloat = input_y - divider_gap;

    pub fn panelHeight(mode: Mode) objc.CGFloat {
        return switch (mode) {
            .compact => compact_panel_height,
            .expanded => expanded_panel_height,
        };
    }

    pub fn inputY(mode: Mode) objc.CGFloat {
        return panelHeight(mode) - top_padding - input_height;
    }
};

pub const Mode = enum {
    compact,
    expanded,
};

pub const Rows = [Layout.visible_rows]Row;

pub const Elements = struct {
    panel: objc.Panel,
    glass: objc.GlassSurface,
    input: objc.TextField,
    rows: Rows,
    divider: objc.View,
};

pub const Row = struct {
    background: objc.View = .{},
    number_box: objc.View = .{},
    number: objc.TextLayer = .{},
    icon: objc.ImageView = .{},
    app_name: objc.TextField = .{},
    selected_bar: objc.View = .{},

    pub fn create(content: objc.View, y: objc.CGFloat, colors: theme.Theme) Row {
        const background = objc.View.create(.{
            .frame = rowFrame(y),
            .background_color = objc.Color.clear(),
        });
        background.setCornerRadius(Layout.row_corner_radius);
        content.addSubview(background);

        const selected_bar = objc.View.create(.{
            .frame = .{
                .origin = .{ .x = Layout.list_x, .y = y },
                .size = .{ .width = Layout.selected_bar_width, .height = Layout.row_height },
            },
            .background_color = colors.accent,
        });
        selected_bar.setHidden(true);
        content.addSubview(selected_bar);

        const number_box_frame = numberBoxFrame(y);
        const number_box = objc.View.create(.{
            .frame = number_box_frame,
            .background_color = objc.Color.clear(),
        });
        number_box.setBorder(1, colors.shortcut_border);
        number_box.setCornerRadius(6);
        content.addSubview(number_box);

        const number = objc.TextLayer.create(.{
            .frame = numberLayerFrame(number_box_frame),
            .text = objc.String.fromStatic(""),
            .font_size = Layout.row_number_font_size,
            .text_color = colors.shortcut_fill,
        });
        number_box.layer().addSublayer(number);

        const icon = objc.ImageView.create(.{
            .frame = iconFrame(y),
        });
        content.addSubview(icon);

        const app_name = makeTextField(.{
            .origin = .{ .x = Layout.list_x + Layout.row_label_x_offset, .y = y },
            .size = .{ .width = Layout.list_width - Layout.row_label_x_offset, .height = Layout.row_height },
        }, objc.Font.system(Layout.entry_font_size), colors.text, objc.Color.clear(), false);
        content.addSubview(app_name);

        return .{
            .background = background,
            .number_box = number_box,
            .number = number,
            .icon = icon,
            .app_name = app_name,
            .selected_bar = selected_bar,
        };
    }

    pub fn isEmpty(self: Row) bool {
        return self.app_name.isNil();
    }

    pub fn setAccent(self: Row, color: objc.Color) void {
        self.selected_bar.setFillColor(color);
    }

    pub fn showApp(self: Row, arena: std.mem.Allocator, slot: usize, name: []const u8, icon: objc.Image) void {
        var number_buf: [1]u8 = .{@intCast('1' + slot)};
        self.setHidden(false);
        self.number.setString(objc.String.fromUtf8(arena, &number_buf));
        self.icon.setImage(icon);
        self.app_name.setStringValue(objc.String.fromUtf8(arena, name));
    }

    pub fn clear(self: Row, arena: std.mem.Allocator) void {
        self.number.setString(objc.String.fromUtf8(arena, ""));
        self.icon.setImage(.nil());
        self.app_name.setStringValue(objc.String.fromUtf8(arena, ""));
        self.setHidden(true);
    }

    pub fn setSelected(self: Row, selected: bool, colors: theme.Theme) void {
        if (selected) {
            self.background.setFillColor(colors.selected);
            self.number_box.setFillColor(colors.shortcut_fill);
            self.number_box.setBorder(1, colors.shortcut_fill);
            self.number.setTextColor(colors.shortcut_text);
            self.app_name.setTextColor(colors.selected_text);
            self.selected_bar.setHidden(true);
            return;
        }

        self.background.setFillColor(objc.Color.clear());
        self.number_box.setFillColor(objc.Color.clear());
        self.number_box.setBorder(1, colors.shortcut_border);
        self.number.setTextColor(colors.shortcut_fill);
        self.app_name.setTextColor(colors.muted);
        self.selected_bar.setHidden(true);
    }

    pub fn setHidden(self: Row, hidden: bool) void {
        self.background.setHidden(hidden);
        self.number_box.setHidden(hidden);
        self.number.setHidden(hidden);
        self.icon.setHidden(hidden);
        self.app_name.setHidden(hidden);
        self.selected_bar.setHidden(hidden);
    }

    pub fn setY(self: Row, y: objc.CGFloat) void {
        self.background.setFrame(rowFrame(y));
        self.selected_bar.setFrame(.{
            .origin = .{ .x = Layout.list_x, .y = y },
            .size = .{ .width = Layout.selected_bar_width, .height = Layout.row_height },
        });
        const shortcut_frame = numberBoxFrame(y);
        self.number_box.setFrame(shortcut_frame);
        self.number.setFrame(numberLayerFrame(shortcut_frame));
        self.icon.setFrame(iconFrame(y));
        self.app_name.setFrame(.{
            .origin = .{ .x = Layout.list_x + Layout.row_label_x_offset, .y = y },
            .size = .{ .width = Layout.list_width - Layout.row_label_x_offset, .height = Layout.row_height },
        });
    }
};

pub fn build(app: objc.Application, delegate: objc.Object) Elements {
    const colors = theme.Theme.current(app);
    const panel = objc.Panel.create(.{
        .class_name = "ZLPanel",
        .content_rect = .{
            .origin = .{ .x = 0, .y = 0 },
            .size = .{ .width = Layout.panel_width, .height = Layout.panel_height },
        },
        .style = .{ .nonactivating = true },
    });

    panel.setOpaque(false);
    panel.setBackgroundColor(objc.Color.clear());
    panel.setMovableByWindowBackground(true);
    panel.setHidesOnDeactivate(true);
    panel.setLevel(.floating);
    panel.setDelegate(delegate);

    const content = panel.contentView();
    content.setWantsLayer(true);
    content.layer().setBackgroundColor(objc.Color.clear().cgColor());

    const glass = objc.GlassSurface.create(.{
        .frame = .{
            .origin = .{ .x = 0, .y = 0 },
            .size = .{ .width = Layout.panel_width, .height = Layout.panel_height },
        },
        .tint_color = colors.panel,
        .corner_radius = Layout.panel_corner_radius,
        .style = .regular,
    });
    content.addSubview(glass);
    const surface = glass.contentView();

    const input = makeTextField(.{
        .origin = .{ .x = Layout.input_x, .y = Layout.input_y },
        .size = .{ .width = Layout.input_width, .height = Layout.input_height },
    }, objc.Font.system(Layout.query_font_size), colors.text, colors.input, true);
    input.setBorder(0, colors.accent);
    input.setCornerRadius(Layout.input_corner_radius);
    input.setDelegate(delegate);
    surface.addSubview(input);

    const divider = objc.View.create(.{
        .frame = .{
            .origin = .{ .x = Layout.list_x, .y = Layout.divider_top_y },
            .size = .{ .width = Layout.list_width, .height = Layout.divider_height },
        },
        .background_color = colors.divider,
    });
    surface.addSubview(divider);

    var rows: Rows = [_]Row{.{}} ** Layout.visible_rows;
    var y: objc.CGFloat = Layout.row_start_y;
    for (&rows) |*row| {
        row.* = Row.create(surface, y, colors);
        row.setHidden(true);
        y -= Layout.row_height;
    }

    setMode(panel, glass, input, rows, divider, .compact);

    return .{ .panel = panel, .glass = glass, .input = input, .rows = rows, .divider = divider };
}

pub fn applyTheme(app: objc.Application, panel: objc.Panel, glass: objc.GlassSurface, input: objc.TextField, rows: Rows, divider: objc.View) void {
    const colors = theme.Theme.current(app);
    panel.setBackgroundColor(objc.Color.clear());
    panel.contentView().layer().setBackgroundColor(objc.Color.clear().cgColor());
    glass.setTintColor(colors.panel);
    glass.setCornerRadius(Layout.panel_corner_radius);
    input.setTextColor(colors.text);
    input.setFillColor(colors.input);
    input.setBorder(0, colors.accent);
    input.setCornerRadius(Layout.input_corner_radius);
    for (rows) |row| {
        row.setAccent(colors.accent);
        row.number_box.setBorder(1, colors.shortcut_border);
    }
    divider.setFillColor(colors.divider);
}

pub fn setMode(panel: objc.Panel, glass: objc.GlassSurface, input: objc.TextField, rows: Rows, divider: objc.View, mode: Mode) void {
    const height = Layout.panelHeight(mode);
    var frame = panel.frame();
    const top = frame.origin.y + frame.size.height;
    frame.size.height = height;
    frame.origin.y = top - height;
    panel.setFrame(frame, true);
    glass.setFrame(.{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = Layout.panel_width, .height = height },
    });

    input.setFrame(.{
        .origin = .{ .x = Layout.input_x, .y = Layout.inputY(mode) },
        .size = .{ .width = Layout.input_width, .height = Layout.input_height },
    });

    var y: objc.CGFloat = Layout.row_start_y;
    for (rows) |row| {
        row.setY(y);
        if (mode == .compact) row.setHidden(true);
        y -= Layout.row_height;
    }

    divider.setFrame(.{
        .origin = .{ .x = Layout.list_x, .y = Layout.inputY(mode) - Layout.divider_gap },
        .size = .{ .width = Layout.list_width, .height = Layout.divider_height },
    });
    divider.setHidden(mode == .compact);
}

pub fn positionPanel(panel: objc.Panel, mode: Mode) void {
    const frame = objc.Screen.main().visibleFrame();
    const height = Layout.panelHeight(mode);
    panel.setFrameOrigin(.{
        .x = frame.origin.x + (frame.size.width - Layout.panel_width) / 2,
        .y = frame.origin.y + frame.size.height * 0.62 - height / 2,
    });
}

fn rowFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{ .x = Layout.list_x, .y = y },
        .size = .{ .width = Layout.list_width, .height = Layout.row_height },
    };
}

fn numberBoxFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.list_x + Layout.row_number_x_offset,
            .y = y + Layout.row_number_y_offset,
        },
        .size = .{ .width = Layout.row_number_width, .height = Layout.row_number_height },
    };
}

fn numberLayerFrame(box: objc.Rect) objc.Rect {
    return .{
        .origin = .{ .x = 0, .y = (box.size.height - Layout.row_number_font_size) / 2 - 1 },
        .size = .{ .width = box.size.width, .height = Layout.row_number_font_size + 2 },
    };
}

fn iconFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.list_x + Layout.icon_x_offset,
            .y = y + Layout.icon_y_offset,
        },
        .size = .{ .width = Layout.icon_size, .height = Layout.icon_size },
    };
}

fn makeTextField(rect: objc.Rect, font: objc.Font, text_color: objc.Color, background_color: objc.Color, editable: objc.BOOL) objc.TextField {
    return objc.TextField.create(.{
        .class_name = if (editable) "ZLInputTextField" else "NSTextField",
        .frame = rect,
        .font = font,
        .text_color = text_color,
        .background_color = background_color,
        .editable = editable,
    });
}
