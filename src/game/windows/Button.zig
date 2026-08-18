text: []const u8,
has_alternatives: bool,

pub const close: @This() = .{ .text = "Close", .has_alternatives = false };
pub const choose: @This() = .{ .text = "Choose", .has_alternatives = false };
pub const choose_with_alternatives: @This() = .{ .text = "Choose", .has_alternatives = true };
