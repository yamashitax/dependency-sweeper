const std = @import("std");

var target_directories: std.ArrayListAligned(std.json.Value, null) = undefined;
var delete_directories: std.ArrayListAligned(std.json.Value, null) = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    allocator = arena.allocator();

    try setup();

    const home_dir = std.os.getenv("HOME") orelse {
        return error.HomeDirNotAvailable;
    };

    for (target_directories.items) |target| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, target.String });
        defer allocator.free(path);

        const dir = std.fs.cwd().openIterableDir(path, .{}) catch continue;
        var walker = try dir.walk(allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            if (entry.kind != .Directory) continue;
            if (std.mem.startsWith(u8, entry.path, ".")) continue;

            for (delete_directories.items) |delete| {
                if (std.mem.endsWith(u8, entry.path, delete.String)) {
                    const parent_dir = std.fs.path.dirname(entry.path) orelse continue;
                    if (std.mem.containsAtLeast(u8, parent_dir, 1, delete.String)) continue;

                    const joined_path = std.fs.path.join(allocator, &[_][]const u8{ path, parent_dir }) catch null;
                    if (joined_path) |p| {
                        defer allocator.free(p);

                        const d = std.fs.cwd().openDir(p, .{}) catch continue;

                        if (d.stat() catch null) |stat| {
                            if (std.time.nanoTimestamp() - stat.mtime >= std.time.ns_per_week * 4) {
                                const delete_path = std.fs.path.join(allocator, &[_][]const u8{ p, delete.String }) catch unreachable;
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

fn setup() !void {
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();

    const value_tree = brk: {
        const file = std.fs.cwd().openFile("config.json", .{}) catch {
            const json =
                \\    {
                \\        "target_directories": [
                \\            "Projects",
                \\            "Sites",
                \\            "Code"
                \\        ],
                \\        "delete_directories": [
                \\            "node_modules",
                \\            "vendor"
                \\        ]
                \\    }
            ;

            break :brk try parser.parse(json);
        };

        var buff: []u8 = undefined;

        _ = try file.readAll(buff);

        break :brk try parser.parse(buff);
    };

    const root: std.json.Value = value_tree.root;

    target_directories = root.Object.get("target_directories").?.Array;
    delete_directories = root.Object.get("delete_directories").?.Array;
}
