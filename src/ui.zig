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
    panel: objc.Panel = .{},
    glass: objc.GlassSurface = .{},
    search_icon: objc.ImageView = .{},
    input: objc.TextField = .{},
    results: ResultList = .{},

    pub fn applyTheme(self: Elements, app: objc.Application) void {
        applyThemeViews(app, self.panel, self.glass, self.search_icon, self.input, self.results);
    }

    pub fn setMode(self: Elements, mode: Mode) void {
        setModeViews(self.panel, self.glass, self.search_icon, self.input, self.results, mode);
    }

    pub fn positionPanel(self: Elements, mode: Mode) void {
        positionPanelView(self.panel, mode);
    }
};

pub const ResultList = struct {
    rows: Rows = [_]Row{.{}} ** Layout.visible_rows,
    divider: objc.View = .{},
    mouse_target: objc.View = .{},

    pub fn create(surface: objc.View, colors: theme.Theme) ResultList {
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
        for (&rows, 0..) |*row, slot| {
            row.* = Row.create(surface, y, slot, colors);
            row.setHidden(true);
            y -= Layout.ResultRow.height;
        }

        const mouse_target = objc.View.create(.{
            .class_name = "ZLResultsMouseView",
            .frame = resultsMouseFrame(),
            .background_color = objc.Color.clear(),
        });
        mouse_target.addMouseMovedTrackingArea();
        surface.addSubview(mouse_target);

        return .{
            .rows = rows,
            .divider = divider,
            .mouse_target = mouse_target,
        };
    }

    pub fn applyTheme(self: ResultList, colors: theme.Theme) void {
        for (self.rows) |row| row.applyTheme(colors);
        self.divider.setFillColor(colors.divider);
    }

    pub fn setMode(self: ResultList, mode: Mode) void {
        var y: objc.CGFloat = Layout.rowStartY();
        for (self.rows) |row| {
            row.setY(y);
            if (mode == .compact) row.setHidden(true);
            y -= Layout.ResultRow.height;
        }

        self.divider.setFrame(.{
            .origin = .{ .x = Layout.List.x, .y = Layout.dividerY(mode) },
            .size = .{ .width = Layout.List.width, .height = Layout.List.divider_height },
        });
        self.divider.setHidden(mode == .compact);

        self.mouse_target.setFrame(resultsMouseFrame());
        self.mouse_target.setHidden(mode == .compact);
    }
};

pub const Row = struct {
    background: objc.View = .{},
    number_box: objc.View = .{},
    number: objc.TextLayer = .{},
    icon: objc.ImageView = .{},
    app_name: objc.TextField = .{},

    pub fn create(content: objc.View, y: objc.CGFloat, slot: usize, colors: theme.Theme) Row {
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
        number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut.border);
        number_box.setCornerRadius(Layout.ResultRow.shortcut_corner_radius);
        content.addSubview(number_box);

        const number = objc.TextLayer.create(.{
            .frame = numberTextFrame(number_box_frame),
            .text = rowNumberString(slot),
            .font_size = Layout.ResultRow.shortcut_font_size,
            .text_color = colors.shortcut.text,
        });
        number_box.layer().addSublayer(number);

        const icon = objc.ImageView.create(.{
            .frame = iconFrame(y),
        });
        content.addSubview(icon);

        const app_name = makeTextField(.{
            .origin = .{ .x = Layout.List.x + Layout.ResultRow.app_name_column_x, .y = y },
            .size = .{ .width = Layout.List.width - Layout.ResultRow.app_name_column_x, .height = Layout.ResultRow.height },
        }, objc.Font.system(Layout.ResultRow.app_font_size), colors.row.text, objc.Color.clear(), false);
        content.addSubview(app_name);

        return .{
            .background = background,
            .number_box = number_box,
            .number = number,
            .icon = icon,
            .app_name = app_name,
        };
    }

    pub fn showApp(self: Row, arena: std.mem.Allocator, name: []const u8, icon: objc.Image) void {
        self.setHidden(false);
        self.icon.setImage(icon);
        self.app_name.setStringValue(objc.String.fromUtf8(arena, name));
    }

    pub fn clear(self: Row, arena: std.mem.Allocator) void {
        self.icon.setImage(.nil());
        self.app_name.setStringValue(objc.String.fromUtf8(arena, ""));
        self.setHidden(true);
    }

    pub fn setSelected(self: Row, selected: bool, colors: theme.Theme) void {
        if (selected) {
            self.app_name.setTextColor(colors.row.selected_text);
            self.background.setFillColor(colors.row.selected);
            self.number_box.setFillColor(colors.shortcut.fill);
            self.number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut.fill);
            return;
        }

        self.background.setFillColor(objc.Color.clear());
        self.number_box.setFillColor(objc.Color.clear());
        self.number_box.setBorder(Layout.ResultRow.border_width, colors.shortcut.border);
        self.app_name.setTextColor(colors.row.muted);
    }

    pub fn applyTheme(self: Row, colors: theme.Theme) void {
        self.number.setTextColor(colors.shortcut.text);
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
        self.number.setFrame(numberTextFrame(shortcut_frame));
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
    panel.setAcceptsMouseMovedEvents(true);
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
        .tint_color = colors.glass.tint,
        .corner_radius = Layout.Panel.corner_radius,
        .style = colors.glass.style,
    });
    content.addSubview(glass);
    const surface = glass.contentView();

    const input = makeTextField(searchTextFrame(.expanded), objc.Font.system(Layout.Search.font_size), colors.search.text, colors.search.fill, true);
    input.setBorder(Layout.Search.border_width, colors.search.accent);
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
    search_icon.setContentTintColor(colors.search.icon);
    surface.addSubview(search_icon);

    const results = ResultList.create(surface, colors);

    setModeViews(panel, glass, search_icon, input, results, .compact);

    return .{
        .panel = panel,
        .glass = glass,
        .search_icon = search_icon,
        .input = input,
        .results = results,
    };
}

