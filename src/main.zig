const std = @import("std");

const target_directories = [_][]const u8{ "Projects", "Sites", "Code" };
const delete_directories = [_][]const u8{ "node_modules", "vendor" };

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const home_dir = std.os.getenv("HOME") orelse {
        return error.HomeDirNotAvailable;
    };

    for (target_directories) |target| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, target });
        defer allocator.free(path);

        const dir = std.fs.cwd().openIterableDir(path, .{}) catch continue;
        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .Directory) continue;
            if (std.mem.startsWith(u8, entry.path, ".")) continue;

            for (delete_directories) |delete| {
                if (std.mem.endsWith(u8, entry.path, delete)) {
                    const parent_dir = std.fs.path.dirname(entry.path) orelse continue;
                    if (std.mem.containsAtLeast(u8, parent_dir, 1, delete)) continue;

                    const joined_path = std.fs.path.join(allocator, &[_][]const u8{ path, parent_dir }) catch null;
                    if (joined_path) |p| {
                        defer allocator.free(p);

                        const d = std.fs.cwd().openDir(p, .{}) catch continue;

                        if (d.stat() catch null) |stat| {
                            if (std.time.nanoTimestamp() - stat.mtime >= std.time.ns_per_week * 4) {
                                const delete_path = std.fs.path.join(allocator, &[_][]const u8{ p, delete }) catch unreachable;
                                defer allocator.free(delete_path);
                                std.debug.print("More than 1 month has elapsed since modification: {s}\n DELETING\n", .{delete_path});
                                std.fs.cwd().deleteTree(delete_path) catch {
                                    std.debug.print("Failed to delete", .{});
                                    continue;
                                };
                                std.debug.print("DELETED", .{});
                            }
                        }
                    }
                }
            }
        }
    }
}
