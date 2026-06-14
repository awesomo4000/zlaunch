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
    pub const row_height: objc.CGFloat = 46;
    pub const selected_bar_width: objc.CGFloat = 2;
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
    label: objc.TextField = .{},
    selected_bar: objc.View = .{},

    pub fn create(content: objc.View, y: objc.CGFloat, colors: theme.Theme) Row {
        const label = makeTextField(.{
            .origin = .{ .x = Layout.list_x, .y = y },
            .size = .{ .width = Layout.list_width, .height = Layout.row_height },
        }, colors.text, objc.Color.clear(), false);
        content.addSubview(label);

        const selected_bar = objc.View.create(.{
            .frame = .{
                .origin = .{ .x = Layout.list_x, .y = y },
                .size = .{ .width = Layout.selected_bar_width, .height = Layout.row_height },
            },
            .background_color = colors.accent,
        });
        selected_bar.setHidden(true);
        content.addSubview(selected_bar);

        return .{ .label = label, .selected_bar = selected_bar };
    }

    pub fn isEmpty(self: Row) bool {
        return self.label.isNil();
    }

    pub fn setAccent(self: Row, color: objc.Color) void {
        self.selected_bar.setFillColor(color);
    }

    pub fn showApp(self: Row, arena: std.mem.Allocator, name: []const u8) void {
        self.label.setStringValue(objc.String.fromUtf8(arena, name));
    }

    pub fn clear(self: Row, arena: std.mem.Allocator) void {
        self.label.setStringValue(objc.String.fromUtf8(arena, ""));
    }

    pub fn setSelected(self: Row, selected: bool, colors: theme.Theme) void {
        if (selected) {
            self.label.setFillColor(colors.selected);
            self.label.setTextColor(colors.selected_text);
            self.selected_bar.setHidden(false);
            return;
        }

        self.label.setFillColor(objc.Color.clear());
        self.label.setTextColor(colors.muted);
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
    }, colors.text, colors.input, true);
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

fn makeTextField(rect: objc.Rect, text_color: objc.Color, background_color: objc.Color, editable: objc.BOOL) objc.TextField {
    return objc.TextField.create(.{
        .frame = rect,
        .font = objc.Font.monospacedSystem(Layout.entry_font_size, 0),
        .text_color = text_color,
        .background_color = background_color,
        .editable = editable,
    });
}