fn applyThemeViews(app: objc.Application, panel: objc.Panel, glass: objc.GlassSurface, search_icon: objc.ImageView, input: objc.TextField, results: ResultList) void {
    const colors = theme.Theme.current(app);
    panel.setBackgroundColor(objc.Color.clear());
    panel.contentView().layer().setBackgroundColor(objc.Color.clear().cgColor());
    glass.setStyle(colors.glass.style);
    glass.setTintColor(colors.glass.tint);
    glass.setCornerRadius(Layout.Panel.corner_radius);
    input.setTextColor(colors.search.text);
    input.setFillColor(colors.search.fill);
    input.setBorder(Layout.Search.border_width, colors.search.accent);
    input.setCornerRadius(Layout.Search.corner_radius);
    search_icon.setContentTintColor(colors.search.icon);
    results.applyTheme(colors);
}

fn setModeViews(panel: objc.Panel, glass: objc.GlassSurface, search_icon: objc.ImageView, input: objc.TextField, results: ResultList, mode: Mode) void {
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
    results.setMode(mode);
}

pub fn visibleRowAtY(y: objc.CGFloat) ?usize {
    if (y < 0) return null;

    const total_height = Layout.ResultRow.height * @as(objc.CGFloat, @floatFromInt(Layout.visible_rows));
    if (y >= total_height) return null;

    const row_from_bottom: usize = @intFromFloat(y / Layout.ResultRow.height);
    return Layout.visible_rows - 1 - row_from_bottom;
}

fn positionPanelView(panel: objc.Panel, mode: Mode) void {
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

fn resultsMouseFrame() objc.Rect {
    const height = Layout.ResultRow.height * @as(objc.CGFloat, @floatFromInt(Layout.visible_rows));
    return .{
        .origin = .{
            .x = Layout.List.x,
            .y = Layout.rowStartY() - Layout.ResultRow.height * @as(objc.CGFloat, @floatFromInt(Layout.visible_rows - 1)),
        },
        .size = .{ .width = Layout.List.width, .height = height },
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

fn numberTextFrame(box: objc.Rect) objc.Rect {
    return .{
        .origin = .{ .x = 0, .y = (box.size.height - Layout.ResultRow.shortcut_font_size) / 2 + Layout.ResultRow.shortcut_text_baseline_adjustment },
        .size = .{ .width = box.size.width, .height = Layout.ResultRow.shortcut_font_size + Layout.ResultRow.shortcut_text_height_padding },
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

fn rowNumberString(slot: usize) objc.String {
    return switch (slot) {
        0 => objc.String.fromStatic("1"),
        1 => objc.String.fromStatic("2"),
        2 => objc.String.fromStatic("3"),
        3 => objc.String.fromStatic("4"),
        4 => objc.String.fromStatic("5"),
        else => objc.String.fromStatic(""),
    };
}

test "visible row hit testing maps from top to bottom" {
    try std.testing.expectEqual(@as(?usize, 4), visibleRowAtY(0));
    try std.testing.expectEqual(@as(?usize, 4), visibleRowAtY(Layout.ResultRow.height - 1));
    try std.testing.expectEqual(@as(?usize, 3), visibleRowAtY(Layout.ResultRow.height));
    try std.testing.expectEqual(@as(?usize, 0), visibleRowAtY(Layout.ResultRow.height * 4));
}

test "visible row hit testing rejects outside list" {
    const height = Layout.ResultRow.height * @as(objc.CGFloat, @floatFromInt(Layout.visible_rows));
    try std.testing.expectEqual(@as(?usize, null), visibleRowAtY(-1));
    try std.testing.expectEqual(@as(?usize, null), visibleRowAtY(height));
}
