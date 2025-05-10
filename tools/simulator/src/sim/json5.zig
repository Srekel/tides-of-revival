// JSON5 parser conforming to JSON5 standard.
// https://json5.github.io/json5-spec

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const maxInt = std.math.maxInt;

// Assigned this to Json5 to avoid some ambigous references in the file
const Json5 = @This();

const StringEscapes = union(enum) {
    None,
    Some: struct {
        size_diff: isize,
    },
};

/// Checks to see if a string matches what it would be as a json5-encoded string
/// Assumes that `encoded` is a well-formed json5 string
fn encodesTo(decoded: []const u8, encoded: []const u8) bool {
    var i: usize = 0;
    var j: usize = 0;
    while (i < decoded.len) {
        if (j >= encoded.len) return false;
        if (encoded[j] != '\\') {
            if (decoded[i] != encoded[j]) return false;
            j += 1;
            i += 1;
        } else {
            const escape_type = encoded[j + 1];
            if (escape_type != 'u') {
                const t: u8 = switch (escape_type) {
                    '\\' => '\\',
                    '/' => '/',
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    'f' => 12,
                    'b' => 8,
                    '"' => '"',
                    '\'' => '\'',
                    '\n' => '\n',
                    else => unreachable,
                };
                if (decoded[i] != t) return false;
                j += 2;
                i += 1;
            } else {
                var codepoint = std.fmt.parseInt(u21, encoded[j + 2 .. j + 6], 16) catch unreachable;
                j += 6;
                if (codepoint >= 0xD800 and codepoint < 0xDC00) {
                    // surrogate pair
                    assert(encoded[j] == '\\');
                    assert(encoded[j + 1] == 'u');
                    const low_surrogate = std.fmt.parseInt(u21, encoded[j + 2 .. j + 6], 16) catch unreachable;
                    codepoint = 0x10000 + (((codepoint & 0x03ff) << 10) | (low_surrogate & 0x03ff));
                    j += 6;
                }
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(codepoint, &buf) catch unreachable;
                if (i + len > decoded.len) return false;
                if (!mem.eql(u8, decoded[i .. i + len], buf[0..len])) return false;
                i += len;
            }
        }
    }
    assert(i == decoded.len);
    assert(j == encoded.len);
    return true;
}

/// A single token slice into the parent string.
///
/// Use `token.slice()` on the input at the current position to get the current slice.
pub const Token = union(enum) {
    ObjectBegin,
    ObjectEnd,
    ArrayBegin,
    ArrayEnd,
    String: struct {
        /// How many bytes the token is.
        count: usize,

        /// Whether string contains an escape sequence and cannot be zero-copied
        escapes: StringEscapes,

        pub fn decodedLength(self: @This()) usize {
            return self.count +% switch (self.escapes) {
                .None => 0,
                .Some => |s| @as(usize, @bitCast(s.size_diff))
            };
        }

        /// Slice into the underlying input string.
        pub fn slice(self: @This(), input: []const u8, i: usize) []const u8 {
            return input[i - self.count .. i];
        }
    },
    Number: struct {
        /// How many bytes the token is.
        count: usize,

        /// Whether number is simple and can be represented by an integer (i.e. no `.` or `e`)
        is_integer: bool,

        /// Slice into the underlying input string.
        pub fn slice(self: @This(), input: []const u8, i: usize) []const u8 {
            return input[i - self.count .. i];
        }
    },
    True,
    False,
    Null,
};

const AggregateContainerType = enum(u1) { object, array };

// A LIFO bit-stack. Tracks which container-types have been entered during parse.
fn AggregateContainerStack(comptime n: usize) type {
    return struct {
        const Self = @This();

        const element_bitcount = 8 * @sizeOf(usize);
        const element_count = n / element_bitcount;
        const ElementType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = element_bitcount } });
        const ElementShiftAmountType = std.math.Log2Int(ElementType);

        comptime {
            std.debug.assert(n % element_bitcount == 0);
        }

        memory: [element_count]ElementType,
        len: usize,

        pub fn init(self: *Self) void {
            self.memory = [_]ElementType{0} ** element_count;
            self.len = 0;
        }

        pub fn push(self: *Self, ty: AggregateContainerType) ?void {
            if (self.len >= n) {
                return null;
            }

            const index = self.len / element_bitcount;
            const sub_index = @as(ElementShiftAmountType, @intCast(self.len % element_bitcount));
            const clear_mask = ~(@as(ElementType, 1) << sub_index);
            const set_bits = @as(ElementType, @intFromEnum(ty)) << sub_index;

            self.memory[index] &= clear_mask;
            self.memory[index] |= set_bits;
            self.len += 1;
        }

        pub fn peek(self: *Self) ?AggregateContainerType {
            if (self.len == 0) {
                return null;
            }

            const bit_to_extract = self.len - 1;
            const index = bit_to_extract / element_bitcount;
            const sub_index = @as(ElementShiftAmountType, @intCast( bit_to_extract % element_bitcount));
            const bit = @as(u1, @intCast((self.memory[index] >> sub_index) & 1));
            return @enumFromInt(bit);
        }

        pub fn pop(self: *Self) ?AggregateContainerType {
            if (self.peek()) |ty| {
                self.len -= 1;
                return ty;
            }

            return null;
        }
    };
}

