const std = @import("std");

const logger = @import("logger.zig");
const metadata = @import("metadata.zig");
const install = @import("install.zig");

const MetaStruct = metadata.MetaStruct;

pub fn do_maint(args: [][]u8, install_dir: []const u8) !void {
    if (args.len < 1) {
        try logger.warn("No sub-command provided!", .{});
    } else {
        if (std.mem.eql(u8, args[0], "uninstall")) {
            try do_uninstall(install_dir);
        }
    }
    try logger.info("Quitting.", .{});
}

fn confirm() !bool {
    var stdin = std.io.getStdIn().reader();

    try logger.query("Please confirm this action [y/n]: ", .{});

    var buf: [8]u8 = undefined;
    if (try stdin.readUntilDelimiterOrEof(buf[0..], '\n')) |user_input| {
        if (std.mem.eql(u8, user_input[0..1], "y") or std.mem.eql(u8, user_input[0..1], "Y")) {
            return true;
        }
        return false;
    } else {
        return false;
    }
}

fn do_uninstall(install_dir: []const u8) !void {
    try logger.warn("This will uninstall the application runtime for this Burrito binary!", .{});
    if ((try confirm()) == false) {
        try logger.warn("Uninstall was aborted!", .{});
        return;
    }

    try logger.info("Deleting directory: {s}", .{install_dir});
    try std.fs.deleteTreeAbsolute(install_dir);
    try logger.info("Uninstall complete!", .{});
}

pub fn do_clean_old_versions(install_prefix_path: []const u8, current_install_path: []const u8) !void {
    std.log.debug("Going to clean up older versions of this application...", .{});

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = &arena.allocator;

    const prefix_dir = try std.fs.openDirAbsolute(install_prefix_path, .{ .iterate = true, .access_sub_paths = true });

    const current_install = try install.load_install_from_path(allocator, current_install_path);

    var itr = prefix_dir.iterate();
    while (try itr.next()) |dir| {
        if (dir.kind == .Directory) {
            const possible_app_path = try std.fs.path.join(allocator, &[_][]const u8{ install_prefix_path, dir.name });
            const other_install = try install.load_install_from_path(allocator, possible_app_path);

            // If can can't figure out if this is an install dir, just ignore it
            if (other_install == null) {
                continue;
            }

            // If this isn't the same installed app as us ignore it
            if (!std.mem.eql(u8, current_install.?.metadata.app_name, other_install.?.metadata.app_name)) {
                continue;
            }

            // Compare the version, if it's older, delete the directory
            if (std.SemanticVersion.order(current_install.?.version, other_install.?.version) == .gt) {
                try prefix_dir.deleteTree(other_install.?.install_dir_path);
                try logger.info("Uninstalled older version (v{s})", .{other_install.?.metadata.app_version});
            }
        }
    }

    arena.deinit();
}