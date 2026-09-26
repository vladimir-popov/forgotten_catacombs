const std = @import("std");

/// A fixed-size heterogeneous list whose element types are known at comptime.
///
/// The list owns the values stored in `items`. As with other Zig containers,
/// resources owned by an individual element still have to be released by that
/// element's own `deinit` method, when it has one.
pub fn HList(comptime Types: anytype) type {
    validate(Types);

    // Accept both a tuple value (`.{ u8, bool }`) and a tuple type
    // (`@Tuple(&.{ u8, bool })`).
    const Items = if (@TypeOf(Types) == type) Types else @Tuple(&Types);

    return struct {
        pub const Fields = @typeInfo(Items).@"struct".fields;

        const Self = @This();

        pub const capacity = Fields.len;

        items: Items = undefined,
        len: usize = 0,

        pub const empty: Self = .{};

        pub fn append(self: *Self, value: anytype) ?*@TypeOf(value) {
            if (self.len >= capacity) return null;

            inline for (Fields, 0..) |field, i| {
                const T = field.type;
                if (self.len == i) {
                    if (comptime T != @TypeOf(value)) return null;

                    self.items[i] = value;
                    self.len += 1;
                    return &self.items[i];
                }
            }

            return null;
        }

        /// Returns a mutable pointer when the last value has type `T`.
        pub fn getLast(self: *Self, comptime T: type) ?*T {
            if (self.len == 0) return null;
            return self.get(T, self.len - 1);
        }

        /// Removes the last value. Returns `false` when the list is empty.
        /// Resources owned by the value must be released before this call.
        pub fn removeLast(self: *Self) bool {
            if (self.len == 0) return false;

            const last = self.len - 1;
            inline for (0..capacity) |i| {
                if (last == i) {
                    self.items[i] = undefined;
                    self.len = last;
                    return true;
                }
            }

            unreachable;
        }

        /// Returns a mutable pointer when `T` is the type stored at `idx`.
        pub inline fn get(self: *Self, comptime T: type, idx: usize) ?*T {
            if (idx >= self.len) return null;

            inline for (Fields, 0..) |field, i| {
                const Element = field.type;
                if (idx == i) {
                    if (comptime T != Element) return null;
                    return &self.items[i];
                }
            }

            return null;
        }
    };
}

fn validate(comptime Types: anytype) void {
    const Tuple = if (@TypeOf(Types) == type) Types else @TypeOf(Types);
    const info = @typeInfo(Tuple);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError(std.fmt.comptimePrint(
            "HList expects a tuple of types, for example .{{ u8, []const u8 }}. But got {any}",
            .{info},
        ));
    }

    if (@TypeOf(Types) != type) {
        inline for (Types) |element_type| {
            if (@TypeOf(element_type) != type) {
                @compileError("every HList tuple element must be a type");
            }
        }
    }
}

test HList {
    const Position = struct { x: i32, y: i32 };
    const Name = struct { value: []const u8 };
    const List = HList(.{ Position, Name, bool });

    var list = List.empty;

    const position = list.append(Position{ .x = 10, .y = 20 }).?;
    const name = list.append(Name{ .value = "hero" }).?;
    const active = list.append(true).?;

    position.x = 42;
    active.* = false;

    const runtime_idx: usize = 0;
    try std.testing.expectEqual(42, list.get(Position, runtime_idx).?.x);
    try std.testing.expectEqualStrings("hero", name.value);
    try std.testing.expect(!list.get(bool, 2).?.*);
    try std.testing.expect(list.get(Name, runtime_idx) == null);
    try std.testing.expect(list.get(Position, List.capacity) == null);
    try std.testing.expectEqual(3, List.capacity);
    try std.testing.expectEqual(3, list.len);
    try std.testing.expect(list.append(false) == null);

    try std.testing.expect(list.getLast(Name) == null);
    try std.testing.expectEqual(false, list.getLast(bool).?.*);
    try std.testing.expect(list.removeLast());
    try std.testing.expectEqualStrings("hero", list.getLast(Name).?.value);
    try std.testing.expect(list.removeLast());
    try std.testing.expectEqual(42, list.getLast(Position).?.x);
    try std.testing.expect(list.removeLast());
    try std.testing.expectEqual(0, list.len);
    try std.testing.expect(list.getLast(Position) == null);
    try std.testing.expect(!list.removeLast());
}

test "HList rejects a value whose type does not match the next slot" {
    const List = HList(.{ u8, bool });
    var list = List.empty;

    try std.testing.expect(list.append(true) == null);
    try std.testing.expectEqual(0, list.len);
    try std.testing.expect(list.append(@as(u8, 7)) != null);
    try std.testing.expect(list.append(false) != null);
}