/// A small streaming JSON5 parser. This accepts input one byte at a time and returns tokens as
/// they are encountered. No copies or allocations are performed during parsing and the entire
/// parsing state requires ~40-50 bytes of stack space.
///
/// Conforms strictly to RFC8259.
///
/// For a non-byte based wrapper, consider using TokenStream instead.
pub const StreamingParser = struct {
    pub const default_max_nestings = 256;

    // Current state
    state: State,
    // How many bytes we have counted for the current token
    count: usize,
    // What state to follow after parsing a string (either property or value string)
    after_string_state: State,
    // What state to follow after parsing a value (either top-level or value end)
    after_value_state: State,
    // If we stopped now, would the complete parsed string to now be a valid json5 string
    complete: bool,
    string_is_single_quote: bool,
    // Current token flags to pass through to the next generated, see Token.
    string_escapes: StringEscapes,
    // When in .String states, was the previous character a high surrogate?
    string_last_was_high_surrogate: bool,
    // Used inside of StringEscapeHexUnicode* states
    string_unicode_codepoint: u21,
    // The first byte needs to be stored to validate 3- and 4-byte sequences.
    sequence_first_byte: u8 = undefined,
    // When in .Number states, is the number a (still) valid integer?
    number_is_integer: bool,
    // Bit-stack for nested object/map literals (max 256 nestings).
    stack: AggregateContainerStack(default_max_nestings),

    pub fn init() StreamingParser {
        var p: StreamingParser = undefined;
        p.reset();
        return p;
    }

    pub fn reset(p: *StreamingParser) void {
        p.state = .TopLevelBegin;
        p.count = 0;
        // Set before ever read in main transition function
        p.after_string_state = undefined;
        p.after_value_state = .ValueEnd; // handle end of values normally
        p.stack.init();
        p.complete = false;
        p.string_escapes = undefined;
        p.string_last_was_high_surrogate = undefined;
        p.string_unicode_codepoint = undefined;
        p.string_is_single_quote = false;
        p.number_is_integer = undefined;
    }

    pub const State = enum(u8) {
        // These must be first with these explicit values as we rely on them for indexing the
        // bit-stack directly and avoiding a branch.
        ObjectSeparator = 0,
        ValueEnd = 1,

        TopLevelBegin,
        TopLevelEnd,

        CommentBegin, // when the character is '/'
        CommentMultiLine, // multi-line comment parsing continues
        CommentMultiLineEnd, // when the character is '*'
        CommentSingleLine, // when the character isn't '\n'

        ValueBegin,
        ValueBeginNoClosing,

        Identifier,

        String,
        StringUtf8Byte2Of2,
        StringUtf8Byte2Of3,
        StringUtf8Byte3Of3,
        StringUtf8Byte2Of4,
        StringUtf8Byte3Of4,
        StringUtf8Byte4Of4,
        StringEscapeCharacter,
        StringEscapeHexUnicode4,
        StringEscapeHexUnicode3,
        StringEscapeHexUnicode2,
        StringEscapeHexUnicode1,

        Number,
        NumberMaybeDotOrExponent,
        NumberMaybeDigitOrDotOrExponent,
        NumberFractionalRequired,
        NumberFractional,
        NumberMaybeExponent,
        NumberExponent,
        NumberExponentDigitsRequired,
        NumberExponentDigits,

        TrueLiteral1,
        TrueLiteral2,
        TrueLiteral3,

        FalseLiteral1,
        FalseLiteral2,
        FalseLiteral3,
        FalseLiteral4,

        NullLiteral1,
        NullLiteral2,
        NullLiteral3,

        // Given an aggregate container type, return the state which should be entered after
        // processing a complete value type.
        pub fn fromAggregateContainerType(ty: AggregateContainerType) State {
            comptime {
                std.debug.assert(@intFromEnum(AggregateContainerType.object) == @intFromEnum(State.ObjectSeparator));
                std.debug.assert(@intFromEnum(AggregateContainerType.array) == @intFromEnum(State.ValueEnd));
            }

            return @enumFromInt(@intFromEnum(ty));
        }
    };

    pub const Error = error{
        InvalidTopLevel,
        TooManyNestedItems,
        TooManyClosingItems,
        InvalidValueBegin,
        InvalidValueEnd,
        UnbalancedBrackets,
        UnbalancedBraces,
        UnexpectedClosingBracket,
        UnexpectedClosingBrace,
        InvalidComment,
        InvalidNumber,
        InvalidSeparator,
        InvalidLiteral,
        InvalidEscapeCharacter,
        InvalidUnicodeHexSymbol,
        InvalidUtf8Byte,
        InvalidTopLevelTrailing,
        InvalidControlCharacter,
        InvalidIdentifier,
    };

    /// Give another byte to the parser and obtain any new tokens. This may (rarely) return two
    /// tokens. token2 is always null if token1 is null.
    ///
    /// There is currently no error recovery on a bad stream.
    pub fn feed(p: *StreamingParser, c: u8, token1: *?Token, token2: *?Token) Error!void {
        token1.* = null;
        token2.* = null;
        p.count += 1;

        // unlikely
        if (try p.transition(c, token1)) {
            _ = try p.transition(c, token2);
        }
    }

    // Perform a single transition on the state machine and return any possible token.
    fn transition(p: *StreamingParser, c: u8, token: *?Token) Error!bool {
        switch (p.state) {
            .TopLevelBegin => switch (c) {
                '{' => {
                    p.stack.push(.object) orelse return error.TooManyNestedItems;
                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;

                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    p.stack.push(.array) orelse return error.TooManyNestedItems;
                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;

                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '"', '\'' => {
                    p.state = .String;
                    p.after_value_state = .TopLevelEnd;
                    // We don't actually need the following since after_value_state should override.
                    p.after_string_state = .ValueEnd;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;

                    p.string_is_single_quote = c == '\'';
                },
                't' => {
                    p.state = .TrueLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                'f' => {
                    p.state = .FalseLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                'n' => {
                    p.state = .NullLiteral1;
                    p.after_value_state = .TopLevelEnd;
                    p.count = 0;
                },
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .TopLevelBegin;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                else => {
                    return error.InvalidTopLevel;
                },
            },

            .TopLevelEnd => switch (c) {
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .TopLevelEnd;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                else => {
                    return error.InvalidTopLevelTrailing;
                },
            },
            .CommentBegin => switch (c) {
                '*' => {
                    p.state = .CommentMultiLine;
                },
                '/' => {
                    p.state = .CommentSingleLine;
                },
                else => {
                    return error.InvalidComment;
                },
            },
            .CommentMultiLine => switch (c) {
                '*' => {
                    p.state = .CommentMultiLineEnd;
                },
                else => {},
            },
            .CommentMultiLineEnd => switch (c) {
                '/' => {
                    p.state = p.after_value_state;
                },
                else => {
                    p.state = .CommentMultiLine;
                },
            },
            .CommentSingleLine => switch (c) {
                '\n' => {
                    p.state = p.after_value_state;
                    if (p.after_value_state == .TopLevelBegin) {
                        p.after_value_state = .ValueEnd;
                    }
                },
                else => {},
            },

            .ValueBegin => switch (c) {
                // NOTE: These are shared in ValueEnd as well, think we can reorder states to
                // be a bit clearer and avoid this duplication.
                '}' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;

                    if (last_type != .object) {
                        return error.UnexpectedClosingBrace;
                    }

                    _ = p.stack.pop();
                    p.state = .ValueBegin;
                    p.after_string_state = State.fromAggregateContainerType(last_type);

                    switch (p.stack.len) {
                        0 => {
                            p.complete = true;
                            p.state = .TopLevelEnd;
                        },
                        else => {
                            p.state = .ValueEnd;
                        },
                    }

                    token.* = Token.ObjectEnd;
                },
                ']' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;

                    if (last_type != .array) {
                        return error.UnexpectedClosingBracket;
                    }

                    _ = p.stack.pop();
                    p.state = .ValueBegin;
                    p.after_string_state = State.fromAggregateContainerType(last_type);

                    switch (p.stack.len) {
                        0 => {
                            p.complete = true;
                            p.state = .TopLevelEnd;
                        },
                        else => {
                            p.state = .ValueEnd;
                        },
                    }

                    token.* = Token.ArrayEnd;
                },
                '{' => {
                    p.stack.push(.object) orelse return error.TooManyNestedItems;

                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;

                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    p.stack.push(.array) orelse return error.TooManyNestedItems;

                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;

                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.count = 0;
                },
                '"', '\'' => {
                    p.state = .String;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;
                    p.string_is_single_quote = c == '\'';
                },
                't' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;
                    if (last_type == .object or p.after_string_state == .ObjectSeparator) {
                        p.state = .Identifier;
                    } else {
                        p.state = .TrueLiteral1;
                    }
                    p.count = 0;
                },
                'f' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;
                    if (last_type == .object or p.after_string_state == .ObjectSeparator) {
                        p.state = .Identifier;
                    } else {
                        p.state = .FalseLiteral1;
                    }
                    p.count = 0;
                },
                'n' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;
                    if (last_type == .object) {
                        p.state = .Identifier;
                    } else {
                        p.state = .NullLiteral1;
                    }
                    p.count = 0;
                },
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .ValueBegin;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                ',' => {
                    if (p.after_string_state != .ObjectSeparator and p.after_string_state != .ValueEnd) {
                        return error.InvalidValueBegin;
                    }
                },
                else => {
                    if (identifierStartTable[c]) {
                        p.state = .Identifier;
                        p.count = 0;
                    } else {
                        return error.InvalidValueBegin;
                    }
                },
            },

            // TODO: A bit of duplication here and in the following state, redo.
            .ValueBeginNoClosing => switch (c) {
                '{' => {
                    p.stack.push(.object) orelse return error.TooManyNestedItems;

                    p.state = .ValueBegin;
                    p.after_string_state = .ObjectSeparator;

                    token.* = Token.ObjectBegin;
                },
                '[' => {
                    p.stack.push(.array) orelse return error.TooManyNestedItems;

                    p.state = .ValueBegin;
                    p.after_string_state = .ValueEnd;

                    token.* = Token.ArrayBegin;
                },
                '-' => {
                    p.number_is_integer = true;
                    p.state = .Number;
                    p.count = 0;
                },
                '0' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDotOrExponent;
                    p.count = 0;
                },
                '1'...'9' => {
                    p.number_is_integer = true;
                    p.state = .NumberMaybeDigitOrDotOrExponent;
                    p.count = 0;
                },
                '"', '\'' => {
                    p.state = .String;
                    p.string_escapes = .None;
                    p.string_last_was_high_surrogate = false;
                    p.count = 0;
                    p.string_is_single_quote = c == '\'';
                },
                't' => {
                    if (p.after_string_state == .ObjectSeparator) {
                        p.state = .Identifier;
                    } else {
                        p.state = .TrueLiteral1;
                    }
                    p.count = 0;
                },
                'f' => {
                    if (p.after_string_state == .ObjectSeparator) {
                        p.state = .Identifier;
                    } else {
                        p.state = .FalseLiteral1;
                    }
                    p.count = 0;
                },
                'n' => {
                    if (p.after_string_state == .ObjectSeparator) {
                        p.state = .Identifier;
                    } else {
                        p.state = .NullLiteral1;
                    }
                    p.count = 0;
                },
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .ValueBeginNoClosing;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                else => {
                    return error.InvalidValueBegin;
                },
            },

            .ValueEnd => switch (c) {
                ']' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;

                    if (last_type != .array) {
                        return error.UnexpectedClosingBracket;
                    }

                    _ = p.stack.pop();
                    p.state = .ValueEnd;
                    p.after_string_state = State.fromAggregateContainerType(last_type);

                    if (p.stack.len == 0) {
                        p.complete = true;
                        p.state = .TopLevelEnd;
                    }

                    token.* = Token.ArrayEnd;
                },
                '}' => {
                    const last_type = p.stack.peek() orelse return error.TooManyClosingItems;

                    if (last_type != .object) {
                        return error.UnexpectedClosingBrace;
                    }

                    _ = p.stack.pop();
                    p.state = .ValueEnd;
                    p.after_string_state = State.fromAggregateContainerType(last_type);

                    if (p.stack.len == 0) {
                        p.complete = true;
                        p.state = .TopLevelEnd;
                    }

                    token.* = Token.ObjectEnd;
                },
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .ValueEnd;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                ',' => {
                    p.state = .ValueBegin;
                },
                ':' => {
                    p.state = .ValueBeginNoClosing;
                    p.after_string_state = .ValueEnd;
                },
                else => {
                    return error.InvalidValueEnd;
                },
            },

            .Identifier => switch (c) {
                0x09, 0x0A, 0x0D, 0x20 => {
                    p.state = p.after_string_state;
                    token.* = .{ .String = .{ .count = p.count, .escapes = StringEscapes.None } };
                },
                ':' => {
                    p.state = .ValueBeginNoClosing;
                    p.after_string_state = .ValueEnd;
                    token.* = .{ .String = .{ .count = p.count, .escapes = StringEscapes.None } };
                },
                else => {
                    if (!identifierTable[c]) {
                        return error.InvalidIdentifier;
                    }
                },
            },

            .ObjectSeparator => switch (c) {
                ':' => {
                    p.state = .ValueBeginNoClosing;
                    p.after_string_state = .ValueEnd;
                },
                '/' => {
                    p.state = .CommentBegin;
                    p.after_value_state = .ObjectSeparator;
                },
                0x09, 0x0A, 0x0D, 0x20 => {
                    // whitespace
                },
                else => {
                    return error.InvalidSeparator;
                },
            },

            .String => switch (c) {
                0x00...0x1F => {
                    return error.InvalidControlCharacter;
                },
                '"', '\'' => {
                    const double_quote_end = (c == '"' and !p.string_is_single_quote);
                    const single_quote_end = (c == '\'' and p.string_is_single_quote);

                    if (double_quote_end or single_quote_end) {
                        p.state = p.after_string_state;
                        if (p.after_value_state == .TopLevelEnd) {
                            p.state = .TopLevelEnd;
                            p.complete = true;
                        }

                        token.* = .{
                            .String = .{
                                .count = p.count - 1,
                                .escapes = p.string_escapes,
                            },
                        };
                        p.string_escapes = undefined;
                        p.string_last_was_high_surrogate = undefined;
                        p.string_is_single_quote = false;
                    } else {
                        p.string_last_was_high_surrogate = false;
                    }
                },
                '\\' => {
                    p.state = .StringEscapeCharacter;
                    switch (p.string_escapes) {
                        .None => {
                            p.string_escapes = .{ .Some = .{ .size_diff = 0 } };
                        },
                        .Some => {},
                    }
                },
                0x20, 0x21, 0x23...0x26, 0x28...0x5B, 0x5D...0x7F => {
                    // non-control ascii
                    p.string_last_was_high_surrogate = false;
                },
                0xC2...0xDF => {
                    p.state = .StringUtf8Byte2Of2;
                },
                0xE0...0xEF => {
                    p.state = .StringUtf8Byte2Of3;
                    p.sequence_first_byte = c;
                },
                0xF0...0xF4 => {
                    p.state = .StringUtf8Byte2Of4;
                    p.sequence_first_byte = c;
                },
                else => {
                    return error.InvalidUtf8Byte;
                },
            },

            .StringUtf8Byte2Of2 => switch (c >> 6) {
                0b10 => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte2Of3 => {
                switch (p.sequence_first_byte) {
                    0xE0 => switch (c) {
                        0xA0...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xE1...0xEF => switch (c) {
                        0x80...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    else => return error.InvalidUtf8Byte,
                }
                p.state = .StringUtf8Byte3Of3;
            },
            .StringUtf8Byte3Of3 => switch (c) {
                0x80...0xBF => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte2Of4 => {
                switch (p.sequence_first_byte) {
                    0xF0 => switch (c) {
                        0x90...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xF1...0xF3 => switch (c) {
                        0x80...0xBF => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    0xF4 => switch (c) {
                        0x80...0x8F => {},
                        else => return error.InvalidUtf8Byte,
                    },
                    else => return error.InvalidUtf8Byte,
                }
                p.state = .StringUtf8Byte3Of4;
            },
            .StringUtf8Byte3Of4 => switch (c) {
                0x80...0xBF => p.state = .StringUtf8Byte4Of4,
                else => return error.InvalidUtf8Byte,
            },
            .StringUtf8Byte4Of4 => switch (c) {
                0x80...0xBF => p.state = .String,
                else => return error.InvalidUtf8Byte,
            },

            .StringEscapeCharacter => switch (c) {
                // NOTE: '/' is allowed as an escaped character but it also is allowed
                // as unescaped according to the RFC. There is a reported errata which suggests
                // removing the non-escaped variant but it makes more sense to simply disallow
                // it as an escape code here.
                //
                // The current JSON5TestSuite tests rely on both of this behaviour being present
                // however, so we default to the status quo where both are accepted until this
                // is further clarified.
                '"', '\'', '\\', '/', 'b', 'f', 'n', 'r', 't', '\n' => {
                    p.string_escapes.Some.size_diff -= 1;
                    p.state = .String;
                    p.string_last_was_high_surrogate = false;
                },
                'u' => {
                    p.state = .StringEscapeHexUnicode4;
                },
                else => {
                    return error.InvalidEscapeCharacter;
                },
            },

            .StringEscapeHexUnicode4 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode3;
                p.string_unicode_codepoint = codepoint << 12;
            },

            .StringEscapeHexUnicode3 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode2;
                p.string_unicode_codepoint |= codepoint << 8;
            },

            .StringEscapeHexUnicode2 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .StringEscapeHexUnicode1;
                p.string_unicode_codepoint |= codepoint << 4;
            },

            .StringEscapeHexUnicode1 => {
                var codepoint: u21 = undefined;
                switch (c) {
                    else => return error.InvalidUnicodeHexSymbol,
                    '0'...'9' => {
                        codepoint = c - '0';
                    },
                    'A'...'F' => {
                        codepoint = c - 'A' + 10;
                    },
                    'a'...'f' => {
                        codepoint = c - 'a' + 10;
                    },
                }
                p.state = .String;
                p.string_unicode_codepoint |= codepoint;
                if (p.string_unicode_codepoint < 0xD800 or p.string_unicode_codepoint >= 0xE000) {
                    // not part of surrogate pair
                    p.string_escapes.Some.size_diff -= @as(isize, 6 - (std.unicode.utf8CodepointSequenceLength(p.string_unicode_codepoint) catch unreachable));
                    p.string_last_was_high_surrogate = false;
                } else if (p.string_unicode_codepoint < 0xDC00) {
                    // 'high' surrogate
                    // takes 3 bytes to encode a half surrogate pair into wtf8
                    p.string_escapes.Some.size_diff -= 6 - 3;
                    p.string_last_was_high_surrogate = true;
                } else {
                    // 'low' surrogate
                    p.string_escapes.Some.size_diff -= 6;
                    if (p.string_last_was_high_surrogate) {
                        // takes 4 bytes to encode a full surrogate pair into utf8
                        // 3 bytes are already reserved by high surrogate
                        p.string_escapes.Some.size_diff -= -1;
                    } else {
                        // takes 3 bytes to encode a half surrogate pair into wtf8
                        p.string_escapes.Some.size_diff -= -3;
                    }
                    p.string_last_was_high_surrogate = false;
                }
                p.string_unicode_codepoint = undefined;
            },

            .Number => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0' => {
                        p.state = .NumberMaybeDotOrExponent;
                    },
                    '1'...'9' => {
                        p.state = .NumberMaybeDigitOrDotOrExponent;
                    },
                    else => {
                        return error.InvalidNumber;
                    },
                }
            },

            .NumberMaybeDotOrExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '.' => {
                        p.number_is_integer = false;
                        p.state = .NumberFractionalRequired;
                    },
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        p.number_is_integer = undefined;
                        return true;
                    },
                }
            },

            .NumberMaybeDigitOrDotOrExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '.' => {
                        p.number_is_integer = false;
                        p.state = .NumberFractionalRequired;
                    },
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    '0'...'9' => {
                        // another digit
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },

            .NumberFractionalRequired => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {
                        p.state = .NumberFractional;
                    },
                    else => {
                        return error.InvalidNumber;
                    },
                }
            },

            .NumberFractional => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {
                        // another digit
                    },
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },

            .NumberMaybeExponent => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    'e', 'E' => {
                        p.number_is_integer = false;
                        p.state = .NumberExponent;
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },

            .NumberExponent => switch (c) {
                '-', '+' => {
                    p.complete = false;
                    p.state = .NumberExponentDigitsRequired;
                },
                '0'...'9' => {
                    p.complete = p.after_value_state == .TopLevelEnd;
                    p.state = .NumberExponentDigits;
                },
                else => {
                    return error.InvalidNumber;
                },
            },

            .NumberExponentDigitsRequired => switch (c) {
                '0'...'9' => {
                    p.complete = p.after_value_state == .TopLevelEnd;
                    p.state = .NumberExponentDigits;
                },
                else => {
                    return error.InvalidNumber;
                },
            },

            .NumberExponentDigits => {
                p.complete = p.after_value_state == .TopLevelEnd;
                switch (c) {
                    '0'...'9' => {
                        // another digit
                    },
                    else => {
                        p.state = p.after_value_state;
                        token.* = .{
                            .Number = .{
                                .count = p.count,
                                .is_integer = p.number_is_integer,
                            },
                        };
                        return true;
                    },
                }
            },

            .TrueLiteral1 => switch (c) {
                'r' => p.state = .TrueLiteral2,
                else => {
                    if (identifierTable[c]) {
                        p.state = .Identifier;
                    } else {
                        return error.InvalidLiteral;
                    }
                },
            },

            .TrueLiteral2 => switch (c) {
                'u' => p.state = .TrueLiteral3,
                else => return error.InvalidLiteral,
            },

            .TrueLiteral3 => switch (c) {
                'e' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.True;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },

            .FalseLiteral1 => switch (c) {
                'a' => p.state = .FalseLiteral2,
                else => return error.InvalidLiteral,
            },

            .FalseLiteral2 => switch (c) {
                'l' => p.state = .FalseLiteral3,
                else => return error.InvalidLiteral,
            },

            .FalseLiteral3 => switch (c) {
                's' => p.state = .FalseLiteral4,
                else => return error.InvalidLiteral,
            },

            .FalseLiteral4 => switch (c) {
                'e' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.False;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },

            .NullLiteral1 => switch (c) {
                'u' => p.state = .NullLiteral2,
                else => return error.InvalidLiteral,
            },

            .NullLiteral2 => switch (c) {
                'l' => p.state = .NullLiteral3,
                else => return error.InvalidLiteral,
            },

            .NullLiteral3 => switch (c) {
                'l' => {
                    p.state = p.after_value_state;
                    p.complete = p.state == .TopLevelEnd;
                    token.* = Token.Null;
                },
                else => {
                    return error.InvalidLiteral;
                },
            },
        }

        return false;
    }
};

