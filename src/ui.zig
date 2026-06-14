const std = @import("std");
const objc = @import("objc.zig");
const theme = @import("theme.zig");

pub const Layout = struct {
    pub const panel_width: objc.CGFloat = 640;
    pub const panel_height: objc.CGFloat = 386;
    pub const margin: objc.CGFloat = 20;
    pub const top_padding: objc.CGFloat = 36;
    pub const bottom_padding: objc.CGFloat = top_padding;
    pub const side_padding: objc.CGFloat = 64;
    pub const input_x: objc.CGFloat = side_padding;
    pub const input_width: objc.CGFloat = panel_width - side_padding * 2;
    pub const list_x: objc.CGFloat = side_padding;
    pub const list_width: objc.CGFloat = panel_width - side_padding * 2;
    pub const input_height: objc.CGFloat = 50;
    pub const entry_font_size: objc.CGFloat = 18;
    pub const row_number_font_size: objc.CGFloat = 15;
    pub const row_height: objc.CGFloat = 46;
    pub const selected_bar_width: objc.CGFloat = 2;
    pub const row_number_x_offset: objc.CGFloat = 24;
    pub const row_number_width: objc.CGFloat = 34;
    pub const row_label_x_offset: objc.CGFloat = 76;
    pub const panel_corner_radius: objc.CGFloat = 12;
    pub const input_corner_radius: objc.CGFloat = 5;
    pub const visible_rows = 5;
    pub const input_y: objc.CGFloat = panel_height - top_padding - input_height;
    pub const row_start_y: objc.CGFloat = input_y - margin - row_height;
    pub const divider_height: objc.CGFloat = 1;
    pub const list_bottom_y: objc.CGFloat = row_start_y - row_height * (visible_rows - 1);
    pub const divider_y: objc.CGFloat = bottom_padding;
};

pub const Rows = [Layout.visible_rows]Row;

pub const Elements = struct {
    panel: objc.Panel,
    input: objc.TextField,
    rows: Rows,
    divider: objc.View,
};

pub const Row = struct {
    background: objc.View = .{},
    number: objc.TextField = .{},
    app_name: objc.TextField = .{},
    selected_bar: objc.View = .{},

    pub fn create(content: objc.View, y: objc.CGFloat, colors: theme.Theme) Row {
        const background = objc.View.create(.{
            .frame = .{
                .origin = .{ .x = Layout.list_x, .y = y },
                .size = .{ .width = Layout.list_width, .height = Layout.row_height },
            },
            .background_color = objc.Color.clear(),
        });
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

        const number = makeTextField(.{
            .origin = .{ .x = Layout.list_x, .y = y },
            .size = .{ .width = Layout.row_number_x_offset + Layout.row_number_width, .height = Layout.row_height },
        }, Layout.row_number_font_size, colors.muted, objc.Color.clear(), false);
        content.addSubview(number);

        const app_name = makeTextField(.{
            .origin = .{ .x = Layout.list_x + Layout.row_label_x_offset, .y = y },
            .size = .{ .width = Layout.list_width - Layout.row_label_x_offset, .height = Layout.row_height },
        }, Layout.entry_font_size, colors.text, objc.Color.clear(), false);
        content.addSubview(app_name);

        return .{ .background = background, .number = number, .app_name = app_name, .selected_bar = selected_bar };
    }

    pub fn isEmpty(self: Row) bool {
        return self.app_name.isNil();
    }

    pub fn setAccent(self: Row, color: objc.Color) void {
        self.selected_bar.setFillColor(color);
    }

    pub fn showApp(self: Row, arena: std.mem.Allocator, slot: usize, name: []const u8) void {
        var number_buf: [1]u8 = .{@intCast('1' + slot)};
        self.number.setStringValue(objc.String.fromUtf8(arena, &number_buf));
        self.app_name.setStringValue(objc.String.fromUtf8(arena, name));
    }

    pub fn clear(self: Row, arena: std.mem.Allocator) void {
        self.number.setStringValue(objc.String.fromUtf8(arena, ""));
        self.app_name.setStringValue(objc.String.fromUtf8(arena, ""));
    }

    pub fn setSelected(self: Row, selected: bool, colors: theme.Theme) void {
        if (selected) {
            self.background.setFillColor(colors.selected);
            self.number.setTextColor(colors.selected_text);
            self.app_name.setTextColor(colors.selected_text);
            self.selected_bar.setHidden(false);
            return;
        }

        self.background.setFillColor(objc.Color.clear());
        self.number.setTextColor(colors.muted);
        self.app_name.setTextColor(colors.muted);
        self.selected_bar.setHidden(true);
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
    content.layer().setBackgroundColor(colors.panel.cgColor());
    content.layer().setCornerRadius(Layout.panel_corner_radius);
    content.layer().setMasksToBounds(true);

    const input = makeTextField(.{
        .origin = .{ .x = Layout.input_x, .y = Layout.input_y },
        .size = .{ .width = Layout.input_width, .height = Layout.input_height },
    }, Layout.entry_font_size, colors.text, colors.input, true);
    input.setBorder(1.5, colors.accent);
    input.setCornerRadius(Layout.input_corner_radius);
    input.setDelegate(delegate);
    content.addSubview(input);

    var rows: Rows = [_]Row{.{}} ** Layout.visible_rows;
    var y: objc.CGFloat = Layout.row_start_y;
    for (&rows) |*row| {
        row.* = Row.create(content, y, colors);
        y -= Layout.row_height;
    }

    const divider = objc.View.create(.{
        .frame = .{
            .origin = .{ .x = Layout.list_x, .y = Layout.divider_y },
            .size = .{ .width = Layout.list_width, .height = Layout.divider_height },
        },
        .background_color = colors.divider,
    });
    content.addSubview(divider);

    return .{ .panel = panel, .input = input, .rows = rows, .divider = divider };
}

pub fn applyTheme(app: objc.Application, panel: objc.Panel, input: objc.TextField, rows: Rows, divider: objc.View) void {
    const colors = theme.Theme.current(app);
    panel.setBackgroundColor(objc.Color.clear());
    const content_layer = panel.contentView().layer();
    content_layer.setBackgroundColor(colors.panel.cgColor());
    content_layer.setCornerRadius(Layout.panel_corner_radius);
    content_layer.setMasksToBounds(true);
    input.setTextColor(colors.text);
    input.setFillColor(colors.input);
    input.setBorder(1.5, colors.accent);
    input.setCornerRadius(Layout.input_corner_radius);
    for (rows) |row| row.setAccent(colors.accent);
    divider.setFillColor(colors.divider);
}

pub fn positionPanel(panel: objc.Panel) void {
    const frame = objc.Screen.main().visibleFrame();
    panel.setFrameOrigin(.{
        .x = frame.origin.x + (frame.size.width - Layout.panel_width) / 2,
        .y = frame.origin.y + frame.size.height * 0.62 - Layout.panel_height / 2,
    });
}

fn makeTextField(rect: objc.Rect, font_size: objc.CGFloat, text_color: objc.Color, background_color: objc.Color, editable: objc.BOOL) objc.TextField {
    return objc.TextField.create(.{
        .class_name = if (editable) "ZLInputTextField" else "NSTextField",
        .frame = rect,
        .font = objc.Font.monospacedSystem(font_size, 0),
        .text_color = text_color,
        .background_color = background_color,
        .editable = editable,
    });
}
