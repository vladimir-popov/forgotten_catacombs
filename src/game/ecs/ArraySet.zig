const std = @import("std");
const Type = std.builtin.Type;
const Entity = @import("Entity.zig");

/// The container of the components of the type `C`.
/// The life circle of the components should be equal to the life circle of this container.
/// When the component is removing (directly, or when this container is cleaning), the `deinit`
/// method is invoking (if such method is defined).
///
/// The components are stored in the array, and can be taken
/// for an entity for O(1) thanks for additional indexes inside.
pub fn ArraySet(comptime C: anytype) type {
    return struct {
        const Self = @This();

        components: std.ArrayListUnmanaged(struct { Entity, C }),
        entity_index: std.AutoHashMapUnmanaged(Entity, usize),

        /// An instance of this ArraySet with empty inner storages.
        pub const empty = Self{
            .components = .empty,
            .entity_index = .empty,
        };

        /// Deinits the inner storages and components.
        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents();
            self.components.deinit(alloc);
            self.entity_index.deinit(alloc);
        }

        pub fn clearRetainingCapacity(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents(alloc);
            self.components.clearRetainingCapacity();
            self.entity_index.clearRetainingCapacity();
        }

        pub fn clear(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents(alloc);
            self.components.clearAndFree(alloc);
            self.entity_index.clearAndFree(alloc);
        }

        pub const Iterator = struct {
            parent: *const Self,
            idx: usize = 0,

            pub fn next(self: *Iterator) ?struct { Entity, *C } {
                if (self.idx < self.parent.components.items.len) {
                    defer self.idx += 1;
                    return .{ self.parent.components.items[self.idx][0], &self.parent.components.items[self.idx][1] };
                }
                return null;
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return .{ .parent = self };
        }

        /// Returns the pointer to the component for the entity if it was added before, or null.
        pub fn getForEntity(self: Self, entity: Entity) ?*C {
            if (self.entity_index.get(entity)) |idx| {
                return &self.components.items[idx][1];
            } else {
                return null;
            }
        }

        /// Adds the component of the type `C` for the entity, or replaces existed.
        pub fn setToEntity(self: *Self, alloc: std.mem.Allocator, entity: Entity, component: C) !void {
            if (self.entity_index.get(entity)) |idx| {
                self.deinitComponent(idx);
                self.components.items[idx] = .{ entity, component };
            } else {
                try self.entity_index.put(alloc, entity, self.components.items.len);
                try self.components.append(alloc, .{ entity, component });
            }
        }

        /// Deletes the components of the entity from the all inner stores
        /// if they was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, alloc: std.mem.Allocator, entity: Entity) !void {
            if (self.entity_index.get(entity)) |idx| {
                _ = self.entity_index.remove(entity);

                const last_idx: u8 = @intCast(self.components.items.len - 1);
                self.deinitComponent(idx);
                if (idx == last_idx) {
                    _ = self.components.pop();
                } else {
                    const last_tuple = self.components.items[last_idx];
                    self.components.items[idx] =
                        .{ last_tuple[0], last_tuple[1] };
                    self.components.items.len -= 1;
                    try self.entity_index.put(alloc, last_tuple[0], idx);
                }
            }
        }

        fn deinitComponents(self: *Self) void {
            for (0..self.components.items.len) |idx| {
                self.deinitComponent(idx);
            }
        }

        inline fn deinitComponent(self: *Self, idx: usize) void {
            if (@hasDecl(C, "deinit")) {
                self.components.items[idx][1].deinit();
            }
        }
    };
}
