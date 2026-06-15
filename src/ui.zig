const std = @import("std");
const objc = @import("objc.zig");
const theme = @import("theme.zig");

pub const Layout = struct {
    pub const Panel = struct {
        pub const width: objc.CGFloat = 560;
        pub const top_padding: objc.CGFloat = 14;
        pub const bottom_padding: objc.CGFloat = top_padding;
        pub const corner_radius: objc.CGFloat = 36;
        pub const screen_y_ratio: objc.CGFloat = 0.62;
        pub const compact_height: objc.CGFloat = top_padding + Search.height + bottom_padding;
        pub const expanded_height: objc.CGFloat = top_padding + Search.height + List.divider_gap + List.search_to_rows_gap + ResultRow.height * List.visible_rows + bottom_padding;
    };

    pub const Search = struct {
        pub const height: objc.CGFloat = 48;
        pub const font_size: objc.CGFloat = 22;
        pub const icon_size: objc.CGFloat = 18;
        pub const icon_left: objc.CGFloat = 30;
        pub const text_left: objc.CGFloat = 68;
        pub const text_right_padding: objc.CGFloat = 48;
        pub const corner_radius: objc.CGFloat = height / 2;
        pub const border_width: objc.CGFloat = 0;
    };

    pub const List = struct {
        pub const side_padding: objc.CGFloat = 16;
        pub const x: objc.CGFloat = side_padding;
        pub const width: objc.CGFloat = Panel.width - side_padding * 2;
        pub const visible_rows = 5;
        pub const search_to_rows_gap: objc.CGFloat = 12;
        pub const divider_gap: objc.CGFloat = 6;
        pub const divider_height: objc.CGFloat = 1;
    };

    pub const ResultRow = struct {
        pub const height: objc.CGFloat = 44;
        pub const corner_radius: objc.CGFloat = height / 2;
        pub const app_font_size: objc.CGFloat = 17;
        pub const shortcut_font_size: objc.CGFloat = 12;
        pub const shortcut_column_x: objc.CGFloat = 18;
        pub const shortcut_width: objc.CGFloat = 24;
        pub const shortcut_height: objc.CGFloat = 22;
        pub const shortcut_corner_radius: objc.CGFloat = 6;
        pub const shortcut_y_offset: objc.CGFloat = (height - shortcut_height) / 2;
        pub const icon_column_x: objc.CGFloat = 62;
        pub const icon_size: objc.CGFloat = 34;
        pub const icon_y_offset: objc.CGFloat = (height - icon_size) / 2;
        pub const app_name_column_x: objc.CGFloat = 112;
        pub const border_width: objc.CGFloat = 1;
        pub const shortcut_text_baseline_adjustment: objc.CGFloat = -1;
        pub const shortcut_text_height_padding: objc.CGFloat = 2;
    };

    pub const panel_height: objc.CGFloat = Panel.expanded_height;
    pub const visible_rows = List.visible_rows;

    pub fn panelHeight(mode: Mode) objc.CGFloat {
        return switch (mode) {
            .compact => Panel.compact_height,
            .expanded => Panel.expanded_height,
        };
    }

    pub fn searchY(mode: Mode) objc.CGFloat {
        return panelHeight(mode) - Panel.top_padding - Search.height;
    }

    pub fn rowStartY() objc.CGFloat {
        return searchY(.expanded) - List.search_to_rows_gap - List.divider_gap - ResultRow.height;
    }

    pub fn dividerY(mode: Mode) objc.CGFloat {
        return searchY(mode) - List.divider_gap;
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
    search_icon: objc.ImageView,
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

    pub fn create(content: objc.View, y: objc.CGFloat, colors: theme.Theme) Row {
        const background = objc.View.create(.{
            .frame = rowFrame(y),
            .background_color = objc.Color.clear(),
        });
        background.setCornerRadius(Layout.ResultRow.corner_radius);
        content.addSubview(background);

        const number_box_frame = numberBoxFrame(y);
        const number_box = objc.View.create(.{
            .frame = number_box_frame,
            .background_color = objc.Color.clear(),
        });
        number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut_border);
        number_box.setCornerRadius(Layout.ResultRow.shortcut_corner_radius);
        content.addSubview(number_box);

        const number = objc.TextLayer.create(.{
            .frame = numberLayerFrame(number_box_frame),
            .text = objc.String.fromStatic(""),
            .font_size = Layout.ResultRow.shortcut_font_size,
            .text_color = colors.shortcut_fill,
        });
        number_box.layer().addSublayer(number);

        const icon = objc.ImageView.create(.{
            .frame = iconFrame(y),
        });
        content.addSubview(icon);

        const app_name = makeTextField(.{
            .origin = .{ .x = Layout.List.x + Layout.ResultRow.app_name_column_x, .y = y },
            .size = .{ .width = Layout.List.width - Layout.ResultRow.app_name_column_x, .height = Layout.ResultRow.height },
        }, objc.Font.system(Layout.ResultRow.app_font_size), colors.text, objc.Color.clear(), false);
        content.addSubview(app_name);

        return .{
            .background = background,
            .number_box = number_box,
            .number = number,
            .icon = icon,
            .app_name = app_name,
        };
    }

    pub fn isEmpty(self: Row) bool {
        return self.app_name.isNil();
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
            self.number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut_fill);
            self.number.setTextColor(colors.shortcut_text);
            self.app_name.setTextColor(colors.selected_text);
            return;
        }

        self.background.setFillColor(objc.Color.clear());
        self.number_box.setFillColor(objc.Color.clear());
        self.number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut_border);
        self.number.setTextColor(colors.shortcut_fill);
        self.app_name.setTextColor(colors.muted);
    }

    pub fn setHidden(self: Row, hidden: bool) void {
        self.background.setHidden(hidden);
        self.number_box.setHidden(hidden);
        self.number.setHidden(hidden);
        self.icon.setHidden(hidden);
        self.app_name.setHidden(hidden);
    }

    pub fn setY(self: Row, y: objc.CGFloat) void {
        self.background.setFrame(rowFrame(y));
        const shortcut_frame = numberBoxFrame(y);
        self.number_box.setFrame(shortcut_frame);
        self.number.setFrame(numberLayerFrame(shortcut_frame));
        self.icon.setFrame(iconFrame(y));
        self.app_name.setFrame(.{
            .origin = .{ .x = Layout.List.x + Layout.ResultRow.app_name_column_x, .y = y },
            .size = .{ .width = Layout.List.width - Layout.ResultRow.app_name_column_x, .height = Layout.ResultRow.height },
        });
    }
};

