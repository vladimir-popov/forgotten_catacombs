const std = @import("std");
const Type = std.builtin.Type;
const Entity = @import("Entity.zig");
const ArraySet = @import("ArraySet.zig").ArraySet;
const EntitiesManager = @import("EntitiesManager.zig").EntitiesManager;

pub fn ComponentsIterator(comptime Components: type) type {
    return struct {
        const Self = @This();

        entities: []const Entity,
        manager: EntitiesManager(Components),

        pub fn Iterator1(comptime C: type) type {
            return struct {
                parent: *const Self,
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *C } {
                    while (self.idx < self.parent.entities.len) {
                        const entity = self.parent.entities[self.idx];
                        self.idx += 1;
                        if (self.parent.manager.get(entity, C)) |cmp| {
                            return .{ entity, cmp };
                        }
                    }
                    return null;
                }
            };
        }

        pub fn of(self: *const Self, comptime C: type) Iterator1(C) {
            return .{ .parent = self };
        }

        pub fn Iterator2(comptime C1: type, C2: type) type {
            return struct {
                parent: *const Self,
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *C1, *C2 } {
                    while (self.idx < self.parent.entities.len) {
                        const entity = self.parent.entities[self.idx];
                        self.idx += 1;
                        if (self.parent.manager.get2(entity, C1, C2)) |res| {
                            return .{ entity, res[0], res[1] };
                        }
                    }
                    return null;
                }
            };
        }

        pub fn of2(self: *const Self, comptime C1: type, C2: type) Iterator2(C1, C2) {
            return .{ .parent = self };
        }

        pub fn Iterator3(comptime C1: type, C2: type, C3: type) type {
            return struct {
                parent: *const Self,
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *C1, *C2, *C3 } {
                    while (self.idx < self.parent.entities.len) {
                        const entity = self.parent.entities[self.idx];
                        self.idx += 1;
                        if (self.parent.manager.get2(entity, C1, C2, C3)) |res| {
                            return .{ entity, res[0], res[1], res[2] };
                        }
                    }
                    return null;
                }
            };
        }

        pub fn of3(self: *const Self, comptime C1: type, C2: type, C3: type) Iterator3(C1, C2, C3) {
            return .{ .parent = self };
        }
    };
}
