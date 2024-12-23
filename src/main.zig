const std = @import("std");

// Enum to represent the type of comment.
const CommentType = enum { singleLine, multiLine, preprocessor };

// State related to comment handling.
const CommentState = struct {
    in_comment: bool = false,
    type: ?CommentType = null,
};

// State related to quote handling.
const QuoteState = struct {
    in_quotes: bool = false,
    quote_char: u8 = 0,
    escaped: bool = false, // To handle escape characters within quotes.
};

// State related to HTML handling.
const HTMLState = struct {
    in_html: bool = false,
    tag_depth: usize = 0, // To handle nested HTML tags.
};

// The overall state of the minifier.
const MinifierState = struct {
    comment: CommentState = .{},
    quote: QuoteState = .{},
    html: HTMLState = .{},
    prev_char: u8 = '\n', // assume newline before first line
    pprev_char: u8 = '\n', // not always updated in loop
    next_char: u8 = 0, // not always updated in loop
    dealed_WhitespaceBefore: bool = false,
    is_line_start: bool = true,
};

// Handles the logic for comment processing.
fn handleComment(state: *MinifierState, c: u8, minified: *std.ArrayList(u8)) !void {
    if (state.quote.in_quotes or state.html.in_html) return;
    if (state.comment.in_comment) {
        const comment_type = state.comment.type orelse return;
        switch (comment_type) {
            .singleLine, .preprocessor => {
                if (c == '\n') state.comment.in_comment = false;
            },
            .multiLine => {
                if (state.prev_char == '*' and c == '/') state.comment.in_comment = false;
            },
        }
    } else {
        if (c == '/' and state.prev_char == '/') {
            state.comment.in_comment = true;
            state.comment.type = .singleLine;
            if (minified.items.len != 0) minified.items.len -= 1;
        } else if (c == '*' and state.prev_char == '/') {
            state.comment.in_comment = true;
            state.comment.type = .multiLine;
            if (minified.items.len != 0) minified.items.len -= 1;
        } else if (c == '#' and state.is_line_start) {
            state.comment.in_comment = true;
            state.comment.type = .preprocessor;
        }
    }
}

// Handles the logic for quote processing.
fn handleQuotes(state: *MinifierState, c: u8, minified: *std.ArrayList(u8)) !void {
    if (state.quote.in_quotes) {
        if (state.quote.escaped) {
            state.quote.escaped = false;
        } else {
            if (c == '\\') {
                state.quote.escaped = true;
            } else if (c == state.quote.quote_char) {
                state.quote.in_quotes = false;
                return; // otherwise ending quote_char will be added twice
            }
        }
        try minified.append(c);
    } else if (c == '"' or c == '\'') {
        state.quote.in_quotes = true;
        state.quote.quote_char = c;
        try minified.append(c);
    }
}

// Handles the logic for HTML processing.
fn handleHTML(state: *MinifierState, c: u8, minified: *std.ArrayList(u8)) !void {
    if (state.html.in_html) {
        if (c == '<') {
            state.html.tag_depth += 1;
        } else if (c == '>') {
            state.html.tag_depth -= 1;
            if (state.html.tag_depth == 0) {
                state.html.in_html = false;
            }
        }
        if (state.html.in_html) try minified.append(c);
    } else if (c == '<') {
        state.html.in_html = true;
        state.html.tag_depth = 1;
        try minified.append(c);
    }
}

// Handles whitespace with context awareness.
fn handleWhitespace(state: *MinifierState, c: u8, minified: *std.ArrayList(u8)) !void {
    if (state.quote.in_quotes or state.html.in_html) return;
    if (std.ascii.isWhitespace(c) and !std.ascii.isWhitespace(state.prev_char)) {
        switch (state.prev_char) {
            ';', '[', ']', '{', '}', '=' => {},
            // "-> ", "-- "
            '>', '-' => if (state.pprev_char != '-') try minified.append(' '),
            else => try minified.append(' '),
        }
    }
}

fn handleWhitespaceBefore(state: *MinifierState, c: u8, minified: *std.ArrayList(u8)) !void {
    if (state.quote.in_quotes or state.html.in_html) return;
    state.dealed_WhitespaceBefore = false;
    switch (c) {
        ';', '[', ']', '{', '}', '=', '-' => {
            if (c == '-' and !(state.next_char == '>' or state.next_char == '-')) return; // " ->", " --"
            var start = minified.items.len;
            while (start > 0 and minified.items[start - 1] == ' ') {
                start -= 1;
            }
            minified.items.len = start;
            try minified.append(c);
            state.dealed_WhitespaceBefore = true;
        },
        else => {},
    }
}

pub fn minifyDot(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var minified = try std.ArrayList(u8).initCapacity(allocator, input.len);
    defer minified.deinit();

    var state = MinifierState{};

    // var line_start: usize = 0;
    for (input, 0..) |c, i| {
        handles: { // a block for handy break;
            if (c == '\n') {
                // ending of singline comment -> state modify; better to be in handle
                if (state.comment.in_comment and (state.comment.type == .singleLine or state.comment.type == .preprocessor)) {
                    state.comment.in_comment = false;
                    break :handles;
                }
                if (!state.comment.in_comment and !state.quote.in_quotes) {
                    switch (state.prev_char) {
                        ';', '[', ']', '{', '}', '\n' => {},
                        else => try minified.append(' '),
                    }
                }
                break :handles;
            }
            // state.is_line_start
            if (state.prev_char == '\n') state.is_line_start = true;
            if (!std.ascii.isWhitespace(state.prev_char) and state.is_line_start) state.is_line_start = false;

            try handleComment(&state, c, &minified);
            if (state.comment.in_comment) break :handles;

            try handleQuotes(&state, c, &minified);
            if (state.quote.in_quotes) break :handles;

            try handleHTML(&state, c, &minified);
            if (state.html.in_html) break :handles;

            if (i >= 2) state.pprev_char = input[i - 2]; // state.pprev_char is only used by handleWhitespace
            try handleWhitespace(&state, c, &minified);
            if (std.ascii.isWhitespace(c)) break :handles;

            if (i + 1 < input.len) state.next_char = input[i + 1] else state.next_char = 0; // state.next_chat is only used by handleWhitespaceBefore
            try handleWhitespaceBefore(&state, c, &minified);
            if (state.dealed_WhitespaceBefore == true) break :handles;

            try minified.append(c);
        }
        state.prev_char = c;
    }

    return minified.toOwnedSlice();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var reader = std.io.getStdIn().reader();
    var writer = std.io.getStdOut().writer();

    const initial_size = 4096;
    var input = try std.ArrayList(u8).initCapacity(allocator, initial_size);
    defer input.deinit();

    var buffer: [4096]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        try input.appendSlice(line);
        try input.append('\n');
    }
    const input_slice = input.items;

    const minified_dot = try minifyDot(allocator, input_slice);
    defer allocator.free(minified_dot);

    try writer.writeAll(minified_dot);
}