/// A small wrapper over a StreamingParser for full slices. Returns a stream of json5 Tokens.
pub const TokenStream = struct {
    i: usize,
    slice: []const u8,
    parser: StreamingParser,
    token: ?Token,

    pub const Error = StreamingParser.Error || error{UnexpectedEndOfJson5};

    pub fn init(slice: []const u8) TokenStream {
        return TokenStream{
            .i = 0,
            .slice = slice,
            .parser = StreamingParser.init(),
            .token = null,
        };
    }

    pub fn stackUsed(self: *TokenStream) usize {
        return self.parser.stack.len + if (self.token != null) @as(usize, 1) else 0;
    }

    pub fn next(self: *TokenStream) Error!?Token {
        if (self.token) |token| {
            self.token = null;
            return token;
        }

        var t1: ?Token = undefined;
        var t2: ?Token = undefined;

        while (self.i < self.slice.len) {
            try self.parser.feed(self.slice[self.i], &t1, &t2);
            self.i += 1;

            if (t1) |token| {
                self.token = t2;
                return token;
            }
        }

        // Without this a bare number fails, the streaming parser doesn't know the input ended
        try self.parser.feed(' ', &t1, &t2);
        self.i += 1;

        if (t1) |token| {
            return token;
        } else if (self.parser.complete) {
            return null;
        } else {
            return error.UnexpectedEndOfJson5;
        }
    }
};

/// Validate a JSON5 string. This does not limit number precision so a decoder may not necessarily
/// be able to decode the string even if this returns true.
pub fn validate(s: []const u8) bool {
    var p = StreamingParser.init();

    for (s) |c| {
        var token1: ?Token = undefined;
        var token2: ?Token = undefined;

        p.feed(c, &token1, &token2) catch {
            return false;
        };
    }

    return p.complete;
}

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;

