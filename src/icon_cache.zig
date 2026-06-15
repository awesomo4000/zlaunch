const std = @import("std");
const objc = @import("objc.zig");

pub const IconCache = struct {
    arena: std.mem.Allocator,
    icons: std.StringHashMapUnmanaged(objc.Image) = .empty,

    pub fn init(arena: std.mem.Allocator) IconCache {
        return .{ .arena = arena };
    }

    pub fn iconForPath(self: *IconCache, path: []const u8) objc.Image {
        if (self.icons.get(path)) |image| return image;

        const path_string = objc.String.fromUtf8(self.arena, path);
        const image = objc.Workspace.shared().iconForFile(path_string);
        const retained_image = image.retain();
        self.icons.put(self.arena, path, retained_image) catch {
            retained_image.release();
            return image;
        };
        return retained_image;
    }

    pub fn clear(self: *IconCache) void {
        var iterator = self.icons.iterator();
        while (iterator.next()) |entry| entry.value_ptr.release();
        self.icons.clearRetainingCapacity();
    }
};