pub fn build(app: objc.Application, delegate: objc.Object) Elements {
    const colors = theme.Theme.current(app);
    const panel = objc.Panel.create(.{
        .class_name = "ZLPanel",
        .content_rect = .{
            .origin = .{ .x = 0, .y = 0 },
            .size = .{ .width = Layout.Panel.width, .height = Layout.panel_height },
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
            .size = .{ .width = Layout.Panel.width, .height = Layout.panel_height },
        },
        .tint_color = colors.panel,
        .corner_radius = Layout.Panel.corner_radius,
        .style = colors.glass_style,
    });
    content.addSubview(glass);
    const surface = glass.contentView();

    const input = makeTextField(searchTextFrame(.expanded), objc.Font.system(Layout.Search.font_size), colors.text, colors.input, true);
    input.setBorder(Layout.Search.border_width, colors.accent);
    input.setCornerRadius(Layout.Search.corner_radius);
    input.setDelegate(delegate);
    surface.addSubview(input);

    const search_icon = objc.ImageView.create(.{
        .frame = searchIconFrame(.expanded),
        .image = objc.Image.systemSymbol(
            objc.String.fromStatic("magnifyingglass"),
            objc.String.fromStatic("Search"),
        ),
    });
    search_icon.setContentTintColor(colors.muted);
    surface.addSubview(search_icon);

    const divider = objc.View.create(.{
        .frame = .{
            .origin = .{ .x = Layout.List.x, .y = Layout.dividerY(.expanded) },
            .size = .{ .width = Layout.List.width, .height = Layout.List.divider_height },
        },
        .background_color = colors.divider,
    });
    surface.addSubview(divider);

    var rows: Rows = [_]Row{.{}} ** Layout.visible_rows;
    var y: objc.CGFloat = Layout.rowStartY();
    for (&rows) |*row| {
        row.* = Row.create(surface, y, colors);
        row.setHidden(true);
        y -= Layout.ResultRow.height;
    }

    setMode(panel, glass, search_icon, input, rows, divider, .compact);

    return .{ .panel = panel, .glass = glass, .search_icon = search_icon, .input = input, .rows = rows, .divider = divider };
}