pub const ValueTree = struct {
    arena: ArenaAllocator,
    root: Value,

    pub fn deinit(self: *ValueTree) void {
        self.arena.deinit();
    }
};

pub const ObjectMap = StringArrayHashMap(Value);
pub const Array = ArrayList(Value);

/// Represents a JSON5 value
/// Currently only supports numbers that fit into i64 or f64.
pub const Value = union(enum) {
    Null,
    Bool: bool,
    Integer: i64,
    Float: f64,
    NumberString: []const u8,
    String: []const u8,
    Array: Array,
    Object: ObjectMap,

    pub fn json5Stringify(
        value: @This(),
        options: StringifyOptions,
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        switch (value) {
            .Null => try stringify(null, options, out_stream),
            .Bool => |inner| try stringify(inner, options, out_stream),
            .Integer => |inner| try stringify(inner, options, out_stream),
            .Float => |inner| try stringify(inner, options, out_stream),
            .NumberString => |inner| try out_stream.writeAll(inner),
            .String => |inner| try stringify(inner, options, out_stream),
            .Array => |inner| try stringify(inner.items, options, out_stream),
            .Object => |inner| {
                try out_stream.writeByte('{');
                var field_output = false;
                var child_options = options;
                if (child_options.whitespace) |*child_whitespace| {
                    child_whitespace.indent_level += 1;
                }
                var it = inner.iterator();
                while (it.next()) |entry| {
                    if (!field_output) {
                        field_output = true;
                    } else {
                        try out_stream.writeByte(',');
                    }
                    if (child_options.whitespace) |child_whitespace| {
                        try child_whitespace.outputIndent(out_stream);
                    }

                    try stringify(entry.key_ptr.*, options, out_stream);
                    try out_stream.writeByte(':');
                    if (child_options.whitespace) |child_whitespace| {
                        if (child_whitespace.separator) {
                            try out_stream.writeByte(' ');
                        }
                    }
                    try stringify(entry.value_ptr.*, child_options, out_stream);
                }
                if (field_output) {
                    if (options.whitespace) |whitespace| {
                        try whitespace.outputIndent(out_stream);
                    }
                }
                try out_stream.writeByte('}');
            },
        }
    }

    pub fn dump(self: Value) void {
        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();

        const stderr = std.io.getStdErr().writer();
        stringify(self, StringifyOptions{ .whitespace = null }, stderr) catch return;
    }
};

/// parse tokens from a stream, returning `false` if they do not decode to `value`
fn parsesTo(comptime T: type, value: T, tokens: *TokenStream, options: ParseOptions) !bool {
    // TODO: should be able to write this function to not require an allocator
    const tmp = try parse(T, tokens, options);
    defer parseFree(T, tmp, options);

    return parsedEqual(tmp, value);
}

/// Returns if a value returned by `parse` is deep-equal to another value
fn parsedEqual(a: anytype, b: @TypeOf(a)) bool {
    switch (@typeInfo(@TypeOf(a))) {
        .Optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return parsedEqual(a.?, b.?);
        },
        .Union => |info| {
            if (info.tag_type) |UnionTag| {
                const tag_a = std.meta.activeTag(a);
                const tag_b = std.meta.activeTag(b);
                if (tag_a != tag_b) return false;

                inline for (info.fields) |field_info| {
                    if (@field(UnionTag, field_info.name) == tag_a) {
                        return parsedEqual(@field(a, field_info.name), @field(b, field_info.name));
                    }
                }
                return false;
            } else {
                unreachable;
            }
        },
        .Array => {
            for (a, 0..) |e, i|
                if (!parsedEqual(e, b[i])) return false;
            return true;
        },
        .Struct => |info| {
            inline for (info.fields) |field_info| {
                if (!parsedEqual(@field(a, field_info.name), @field(b, field_info.name))) return false;
            }
            return true;
        },
        .Pointer => |ptrInfo| switch (ptrInfo.size) {
            .One => return parsedEqual(a.*, b.*),
            .Slice => {
                if (a.len != b.len) return false;
                for (a, 0..) |e, i|
                    if (!parsedEqual(e, b[i])) return false;
                return true;
            },
            .Many, .C => unreachable,
        },
        else => return a == b,
    }
    unreachable;
}

pub const ParseOptions = struct {
    allocator: ?Allocator = null,

    /// Behaviour when a duplicate field is encountered.
    duplicate_field_behavior: enum {
        UseFirst,
        Error,
        UseLast,
    } = .Error,

    /// If false, finding an unknown field returns an error.
    ignore_unknown_fields: bool = false,

    allow_trailing_data: bool = false,
};

const SkipValueError = error{UnexpectedJson5Depth} || TokenStream.Error;

fn skipValue(tokens: *TokenStream) SkipValueError!void {
    const original_depth = tokens.stackUsed();

    // Return an error if no value is found
    _ = try tokens.next();
    if (tokens.stackUsed() < original_depth) return error.UnexpectedJson5Depth;
    if (tokens.stackUsed() == original_depth) return;

    while (try tokens.next()) |_| {
        if (tokens.stackUsed() == original_depth) return;
    }
}

fn ParseInternalError(comptime T: type) type {
    // `inferred_types` is used to avoid infinite recursion for recursive type definitions.
    const inferred_types = [_]type{};
    return ParseInternalErrorImpl(T, &inferred_types);
}

