const std = @import("std");

const CSSProperty = union(enum) { unknown: void, color: []const u8, background: []const u8 };

const CSSRule = struct { selector: []const u8, properties: []CSSProperty };

const CSSSheet = struct {
    rules: []CSSRule,

    fn display(sheet: CSSSheet) void {
        for (sheet.rules) |rule| {
            std.debug.print("selector: {s}\n", .{rule.selector});
            for (rule.properties) |property| {
                inline for (@typeInfo(CSSProperty).Union.fields) |u_field| {
                    if (comptime !std.mem.eql(u8, u_field.name, "unknown")) {
                        if (std.mem.eql(u8, u_field.name, @tagName(property))) {
                            std.debug.print(" {s}: {s}\n", .{ @tagName(property), @field(property, u_field.name) });
                        }
                    }
                }
            }
            std.debug.print("\n", .{});
        }
    }
};

fn debugAt(css: []const u8, index: usize, comptime msg: []const u8, args: anytype) void {
    var line_no: usize = 1;
    var col_no: usize = 0;

    var i: usize = 0;
    var line_beginning: usize = 0;
    var found_line = false;

    while (i < css.len) : (i += 1) {
        if (css[i] == '\n') {
            if (!found_line) {
                col_no = 0;
                line_beginning = i;
                line_no += 1;
                continue;
            } else {
                break;
            }
        }

        if (i == index) {
            found_line = true;
        }

        if (!found_line) {
            col_no += 1;
        }
    }

    std.debug.print("Error at line {}, column {}. ", .{ line_no, col_no });
    std.debug.print(msg ++ "\n\n", args);
    std.debug.print("{s}\n", .{css[line_beginning..i]});
    while (col_no > 0) : (col_no -= 1) {
        std.debug.print(" ", .{});
    }
    std.debug.print("^ Near here.\n", .{});
}

fn eatWhitespace(css: []const u8, initial_index: usize) usize {
    var index = initial_index;
    while (index < css.len and std.ascii.isWhitespace(css[index])) {
        index += 1;
    }

    return index;
}

fn parseSyntax(css: []const u8, initial_index: usize, syntax: u8) !usize {
    if (initial_index < css.len and css[initial_index] == syntax) {
        return initial_index + 1;
    }

    debugAt(css, initial_index, "Expected syntax: '{c}'.", .{syntax});
    return error.NoSuchSyntax;
}

const ParseIdentifierResult = struct { identifier: []const u8, index: usize };
fn parseIdentifier(css: []const u8, initial_index: usize) !ParseIdentifierResult {
    var index = initial_index;
    while (index < css.len and std.ascii.isAlphabetic(css[index])) {
        index += 1;
    }

    if (index == initial_index) {
        debugAt(css, initial_index, "Expected valid identifier.", .{});
        return error.InvalidIdentifier;
    }

    return ParseIdentifierResult{
        .identifier = css[initial_index..index],
        .index = index,
    };
}

fn matchProperty(name: []const u8, value: []const u8) !CSSProperty {
    const cssPropertyInfo = @typeInfo(CSSProperty);

    inline for (cssPropertyInfo.Union.fields) |u_field| {
        if (comptime !std.mem.eql(u8, u_field.name, "unknown")) {
            if (std.mem.eql(u8, u_field.name, name)) {
                return @unionInit(CSSProperty, u_field.name, value);
            }
        }
    }

    return error.UnknownProperty;
}

const ParsePropertyResult = struct {
    property: CSSProperty,
    index: usize,
};
fn parseProperty(css: []const u8, initial_index: usize) !ParsePropertyResult {
    var index = eatWhitespace(css, initial_index);

    const name_res = try parseIdentifier(css, index);
    index = name_res.index;

    index = try parseSyntax(css, index, ':');

    index = eatWhitespace(css, index);

    const property_res = try parseIdentifier(css, index);
    index = property_res.index;

    index = try parseSyntax(css, index, ';');

    const property = matchProperty(name_res.identifier, property_res.identifier) catch |e| {
        debugAt(css, initial_index, "Unknown property: '{s}'.", .{name_res.identifier});
        return e;
    };

    return ParsePropertyResult{ .property = property, .index = index };
}

const ParseRuleResult = struct { rule: CSSRule, index: usize };
fn parseRule(allocator: std.mem.Allocator, css: []const u8, initial_index: usize) !ParseRuleResult {
    var index = eatWhitespace(css, initial_index);

    const identifier_res = try parseIdentifier(css, index);
    index = identifier_res.index;

    index = eatWhitespace(css, index);
    index = try parseSyntax(css, index, '{');

    var properties = std.ArrayList(CSSProperty).init(allocator);

    while (index < css.len) {
        index = eatWhitespace(css, index);
        if (index < css.len and css[index] == '}') {
            break;
        }

        const property_res = try parseProperty(css, index);
        index = property_res.index;

        try properties.append(property_res.property);
    }

    index = eatWhitespace(css, index);
    index = try parseSyntax(css, index, '}');

    return ParseRuleResult{ .rule = CSSRule{ .selector = identifier_res.identifier, .properties = properties.items }, .index = index };
}

fn parse(allocator: std.mem.Allocator, css: []const u8) !CSSSheet {
    var rules = std.ArrayList(CSSRule).init(allocator);
    var index: usize = 0;

    while (index < css.len) {
        const rule_res = try parseRule(allocator, css, index);
        index = rule_res.index;
        try rules.append(rule_res.rule);
        index = eatWhitespace(css, index);
    }

    return CSSSheet{ .rules = rules.items };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = std.process.args();
    _ = args.next();

    var file_name: []const u8 = "";
    if (args.next()) |f| {
        file_name = f;
    }

    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const css_file = try allocator.alloc(u8, file_size);
    _ = try file.read(css_file);

    const sheet = parse(allocator, css_file) catch return;

    sheet.display();
}