pub fn applyTheme(app: objc.Application, panel: objc.Panel, glass: objc.GlassSurface, search_icon: objc.ImageView, input: objc.TextField, rows: Rows, divider: objc.View) void {
    const colors = theme.Theme.current(app);
    panel.setBackgroundColor(objc.Color.clear());
    panel.contentView().layer().setBackgroundColor(objc.Color.clear().cgColor());
    glass.setStyle(colors.glass_style);
    glass.setTintColor(colors.panel);
    glass.setCornerRadius(Layout.Panel.corner_radius);
    input.setTextColor(colors.text);
    input.setFillColor(colors.input);
    input.setBorder(Layout.Search.border_width, colors.accent);
    input.setCornerRadius(Layout.Search.corner_radius);
    search_icon.setContentTintColor(colors.muted);
    for (rows) |row| {
        row.number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut_border);
    }
    divider.setFillColor(colors.divider);
}

pub fn setMode(panel: objc.Panel, glass: objc.GlassSurface, search_icon: objc.ImageView, input: objc.TextField, rows: Rows, divider: objc.View, mode: Mode) void {
    const height = Layout.panelHeight(mode);
    var frame = panel.frame();
    const top = frame.origin.y + frame.size.height;
    frame.size.height = height;
    frame.origin.y = top - height;
    panel.setFrame(frame, true);
    glass.setFrame(.{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = Layout.Panel.width, .height = height },
    });

    input.setFrame(searchTextFrame(mode));
    search_icon.setFrame(searchIconFrame(mode));

    var y: objc.CGFloat = Layout.rowStartY();
    for (rows) |row| {
        row.setY(y);
        if (mode == .compact) row.setHidden(true);
        y -= Layout.ResultRow.height;
    }

    divider.setFrame(.{
        .origin = .{ .x = Layout.List.x, .y = Layout.dividerY(mode) },
        .size = .{ .width = Layout.List.width, .height = Layout.List.divider_height },
    });
    divider.setHidden(mode == .compact);
}

pub fn positionPanel(panel: objc.Panel, mode: Mode) void {
    const frame = objc.Screen.main().visibleFrame();
    const height = Layout.panelHeight(mode);
    panel.setFrameOrigin(.{
        .x = frame.origin.x + (frame.size.width - Layout.Panel.width) / 2,
        .y = frame.origin.y + frame.size.height * Layout.Panel.screen_y_ratio - height / 2,
    });
}

fn rowFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{ .x = Layout.List.x, .y = y },
        .size = .{ .width = Layout.List.width, .height = Layout.ResultRow.height },
    };
}

fn numberBoxFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.List.x + Layout.ResultRow.shortcut_column_x,
            .y = y + Layout.ResultRow.shortcut_y_offset,
        },
        .size = .{ .width = Layout.ResultRow.shortcut_width, .height = Layout.ResultRow.shortcut_height },
    };
}

fn numberLayerFrame(box: objc.Rect) objc.Rect {
    return .{
        .origin = .{
            .x = 0,
            .y = (box.size.height - Layout.ResultRow.shortcut_font_size) / 2 + Layout.ResultRow.shortcut_text_baseline_adjustment,
        },
        .size = .{
            .width = box.size.width,
            .height = Layout.ResultRow.shortcut_font_size + Layout.ResultRow.shortcut_text_height_padding,
        },
    };
}

fn iconFrame(y: objc.CGFloat) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.List.x + Layout.ResultRow.icon_column_x,
            .y = y + Layout.ResultRow.icon_y_offset,
        },
        .size = .{ .width = Layout.ResultRow.icon_size, .height = Layout.ResultRow.icon_size },
    };
}

fn searchTextFrame(mode: Mode) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.List.x + Layout.Search.text_left,
            .y = Layout.searchY(mode),
        },
        .size = .{
            .width = Layout.List.width - Layout.Search.text_left - Layout.Search.text_right_padding,
            .height = Layout.Search.height,
        },
    };
}

fn searchIconFrame(mode: Mode) objc.Rect {
    return .{
        .origin = .{
            .x = Layout.List.x + Layout.Search.icon_left,
            .y = Layout.searchY(mode) + (Layout.Search.height - Layout.Search.icon_size) / 2,
        },
        .size = .{ .width = Layout.Search.icon_size, .height = Layout.Search.icon_size },
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