fn ParseInternalErrorImpl(comptime T: type, comptime inferred_types: []const type) type {
    for (inferred_types) |ty| {
        if (T == ty) return error{};
    }

    switch (@typeInfo(T)) {
        .Bool => return error{UnexpectedToken},
        .Float, .ComptimeFloat => return error{UnexpectedToken} || std.fmt.ParseFloatError,
        .Int, .ComptimeInt => {
            return error{ UnexpectedToken, InvalidNumber, Overflow } ||
                std.fmt.ParseIntError || std.fmt.ParseFloatError;
        },
        .Optional => |optionalInfo| {
            return ParseInternalErrorImpl(optionalInfo.child, inferred_types ++ [_]type{T});
        },
        .Enum => return error{ UnexpectedToken, InvalidEnumTag } || std.fmt.ParseIntError ||
            std.meta.IntToEnumError || std.meta.IntToEnumError,
        .Union => |unionInfo| {
            if (unionInfo.tag_type) |_| {
                var errors = error{NoUnionMembersMatched};
                for (unionInfo.fields) |u_field| {
                    errors = errors || ParseInternalErrorImpl(u_field.type, inferred_types ++ [_]type{T});
                }
                return errors;
            } else {
                @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |structInfo| {
            var errors = error{
                DuplicateJSON5Field,
                UnexpectedEndOfJson5,
                UnexpectedToken,
                UnexpectedValue,
                UnknownField,
                MissingField,
            } || SkipValueError || TokenStream.Error;
            for (structInfo.fields) |field| {
                errors = errors || ParseInternalErrorImpl(field.type, inferred_types ++ [_]type{T});
            }
            return errors;
        },
        .Array => |arrayInfo| {
            return error{ UnexpectedEndOfJson5, UnexpectedToken } || TokenStream.Error ||
                UnescapeValidStringError ||
                ParseInternalErrorImpl(arrayInfo.child, inferred_types ++ [_]type{T});
        },
        .Pointer => |ptrInfo| {
            const errors = error{AllocatorRequired} || std.mem.Allocator.Error;
            switch (ptrInfo.size) {
                .One => {
                    return errors || ParseInternalErrorImpl(ptrInfo.child, inferred_types ++ [_]type{T});
                },
                .Slice => {
                    return errors || error{ UnexpectedEndOfJson5, UnexpectedToken } ||
                        ParseInternalErrorImpl(ptrInfo.child, inferred_types ++ [_]type{T}) ||
                        UnescapeValidStringError || TokenStream.Error;
                },
                else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => return error{},
    }
    unreachable;
}

fn parseInternal(
    comptime T: type,
    token: Token,
    tokens: *TokenStream,
    options: ParseOptions,
) ParseInternalError(T)!T {
    switch (@typeInfo(T)) {
        .Bool => {
            return switch (token) {
                .True => true,
                .False => false,
                else => error.UnexpectedToken,
            };
        },
        .Float, .ComptimeFloat => {
            switch (token) {
                .Number => |numberToken| return try std.fmt.parseFloat(T, numberToken.slice(tokens.slice, tokens.i - 1)),
                .String => |stringToken| return try std.fmt.parseFloat(T, stringToken.slice(tokens.slice, tokens.i - 1)),
                else => return error.UnexpectedToken,
            }
        },
        .Int, .ComptimeInt => {
            switch (token) {
                .Number => |numberToken| {
                    if (numberToken.is_integer)
                        return try std.fmt.parseInt(T, numberToken.slice(tokens.slice, tokens.i - 1), 10);
                    const float = try std.fmt.parseFloat(f128, numberToken.slice(tokens.slice, tokens.i - 1));
                    if (@round(float) != float) return error.InvalidNumber;
                    if (float > std.math.maxInt(T) or float < std.math.minInt(T)) return error.Overflow;
                    return @as(T, @intFromFloat(float));
                },
                .String => |stringToken| {
                    return std.fmt.parseInt(T, stringToken.slice(tokens.slice, tokens.i - 1), 10) catch |err| {
                        switch (err) {
                            error.Overflow => return err,
                            error.InvalidCharacter => {
                                const float = try std.fmt.parseFloat(f128, stringToken.slice(tokens.slice, tokens.i - 1));
                                if (@round(float) != float) return error.InvalidNumber;
                                if (float > std.math.maxInt(T) or float < std.math.minInt(T)) return error.Overflow;
                                return @intFromFloat(float);
                            },
                        }
                    };
                },
                else => return error.UnexpectedToken,
            }
        },
        .Optional => |optionalInfo| {
            if (token == .Null) {
                return null;
            } else {
                return try parseInternal(optionalInfo.child, token, tokens, options);
            }
        },
        .Enum => |enumInfo| {
            switch (token) {
                .Number => |numberToken| {
                    if (!numberToken.is_integer) return error.UnexpectedToken;
                    const n = try std.fmt.parseInt(enumInfo.tag_type, numberToken.slice(tokens.slice, tokens.i - 1), 10);
                    return try std.meta.intToEnum(T, n);
                },
                .String => |stringToken| {
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => return std.meta.stringToEnum(T, source_slice) orelse return error.InvalidEnumTag,
                        .Some => {
                            inline for (enumInfo.fields) |field| {
                                if (field.name.len == stringToken.decodedLength() and encodesTo(field.name, source_slice)) {
                                    return @field(T, field.name);
                                }
                            }
                            return error.InvalidEnumTag;
                        },
                    }
                },
                else => return error.UnexpectedToken,
            }
        },
        .Union => |unionInfo| {
            if (unionInfo.tag_type) |_| {
                // try each of the union fields until we find one that matches
                inline for (unionInfo.fields) |u_field| {
                    // take a copy of tokens so we can withhold mutations until success
                    var tokens_copy = tokens.*;
                    if (parseInternal(u_field.type, token, &tokens_copy, options)) |value| {
                        tokens.* = tokens_copy;
                        return @unionInit(T, u_field.name, value);
                    } else |err| {
                        // Bubble up error.OutOfMemory
                        // Parsing some types won't have OutOfMemory in their
                        // error-sets, for the condition to be valid, merge it in.
                        if (@as(@TypeOf(err) || error{OutOfMemory}, err) == error.OutOfMemory) return err;
                        // Bubble up AllocatorRequired, as it indicates missing option
                        if (@as(@TypeOf(err) || error{AllocatorRequired}, err) == error.AllocatorRequired) return err;
                        // otherwise continue through the `inline for`
                    }
                }
                return error.NoUnionMembersMatched;
            } else {
                @compileError("Unable to parse into untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |structInfo| {
            switch (token) {
                .ObjectBegin => {},
                else => return error.UnexpectedToken,
            }
            var r: T = undefined;
            var fields_seen = [_]bool{false} ** structInfo.fields.len;
            errdefer {
                inline for (structInfo.fields, 0..) |field, i| {
                    if (fields_seen[i] and !field.is_comptime) {
                        parseFree(field.type, @field(r, field.name), options);
                    }
                }
            }

            while (true) {
                switch ((try tokens.next()) orelse return error.UnexpectedEndOfJson5) {
                    .ObjectEnd => break,
                    .String => |stringToken| {
                        const key_source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                        var child_options = options;
                        child_options.allow_trailing_data = true;
                        var found = false;
                        inline for (structInfo.fields, 0..) |field, i| {
                            // TODO: using switches here segfault the compiler (#2727?)
                            if ((stringToken.escapes == .None and mem.eql(u8, field.name, key_source_slice)) or (stringToken.escapes == .Some and (field.name.len == stringToken.decodedLength() and encodesTo(field.name, key_source_slice)))) {
                                // if (switch (stringToken.escapes) {
                                //     .None => mem.eql(u8, field.name, key_source_slice),
                                //     .Some => (field.name.len == stringToken.decodedLength() and encodesTo(field.name, key_source_slice)),
                                // }) {
                                if (fields_seen[i]) {
                                    // switch (options.duplicate_field_behavior) {
                                    //     .UseFirst => {},
                                    //     .Error => {},
                                    //     .UseLast => {},
                                    // }
                                    if (options.duplicate_field_behavior == .UseFirst) {
                                        // unconditonally ignore value. for comptime fields, this skips check against default_value
                                        parseFree(field.type, try parse(field.type, tokens, child_options), child_options);
                                        found = true;
                                        break;
                                    } else if (options.duplicate_field_behavior == .Error) {
                                        return error.DuplicateJSON5Field;
                                    } else if (options.duplicate_field_behavior == .UseLast) {
                                        if (!field.is_comptime) {
                                            parseFree(field.type, @field(r, field.name), child_options);
                                        }
                                        fields_seen[i] = false;
                                    }
                                }
                                if (field.is_comptime) {
                                    if (!try parsesTo(field.type, @as(*align(1) const field.type, @ptrCast(field.default_value.?)).*, tokens, child_options)) {
                                        return error.UnexpectedValue;
                                    }
                                } else {
                                    @field(r, field.name) = try parse(field.type, tokens, child_options);
                                }
                                fields_seen[i] = true;
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            if (options.ignore_unknown_fields) {
                                try skipValue(tokens);
                                continue;
                            } else {
                                return error.UnknownField;
                            }
                        }
                    },
                    else => return error.UnexpectedToken,
                }
            }
            inline for (structInfo.fields, 0..) |field, i| {
                if (!fields_seen[i]) {
                    if (field.default_value) |default_ptr| {
                        if (!field.is_comptime) {
                            const default = @as(*align(1) const field.type, @ptrCast(default_ptr)).*;
                            @field(r, field.name) = default;
                        }
                    } else {
                        return error.MissingField;
                    }
                }
            }
            return r;
        },
        .Array => |arrayInfo| {
            switch (token) {
                .ArrayBegin => {
                    var r: T = undefined;
                    var i: usize = 0;
                    var child_options = options;
                    child_options.allow_trailing_data = true;
                    errdefer {
                        // Without the r.len check `r[i]` is not allowed
                        if (r.len > 0) while (true) : (i -= 1) {
                            parseFree(arrayInfo.child, r[i], options);
                            if (i == 0) break;
                        };
                    }
                    while (i < r.len) : (i += 1) {
                        r[i] = try parse(arrayInfo.child, tokens, child_options);
                    }
                    const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson5;
                    switch (tok) {
                        .ArrayEnd => {},
                        else => return error.UnexpectedToken,
                    }
                    return r;
                },
                .String => |stringToken| {
                    if (arrayInfo.child != u8) return error.UnexpectedToken;
                    var r: T = undefined;
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => mem.copy(u8, &r, source_slice),
                        .Some => try unescapeValidString(&r, source_slice),
                    }
                    return r;
                },
                else => return error.UnexpectedToken,
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse return error.AllocatorRequired;
            switch (ptrInfo.size) {
                .One => {
                    const r: T = try allocator.create(ptrInfo.child);
                    errdefer allocator.destroy(r);
                    r.* = try parseInternal(ptrInfo.child, token, tokens, options);
                    return r;
                },
                .Slice => {
                    switch (token) {
                        .ArrayBegin => {
                            var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                            errdefer {
                                while (arraylist.popOrNull()) |v| {
                                    parseFree(ptrInfo.child, v, options);
                                }
                                arraylist.deinit();
                            }

                            while (true) {
                                const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson5;
                                switch (tok) {
                                    .ArrayEnd => break,
                                    else => {},
                                }

                                try arraylist.ensureUnusedCapacity(1);
                                const v = try parseInternal(ptrInfo.child, tok, tokens, options);
                                arraylist.appendAssumeCapacity(v);
                            }

                            if (ptrInfo.sentinel) |some| {
                                const sentinel_value = @as(*align(1) const ptrInfo.child, @ptrCast(some)).*;
                                try arraylist.append(sentinel_value);
                                const output = arraylist.toOwnedSlice();
                                return output[0 .. output.len - 1 :sentinel_value];
                            }

                            return arraylist.toOwnedSlice();
                        },
                        .String => |stringToken| {
                            if (ptrInfo.child != u8) return error.UnexpectedToken;
                            const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                            const len = stringToken.decodedLength();
                            const output = try allocator.alloc(u8, len + @intFromBool(ptrInfo.sentinel != null));
                            errdefer allocator.free(output);
                            switch (stringToken.escapes) {
                                .None => @memcpy(output, source_slice),
                                .Some => try unescapeValidString(output, source_slice),
                            }

                            if (ptrInfo.sentinel) |some| {
                                const char = @as(*const u8, @ptrCast(some)).*;
                                output[len] = char;
                                return output[0..len :char];
                            }

                            return output;
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

pub fn ParseError(comptime T: type) type {
    return ParseInternalError(T) || error{UnexpectedEndOfJson5} || TokenStream.Error;
}

pub fn parse(comptime T: type, tokens: *TokenStream, options: ParseOptions) ParseError(T)!T {
    const token = (try tokens.next()) orelse return error.UnexpectedEndOfJson5;
    const r = try parseInternal(T, token, tokens, options);
    errdefer parseFree(T, r, options);
    if (!options.allow_trailing_data) {
        if ((try tokens.next()) != null) unreachable;
        assert(tokens.i >= tokens.slice.len);
    }
    return r;
}

/// Releases resources created by `parse`.
/// Should be called with the same type and `ParseOptions` that were passed to `parse`
pub fn parseFree(comptime T: type, value: T, options: ParseOptions) void {
    switch (@typeInfo(T)) {
        .Bool, .Float, .ComptimeFloat, .Int, .ComptimeInt, .Enum => {},
        .Optional => {
            if (value) |v| {
                return parseFree(@TypeOf(v), v, options);
            }
        },
        .Union => |unionInfo| {
            if (unionInfo.tag_type) |UnionTagType| {
                inline for (unionInfo.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        parseFree(u_field.type, @field(value, u_field.name), options);
                        break;
                    }
                }
            } else {
                unreachable;
            }
        },
        .Struct => |structInfo| {
            inline for (structInfo.fields) |field| {
                if (!field.is_comptime) {
                    parseFree(field.type, @field(value, field.name), options);
                }
            }
        },
        .Array => |arrayInfo| {
            for (value) |v| {
                parseFree(arrayInfo.child, v, options);
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse unreachable;
            switch (ptrInfo.size) {
                .One => {
                    parseFree(ptrInfo.child, value.*, options);
                    allocator.destroy(value);
                },
                .Slice => {
                    for (value) |v| {
                        parseFree(ptrInfo.child, v, options);
                    }
                    allocator.free(value);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

/// A non-stream JSON5 parser which constructs a tree of Value's.
pub const Parser = struct {
    allocator: Allocator,
    state: State,
    copy_strings: bool,
    // Stores parent nodes and un-combined Values.
    stack: Array,

    const State = enum {
        ObjectKey,
        ObjectValue,
        ArrayValue,
        Simple,
    };

    pub fn init(allocator: Allocator, copy_strings: bool) Parser {
        return Parser{
            .allocator = allocator,
            .state = .Simple,
            .copy_strings = copy_strings,
            .stack = Array.init(allocator),
        };
    }

    pub fn deinit(p: *Parser) void {
        p.stack.deinit();
    }

    pub fn reset(p: *Parser) void {
        p.state = .Simple;
        p.stack.shrinkRetainingCapacity(0);
    }

    pub fn parse(p: *Parser, input: []const u8) !ValueTree {
        var s = TokenStream.init(input);

        var arena = ArenaAllocator.init(p.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        while (try s.next()) |token| {
            try p.transition(allocator, input, s.i - 1, token);
        }

        debug.assert(p.stack.items.len == 1);

        return ValueTree{
            .arena = arena,
            .root = p.stack.items[0],
        };
    }

    // Even though p.allocator exists, we take an explicit allocator so that allocation state
    // can be cleaned up on error correctly during a `parse` on call.
    fn transition(p: *Parser, allocator: Allocator, input: []const u8, i: usize, token: Token) !void {
        switch (p.state) {
            .ObjectKey => switch (token) {
                .ObjectEnd => {
                    if (p.stack.items.len == 1) {
                        return;
                    }

                    var value = p.stack.pop();
                    try p.pushToParent(&value);
                },
                .String => |s| {
                    try p.stack.append(try p.parseString(allocator, s, input, i));
                    p.state = .ObjectValue;
                },
                else => {
                    // The streaming parser would return an error eventually.
                    // To prevent invalid state we return an error now.
                    // TODO make the streaming parser return an error as soon as it encounters an invalid object key
                    return error.InvalidLiteral;
                },
            },
            .ObjectValue => {
                var object = &p.stack.items[p.stack.items.len - 2].Object;
                const key = p.stack.items[p.stack.items.len - 1].String;

                switch (token) {
                    .ObjectBegin => {
                        try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                        p.state = .ObjectKey;
                    },
                    .ArrayBegin => {
                        try p.stack.append(Value{ .Array = Array.init(allocator) });
                        p.state = .ArrayValue;
                    },
                    .String => |s| {
                        try object.put(key, try p.parseString(allocator, s, input, i));
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .Number => |n| {
                        try object.put(key, try p.parseNumber(n, input, i));
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .True => {
                        try object.put(key, Value{ .Bool = true });
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .False => {
                        try object.put(key, Value{ .Bool = false });
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .Null => {
                        try object.put(key, Value.Null);
                        _ = p.stack.pop();
                        p.state = .ObjectKey;
                    },
                    .ObjectEnd, .ArrayEnd => {
                        unreachable;
                    },
                }
            },
            .ArrayValue => {
                var array = &p.stack.items[p.stack.items.len - 1].Array;

                switch (token) {
                    .ArrayEnd => {
                        if (p.stack.items.len == 1) {
                            return;
                        }

                        var value = p.stack.pop();
                        try p.pushToParent(&value);
                    },
                    .ObjectBegin => {
                        try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                        p.state = .ObjectKey;
                    },
                    .ArrayBegin => {
                        try p.stack.append(Value{ .Array = Array.init(allocator) });
                        p.state = .ArrayValue;
                    },
                    .String => |s| {
                        try array.append(try p.parseString(allocator, s, input, i));
                    },
                    .Number => |n| {
                        try array.append(try p.parseNumber(n, input, i));
                    },
                    .True => {
                        try array.append(Value{ .Bool = true });
                    },
                    .False => {
                        try array.append(Value{ .Bool = false });
                    },
                    .Null => {
                        try array.append(Value.Null);
                    },
                    .ObjectEnd => {
                        unreachable;
                    },
                }
            },
            .Simple => switch (token) {
                .ObjectBegin => {
                    try p.stack.append(Value{ .Object = ObjectMap.init(allocator) });
                    p.state = .ObjectKey;
                },
                .ArrayBegin => {
                    try p.stack.append(Value{ .Array = Array.init(allocator) });
                    p.state = .ArrayValue;
                },
                .String => |s| {
                    try p.stack.append(try p.parseString(allocator, s, input, i));
                },
                .Number => |n| {
                    try p.stack.append(try p.parseNumber(n, input, i));
                },
                .True => {
                    try p.stack.append(Value{ .Bool = true });
                },
                .False => {
                    try p.stack.append(Value{ .Bool = false });
                },
                .Null => {
                    try p.stack.append(Value.Null);
                },
                .ObjectEnd, .ArrayEnd => {
                    unreachable;
                },
            },
        }
    }

    fn pushToParent(p: *Parser, value: *const Value) !void {
        switch (p.stack.items[p.stack.items.len - 1]) {
            // Object Parent -> [ ..., object, <key>, value ]
            Value.String => |key| {
                _ = p.stack.pop();

                var object = &p.stack.items[p.stack.items.len - 1].Object;
                try object.put(key, value.*);
                p.state = .ObjectKey;
            },
            // Array Parent -> [ ..., <array>, value ]
            Value.Array => |*array| {
                try array.append(value.*);
                p.state = .ArrayValue;
            },
            else => {
                unreachable;
            },
        }
    }

    fn parseString(p: *Parser, allocator: Allocator, s: std.meta.TagPayload(Token, Token.String), input: []const u8, i: usize) !Value {
        const slice = s.slice(input, i);
        switch (s.escapes) {
            .None => return Value{ .String = if (p.copy_strings) try allocator.dupe(u8, slice) else slice },
            .Some => {
                const output = try allocator.alloc(u8, s.decodedLength());
                errdefer allocator.free(output);
                try unescapeValidString(output, slice);
                return Value{ .String = output };
            },
        }
    }

    fn parseNumber(p: *Parser, n: std.meta.TagPayload(Token, Token.Number), input: []const u8, i: usize) !Value {
        _ = p;
        return if (n.is_integer)
            Value{
                .Integer = std.fmt.parseInt(i64, n.slice(input, i), 10) catch |e| switch (e) {
                    error.Overflow => return Value{ .NumberString = n.slice(input, i) },
                    error.InvalidCharacter => |err| return err,
                },
            }
        else
            Value{ .Float = try std.fmt.parseFloat(f64, n.slice(input, i)) };
    }
};

pub const UnescapeValidStringError = error{InvalidUnicodeHexSymbol};

/// Unescape a JSON5 string
/// Only to be used on strings already validated by the parser
/// (note the unreachable statements and lack of bounds checking)
pub fn unescapeValidString(output: []u8, input: []const u8) UnescapeValidStringError!void {
    var inIndex: usize = 0;
    var outIndex: usize = 0;

    while (inIndex < input.len) {
        if (input[inIndex] != '\\') {
            // not an escape sequence
            output[outIndex] = input[inIndex];
            inIndex += 1;
            outIndex += 1;
        } else if (input[inIndex + 1] != 'u') {
            // a simple escape sequence
            output[outIndex] = @as(u8, switch (input[inIndex + 1]) {
                '\\' => '\\',
                '/' => '/',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'f' => 12,
                'b' => 8,
                '"' => '"',
                '\'' => '\'',
                '\n' => '\n',
                else => unreachable,
            });
            inIndex += 2;
            outIndex += 1;
        } else {
            // a unicode escape sequence
            const firstCodeUnit = std.fmt.parseInt(u16, input[inIndex + 2 .. inIndex + 6], 16) catch unreachable;

            // guess optimistically that it's not a surrogate pair
            if (std.unicode.utf8Encode(firstCodeUnit, output[outIndex..])) |byteCount| {
                outIndex += byteCount;
                inIndex += 6;
            } else |err| {
                // it might be a surrogate pair
                if (err != error.Utf8CannotEncodeSurrogateHalf) {
                    return error.InvalidUnicodeHexSymbol;
                }
                // check if a second code unit is present
                if (inIndex + 7 >= input.len or input[inIndex + 6] != '\\' or input[inIndex + 7] != 'u') {
                    return error.InvalidUnicodeHexSymbol;
                }

                const secondCodeUnit = std.fmt.parseInt(u16, input[inIndex + 8 .. inIndex + 12], 16) catch unreachable;

                const utf16le_seq = [2]u16{
                    mem.nativeToLittle(u16, firstCodeUnit),
                    mem.nativeToLittle(u16, secondCodeUnit),
                };
                if (std.unicode.utf16LeToUtf8(output[outIndex..], &utf16le_seq)) |byteCount| {
                    outIndex += byteCount;
                    inIndex += 12;
                } else |_| {
                    return error.InvalidUnicodeHexSymbol;
                }
            }
        }
    }
    assert(outIndex == output.len);
}

pub const StringifyOptions = struct {
    pub const Whitespace = struct {
        /// How many indentation levels deep are we?
        indent_level: usize = 0,

        /// What character(s) should be used for indentation?
        indent: union(enum) {
            Space: u8,
            Tab: void,
            None: void,
        } = .{ .Space = 4 },

        /// After a colon, should whitespace be inserted?
        separator: bool = true,

        pub fn outputIndent(
            whitespace: @This(),
            out_stream: anytype,
        ) @TypeOf(out_stream).Error!void {
            var char: u8 = undefined;
            var n_chars: usize = undefined;
            switch (whitespace.indent) {
                .Space => |n_spaces| {
                    char = ' ';
                    n_chars = n_spaces;
                },
                .Tab => {
                    char = '\t';
                    n_chars = 1;
                },
                .None => return,
            }
            try out_stream.writeByte('\n');
            n_chars *= whitespace.indent_level;
            try out_stream.writeByteNTimes(char, n_chars);
        }
    };

    /// Controls the whitespace emitted
    whitespace: ?StringifyOptions.Whitespace = null,

    /// Should optional fields with null value be written?
    emit_null_optional_fields: bool = true,

    string: StringOptions = StringOptions{ .String = .{} },

    /// Should []u8 be serialised as a string? or an array?
    pub const StringOptions = union(enum) {
        Array,
        String: StringOutputOptions,

        /// String output options
        const StringOutputOptions = struct {
            /// Should '/' be escaped in strings?
            escape_solidus: bool = false,

            /// Should unicode characters be escaped in strings?
            escape_unicode: bool = false,
        };
    };
};

fn outputUnicodeEscape(
    codepoint: u21,
    out_stream: anytype,
) !void {
    if (codepoint <= 0xFFFF) {
        // If the character is in the Basic Multilingual Plane (U+0000 through U+FFFF),
        // then it may be represented as a six-character sequence: a reverse solidus, followed
        // by the lowercase letter u, followed by four hexadecimal digits that encode the character's code point.
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(codepoint, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
    } else {
        assert(codepoint <= 0x10FFFF);
        // To escape an extended character that is not in the Basic Multilingual Plane,
        // the character is represented as a 12-character sequence, encoding the UTF-16 surrogate pair.
        const high = @as(u16, @intCast((codepoint - 0x10000) >> 10)) + 0xD800;
        const low = @as(u16, @intCast(codepoint & 0x3FF)) + 0xDC00;
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(high, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
        try out_stream.writeAll("\\u");
        try std.fmt.formatIntValue(low, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, out_stream);
    }
}

/// Write `string` to `writer` as a JSON5 encoded string.
pub fn encodeJson5String(string: []const u8, options: StringifyOptions, writer: anytype) !void {
    try writer.writeByte('\"');
    try encodeJson5StringChars(string, options, writer);
    try writer.writeByte('\"');
}

/// Write `chars` to `writer` as JSON5 encoded string characters.
pub fn encodeJson5StringChars(chars: []const u8, options: StringifyOptions, writer: anytype) !void {
    var i: usize = 0;
    while (i < chars.len) : (i += 1) {
        switch (chars[i]) {
            // normal ascii character
            0x20...0x21, 0x23...0x2E, 0x30...0x5B, 0x5D...0x7F => |c| try writer.writeByte(c),
            // only 2 characters that *must* be escaped
            '\\' => {
                try writer.writeAll("\\\\");
            },
            '\"' => try writer.writeAll("\\\""),
            // solidus is optional to escape
            '/' => {
                if (options.string.String.escape_solidus) {
                    try writer.writeAll("\\/");
                } else {
                    try writer.writeByte('/');
                }
            },
            // control characters with short escapes
            // TODO: option to switch between unicode and 'short' forms?
            0x8 => try writer.writeAll("\\b"),
            0xC => try writer.writeAll("\\f"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                const ulen = std.unicode.utf8ByteSequenceLength(chars[i]) catch unreachable;
                // control characters (only things left with 1 byte length) should always be printed as unicode escapes
                if (ulen == 1 or options.string.String.escape_unicode) {
                    const codepoint = std.unicode.utf8Decode(chars[i .. i + ulen]) catch unreachable;
                    try outputUnicodeEscape(codepoint, writer);
                } else {
                    try writer.writeAll(chars[i .. i + ulen]);
                }
                i += ulen - 1;
            },
        }
    }
}

pub fn stringify(
    value: anytype,
    options: StringifyOptions,
    out_stream: anytype,
) @TypeOf(out_stream).Error!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => {
            return std.fmt.format(out_stream, "{e}", .{value});
        },
        .Int, .ComptimeInt => {
            return std.fmt.formatIntValue(value, "", std.fmt.FormatOptions{}, out_stream);
        },
        .Bool => {
            return out_stream.writeAll(if (value) "true" else "false");
        },
        .Null => {
            return out_stream.writeAll("null");
        },
        .Optional => {
            if (value) |payload| {
                return try stringify(payload, options, out_stream);
            } else {
                return try stringify(null, options, out_stream);
            }
        },
        .Enum => {
            if (@hasDecl(T, "json5Stringify")) {
                return value.json5Stringify(options, out_stream);
            }

            @compileError("Unable to stringify enum '" ++ @typeName(T) ++ "'");
        },
        .Union => {
            if (@hasDecl(T, "json5Stringify")) {
                return value.json5Stringify(options, out_stream);
            }

            const info = @typeInfo(T).Union;
            if (info.tag_type) |UnionTagType| {
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        return try stringify(@field(value, u_field.name), options, out_stream);
                    }
                }
            } else {
                @compileError("Unable to stringify untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |S| {
            if (@hasDecl(T, "json5Stringify")) {
                return value.json5Stringify(options, out_stream);
            }

            try out_stream.writeByte('{');
            var field_output = false;
            var child_options = options;
            if (child_options.whitespace) |*child_whitespace| {
                child_whitespace.indent_level += 1;
            }
            inline for (S.fields) |Field| {
                // don't include void fields
                if (Field.type == void) continue;

                var emit_field = true;

                // don't include optional fields that are null when emit_null_optional_fields is set to false
                if (@typeInfo(Field.type) == .Optional) {
                    if (options.emit_null_optional_fields == false) {
                        if (@field(value, Field.name) == null) {
                            emit_field = false;
                        }
                    }
                }

                if (emit_field) {
                    if (!field_output) {
                        field_output = true;
                    } else {
                        try out_stream.writeByte(',');
                    }
                    if (child_options.whitespace) |child_whitespace| {
                        try child_whitespace.outputIndent(out_stream);
                    }
                    try encodeJson5String(Field.name, options, out_stream);
                    try out_stream.writeByte(':');
                    if (child_options.whitespace) |child_whitespace| {
                        if (child_whitespace.separator) {
                            try out_stream.writeByte(' ');
                        }
                    }
                    try stringify(@field(value, Field.name), child_options, out_stream);
                }
            }
            if (field_output) {
                if (options.whitespace) |whitespace| {
                    try whitespace.outputIndent(out_stream);
                }
            }
            try out_stream.writeByte('}');
            return;
        },
        .ErrorSet => return stringify(@as([]const u8, @errorName(value)), options, out_stream),
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => {
                    const Slice = []const std.meta.Elem(ptr_info.child);
                    return stringify(@as(Slice, value), options, out_stream);
                },
                else => {
                    // TODO: avoid loops?
                    return stringify(value.*, options, out_stream);
                },
            },
            // TODO: .Many when there is a sentinel (waiting for https://github.com/ziglang/zig/pull/3972)
            .Slice => {
                if (ptr_info.child == u8 and options.string == .String and std.unicode.utf8ValidateSlice(value)) {
                    try encodeJson5String(value, options, out_stream);
                    return;
                }

                try out_stream.writeByte('[');
                var child_options = options;
                if (child_options.whitespace) |*whitespace| {
                    whitespace.indent_level += 1;
                }
                for (value, 0..) |x, i| {
                    if (i != 0) {
                        try out_stream.writeByte(',');
                    }
                    if (child_options.whitespace) |child_whitespace| {
                        try child_whitespace.outputIndent(out_stream);
                    }
                    try stringify(x, child_options, out_stream);
                }
                if (value.len != 0) {
                    if (options.whitespace) |whitespace| {
                        try whitespace.outputIndent(out_stream);
                    }
                }
                try out_stream.writeByte(']');
                return;
            },
            else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
        },
        .Array => return stringify(&value, options, out_stream),
        .Vector => |info| {
            const array: [info.len]info.child = value;
            return stringify(&array, options, out_stream);
        },
        else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

// Same as `stringify` but accepts an Allocator and stores result in dynamically allocated memory instead of using a Writer.
// Caller owns returned memory.
pub fn stringifyAlloc(allocator: std.mem.Allocator, value: anytype, options: StringifyOptions) ![]const u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();
    try stringify(value, options, list.writer());
    return list.toOwnedSlice();
}

/// ------------ WriteStream Code ---------------
const WSState = enum {
    Complete,
    Value,
    ArrayStart,
    Array,
    ObjectStart,
    Object,
};

pub const Whitespace = struct {
    /// How many indentation levels deep are we?
    indent_level: usize = 0,
    /// What character(s) should be used for indentation?
    indent: union(enum) {
        space: u8,
        tab: void,
        none: void,
    } = .{ .space = 4 },
    /// After a colon, should whitespace be inserted?
    separator: bool = true,
    pub fn outputIndent(
        whitespace: @This(),
        out_stream: anytype,
    ) @TypeOf(out_stream).Error!void {
        var char: u8 = undefined;
        var n_chars: usize = undefined;
        switch (whitespace.indent) {
            .space => |n_spaces| {
                char = ' ';
                n_chars = n_spaces;
            },
            .tab => {
                char = '\t';
                n_chars = 1;
            },
            .none => return,
        }
        try out_stream.writeByte('\n');
        n_chars *= whitespace.indent_level;
        try out_stream.writeByteNTimes(char, n_chars);
    }
};
/// Controls the whitespace emitted
whitespace: Whitespace = .{ .indent = .none, .separator = false },

/// Writes JSON ([RFC8259](https://tools.ietf.org/html/rfc8259)) formatted data
/// to a stream. `max_depth` is a comptime-known upper bound on the nesting depth.
/// TODO A future iteration of this API will allow passing `null` for this value,
/// and disable safety checks in release builds.
pub fn WriteStream(comptime OutStream: type, comptime max_depth: usize) type {
    return struct {
        const Self = @This();

        pub const Stream = OutStream;

        whitespace: StringifyOptions.Whitespace = StringifyOptions.Whitespace{
            .indent_level = 0,
            .indent = .{ .Space = 1 },
        },

        stream: OutStream,
        state_index: usize,
        state: [max_depth]WSState,

        pub fn init(stream: OutStream) Self {
            var self = Self{
                .stream = stream,
                .state_index = 1,
                .state = undefined,
            };
            self.state[0] = .Complete;
            self.state[1] = .Value;
            return self;
        }

        pub fn beginArray(self: *Self) !void {
            assert(self.state[self.state_index] == WSState.Value); // need to call arrayElem or objectField
            try self.stream.writeByte('[');
            self.state[self.state_index] = WSState.ArrayStart;
            self.whitespace.indent_level += 1;
        }

        pub fn beginObject(self: *Self) !void {
            assert(self.state[self.state_index] == WSState.Value); // need to call arrayElem or objectField
            try self.stream.writeByte('{');
            self.state[self.state_index] = WSState.ObjectStart;
            self.whitespace.indent_level += 1;
        }

        pub fn arrayElem(self: *Self) !void {
            const state = self.state[self.state_index];
            switch (state) {
                .Complete => unreachable,
                .Value => unreachable,
                .ObjectStart => unreachable,
                .Object => unreachable,
                .Array, .ArrayStart => {
                    if (state == .Array) {
                        try self.stream.writeByte(',');
                    }
                    self.state[self.state_index] = .Array;
                    self.pushState(.Value);
                    try self.indent();
                },
            }
        }

        pub fn objectField(self: *Self, name: []const u8) !void {
            const state = self.state[self.state_index];
            switch (state) {
                .Complete => unreachable,
                .Value => unreachable,
                .ArrayStart => unreachable,
                .Array => unreachable,
                .Object, .ObjectStart => {
                    if (state == .Object) {
                        try self.stream.writeByte(',');
                    }
                    self.state[self.state_index] = .Object;
                    self.pushState(.Value);
                    try self.indent();
                    try self.writeEscapedString(name);
                    try self.stream.writeByte(':');
                    if (self.whitespace.separator) {
                        try self.stream.writeByte(' ');
                    }
                },
            }
        }

        pub fn endArray(self: *Self) !void {
            switch (self.state[self.state_index]) {
                .Complete => unreachable,
                .Value => unreachable,
                .ObjectStart => unreachable,
                .Object => unreachable,
                .ArrayStart => {
                    self.whitespace.indent_level -= 1;
                    try self.stream.writeByte(']');
                    self.popState();
                },
                .Array => {
                    self.whitespace.indent_level -= 1;
                    try self.indent();
                    self.popState();
                    try self.stream.writeByte(']');
                },
            }
        }

        pub fn endObject(self: *Self) !void {
            switch (self.state[self.state_index]) {
                .Complete => unreachable,
                .Value => unreachable,
                .ArrayStart => unreachable,
                .Array => unreachable,
                .ObjectStart => {
                    self.whitespace.indent_level -= 1;
                    try self.stream.writeByte('}');
                    self.popState();
                },
                .Object => {
                    self.whitespace.indent_level -= 1;
                    try self.indent();
                    self.popState();
                    try self.stream.writeByte('}');
                },
            }
        }

        pub fn emitNull(self: *Self) !void {
            assert(self.state[self.state_index] == WSState.Value);
            try self.stringify(null);
            self.popState();
        }

        pub fn emitBool(self: *Self, value: bool) !void {
            assert(self.state[self.state_index] == WSState.Value);
            try self.stringify(value);
            self.popState();
        }

        pub fn emitNumber(
            self: *Self,
            /// An integer, float, or `std.math.BigInt`. Emitted as a bare number if it fits losslessly
            /// in a IEEE 754 double float, otherwise emitted as a string to the full precision.
            value: anytype,
        ) !void {
            assert(self.state[self.state_index] == WSState.Value);
            switch (@typeInfo(@TypeOf(value))) {
                .Int => |info| {
                    if (info.bits < 53) {
                        try self.stream.print("{}", .{value});
                        self.popState();
                        return;
                    }
                    if (value < 4503599627370496 and (info.signedness == .unsigned or value > -4503599627370496)) {
                        try self.stream.print("{}", .{value});
                        self.popState();
                        return;
                    }
                },
                .ComptimeInt => {
                    return self.emitNumber(@as(std.math.IntFittingRange(value, value), value));
                },
                .Float, .ComptimeFloat => if (@as(f64, @floatCast(value)) == value) {
                    try self.stream.print("{}", .{@as(f64, @floatCast(value))});
                    self.popState();
                    return;
                },
                else => {},
            }
            try self.stream.print("\"{}\"", .{value});
            self.popState();
        }

        pub fn emitString(self: *Self, string: []const u8) !void {
            assert(self.state[self.state_index] == WSState.Value);
            try self.writeEscapedString(string);
            self.popState();
        }

        fn writeEscapedString(self: *Self, string: []const u8) !void {
            assert(std.unicode.utf8ValidateSlice(string));
            try self.stringify(string);
        }

        /// Writes the complete json into the output stream
        pub fn emitJson(self: *Self, json: Value) Stream.Error!void {
            assert(self.state[self.state_index] == WSState.Value);
            try self.stringify(json);
            self.popState();
        }

        fn indent(self: *Self) !void {
            assert(self.state_index >= 1);
            try self.whitespace.outputIndent(self.stream);
        }

        fn pushState(self: *Self, state: WSState) void {
            self.state_index += 1;
            self.state[self.state_index] = state;
        }

        fn popState(self: *Self) void {
            self.state_index -= 1;
        }

        fn stringify(self: *Self, value: anytype) !void {
            try Json5.stringify(value, StringifyOptions{
                .whitespace = self.whitespace,
            }, self.stream);
        }
    };
}

fn getStringifiedJSON(allocator: Allocator, json5Value: Value) ![]const u8 {
    var arr = std.ArrayList(u8).init(allocator);
    try json5Value.json5Stringify(.{}, arr.writer());
    return arr.items;
}

fn jsonValueEqual(allocator: Allocator, a: Value, b: Value) !bool {
    return switch (a) {
        .Null => switch (b) {
            .Null => true,
            else => false,
        },
        .Bool => |a_b| switch (b) {
            .Bool => |b_b| a_b or b_b,
            else => false,
        },
        .Integer => |a_i| switch (b) {
            .Integer => |b_i| a_i == b_i or std.mem.eql(
                u8,
                try getStringifiedJSON(allocator, a),
                try getStringifiedJSON(allocator, b),
            ),
            else => false,
        },
        .Float => |a_f| switch (b) {
            .Float => |b_f| a_f == b_f or std.mem.eql(
                u8,
                try getStringifiedJSON(allocator, a),
                try getStringifiedJSON(allocator, b),
            ),
            else => false,
        },
        .NumberString => |a_ns| switch (b) {
            .NumberString => |b_ns| std.mem.eql(u8, a_ns, b_ns),
            else => false,
        },
        .String => |a_s| switch (b) {
            .String => |b_s| {
                return std.mem.eql(u8, a_s, b_s);
            },
            else => false,
        },
        .Array => |a_a| switch (b) {
            .Array => |b_a| {
                if (a_a.items.len != b_a.items.len) return false;
                for (a_a.items, 0..) |a_item, i| {
                    const b_item = b_a.items[i];
                    if (!(try jsonValueEqual(allocator, a_item, b_item))) return false;
                }
                return true;
            },
            else => false,
        },
        .Object => |a_o| switch (b) {
            .Object => |b_o| {
                if (a_o.count() != b_o.count()) return false;
                const b_o_keys = b_o.keys();
                const a_o_keys = a_o.keys();
                for (a_o_keys) |a_o_k| {
                    var b_o_k: ?[]const u8 = null;
                    for (b_o_keys) |v| {
                        if (std.mem.eql(u8, v, a_o_k)) {
                            b_o_k = v;
                            break;
                        }
                    }
                    if (b_o_k == null) return false;

                    const a_o_v = a_o.get(a_o_k).?;
                    const b_o_v = b_o.get(b_o_k.?).?;

                    if (!try jsonValueEqual(allocator, a_o_v, b_o_v)) return false;
                }
                return true;
            },
            else => false,
        },
    };
}

pub fn json5Equal(allocator: Allocator, a: Value, b: Value) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    const val = try jsonValueEqual(arena.allocator(), a, b);
    arena.deinit();
    return val;
}

pub fn writeStream(
    out_stream: anytype,
    comptime max_depth: usize,
) WriteStream(@TypeOf(out_stream), max_depth) {
    return WriteStream(@TypeOf(out_stream), max_depth).init(out_stream);
}

fn getJsonObject(allocator: std.mem.Allocator) !Value {
    var value = Value{ .Object = ObjectMap.init(allocator) };
    try value.Object.put("one", Value{ .Integer = @as(i64, @intCast(1)) });
    try value.Object.put("two", Value{ .Float = 2.0 });
    return value;
}

const identifierStartTable = [256]bool{
    // ASCII
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, true,  false, false, false, // $
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, true, true, true, true, true, true, true, // A, B, C, D, E, F, G
    true, true, true, true, true, true, true, true, // H, I, J, K, L, M, N, O
    true, true, true, true, true, true, true, true, // P, Q, R, S, T, U, V, W
    true, true, true, false, false, false, false, true, // X, Y, Z, _
    false, true, true, true, true, true, true, true, // a, b, c, d, e, f, g
    true, true, true, true, true, true, true, true, // h, i, j, k, l, m, n, o
    true, true, true, true, true, true, true, true, // p, q, r, s, t, u, v, w
    true,  true,  true,  false, false, false, false, false, // x, y, z

    // non-ASCII
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
};

pub const identifierTable = [256]bool{
    // ASCII
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, true,  false, false, false, // $
    false, false, false, false, false, false, false, false,
    true, true, true, true, true, true, true, true, // 0, 1, 2, 3, 4, 5, 6, 7
    true, true, false, false, false, false, false, false, // 8, 9
    false, true, true, true, true, true, true, true, // A, B, C, D, E, F, G
    true, true, true, true, true, true, true, true, // H, I, J, K, L, M, N, O
    true, true, true, true, true, true, true, true, // P, Q, R, S, T, U, V, W
    true, true, true, false, false, false, false, true, // X, Y, Z, _
    false, true, true, true, true, true, true, true, // a, b, c, d, e, f, g
    true, true, true, true, true, true, true, true, // h, i, j, k, l, m, n, o
    true, true, true, true, true, true, true, true, // p, q, r, s, t, u, v, w
    true,  true,  true,  false, false, false, false, false, // x, y, z

    // non-ASCII
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,

    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
    false, false, false, false, false, false, false, false,
};
