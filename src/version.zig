//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");

fn show() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush();
}

fn renew(new_version: std.SemanticVersion) !void {
    _ = new_version;
    unreachable;
}

test "version renewal" {
    // const allocator = std.testing.allocator;
    
    // const source = 
    //     \\.{
    //     \\  .name = "SomeProject",
    //     \\  .version = "0.0.1",
    //     \\  .dependencies = .{},
    //     \\}
    // ;
    // const expect = 
    //     \\.{
    //     \\  .name = "SomeProject",
    //     \\  .version = "1.2.3",
    //     \\  .dependencies = .{},
    //     \\}
    // ;
}

const VersionOptions = std.enums.EnumFieldStruct(std.meta.FieldEnum(std.SemanticVersion), ?[]const u8, @as(?[]const u8, null));

fn set(options: VersionOptions) !void {
    _ = options;
    unreachable;
}

const VersionPart = enum {major, minor, patch};

fn increment(part: VersionPart) !void {
    _ = part;
    unreachable;
}

fn readBuildZon(allocator: std.mem.Allocator, full_path: []const u8) ![]const u8 {
    var file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();

    const meta = try file.metadata();
    return try file.readToEndAllocOptions(allocator, meta.size(), meta.size(), @alignOf(u8), 0);
}

fn readVersionInternal(allocator: std.mem.Allocator, source: [:0]const u8) !std.zig.Token.Loc {
    var ast = try std.zig.Ast.parse(allocator, source, .zon);
    defer ast.deinit(allocator);

    const node_links = ast.nodes.items(.data);
    const token_tags = ast.tokens.items(.tag);

    var buf: [2]std.zig.Ast.Node.Index = undefined;

    if (ast.fullStructInit(&buf, node_links[0].lhs)) |node| {
        for (node.ast.fields) |field_index| {
            const token_index = ast.firstToken(field_index) - 2;
            if (token_tags[token_index] != .identifier) continue;

            const field_name = ast.tokenSlice(token_index);

            if (std.mem.eql(u8, field_name, "version")) {
                const span = ast.nodeToSpan(field_index);
                return .{
                    .start = span.start + 1,
                    .end = span.end - 1,
                };
            }
        }
    }

    return error.InvalidFileFormat;
}

test "invalid zon format" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .dependencies = .{},
        \\}
    ;

    const result = readVersionInternal(allocator, source);
    try std.testing.expectError(error.InvalidFileFormat, result);
}

test "read invalid version from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1,2,3",
        \\  .dependencies = .{},
        \\}
    ;

    const range = try readVersionInternal(allocator, source);
    const result = std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectError(error.InvalidVersion, result);
}

test "read version from zon" {
    const allocator = std.testing.allocator;

    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}

test "read version with pre-release from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-beta",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
        .pre = "beta",
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}

test "read version with build-meta from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
        .pre = "alpha", .build = "9876",
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}