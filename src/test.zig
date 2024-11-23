const std = @import("std");
const expect = std.testing.expect;
const testing = std.testing;
const fs = std.fs;
const process = std.process;
const ArrayList = std.ArrayList;
const minifyDot = @import("main.zig").minifyDot;

test "minify and validate .dot files" {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    var dir = fs.cwd().openDir("test_case", .{ .iterate = true }) catch {
        std.log.err("Failed to open directory: test_case\n", .{});
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    // var test_cases = ArrayList([]const u8).init(allocator);
    // defer test_cases.deinit();
    var test_case_count: usize = 0;
    var fail_case_count: usize = 0;

    while (try iter.next()) |entry| {
        test_case_count += 1;
        if (std.mem.endsWith(u8, entry.name, ".dot")) {
            // try test_cases.append(entry.name);
            const file_name = entry.name;
            var is_corrupt: bool = false;
            const eq = std.mem.eql;
            std.debug.print("Test case: {s}\t", .{file_name});
            // must be a better way here, but zig disallow swicth on "string"
            if (eq(u8, file_name, "1308_1.dot") or eq(u8, file_name, "1676.dot") or eq(u8, file_name, "1411.dot")) {
                is_corrupt = true;
                std.debug.print("This test case is a corrupt file. It fails as expected.\n", .{});
            }
            minify_and_validate_file(file_name) catch {
                // err is logged inside minify_and_validate_file()
                // std.log.err("Failed to minify and validate file: {s}\n", .{file_name});
                if (!is_corrupt) fail_case_count += 1;
                continue;
            };
        }
    }
    std.debug.print("\n\n\nTest Complete: Pass/Total: {d}/{d}; Failed: {d}\n\n\n", .{ test_case_count - fail_case_count, test_case_count, fail_case_count });
}

pub fn minify_and_validate_file(file_name: []const u8) !void {
    const allocator = std.heap.page_allocator;

    var dir = fs.cwd().openDir("test_case", .{ .iterate = true }) catch {
        std.log.err("Failed to open directory: test_case\n", .{});
        return;
    };
    defer dir.close();
    // std.debug.print("Try to open file: {s}\n", .{file_name});
    var file = dir.openFile(file_name, .{}) catch {
        std.log.err("Failed to open file: {s}\n", .{file_name});
        return;
    };
    defer file.close();

    const stats = try file.stat();
    const content = try allocator.alloc(u8, stats.size);
    defer allocator.free(content);

    _ = try file.readAll(content);

    // Minify the content
    const minified_content = try minifyDot(allocator, content);
    defer allocator.free(minified_content);

    // Write minified content to a temporary file
    const tmp_file_name = try allocator.alloc(u8, file_name.len + 5); // .min appended
    defer allocator.free(tmp_file_name);
    std.mem.copyForwards(u8, tmp_file_name, file_name);
    std.mem.copyForwards(u8, tmp_file_name[file_name.len..], ".min");

    var tmp_file = try fs.cwd().createFile(tmp_file_name, .{});
    defer fs.cwd().deleteFile(tmp_file_name) catch {}; // Clean up the temp file
    defer tmp_file.close();
    try tmp_file.writeAll(minified_content);

    // Validate the minified .dot file using 'dot' command
    const dot_args = [_][]const u8{ "nop", tmp_file_name }; //, "-Knop", "-Tdot"
    var dot_process = process.Child.init(&dot_args, allocator);
    dot_process.stdin_behavior = .Close;
    dot_process.stdout_behavior = .Close;
    dot_process.stderr_behavior = .Close;
    try dot_process.spawn();
    const result = try dot_process.wait();
    const exit_code = result.Exited;
    if (exit_code != 0) {
        std.log.err("Failed to parse minified {s}: \n{s}\n", .{ file_name, minified_content });
    }
    try expect(exit_code == 0); // Expect successful validation by 'dot'
    std.debug.print("Pass\n", .{});
}
