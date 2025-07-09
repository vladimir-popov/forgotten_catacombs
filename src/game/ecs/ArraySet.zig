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

        components: std.ArrayListUnmanaged(C),
        entity_index: std.AutoHashMapUnmanaged(Entity, usize),
        index_entity: std.AutoHashMapUnmanaged(usize, Entity),

        /// An instance of this ArraySet with empty inner storages.
        pub const empty = Self{
            .components = .empty,
            .entity_index = .empty,
            .index_entity = .empty,
        };

        /// Deinits the inner storages and components.
        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents();
            self.components.deinit(alloc);
            self.entity_index.deinit(alloc);
            self.index_entity.deinit(alloc);
        }

        pub fn clearRetainingCapacity(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents(alloc);
            self.components.clearRetainingCapacity();
            self.entity_index.clearRetainingCapacity();
            self.index_entity.clearRetainingCapacity();
        }

        pub fn clear(self: *Self, alloc: std.mem.Allocator) void {
            self.deinitComponents(alloc);
            self.components.clearAndFree(alloc);
            self.entity_index.clearAndFree(alloc);
            self.index_entity.clearAndFree(alloc);
        }

        pub const Iterator = struct {
            parent: *const Self,
            idx: usize = 0,

            pub fn next(self: *Iterator) ?struct { Entity, *C } {
                if (self.idx < self.parent.components.items.len) {
                    if (self.parent.index_entity.get(self.idx)) |entity| {
                        self.idx += 1;
                        return .{ entity, &self.parent.components.items[self.idx - 1] };
                    }
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
                return &self.components.items[idx];
            } else {
                return null;
            }
        }

        /// Adds the component of the type `C` for the entity, or replaces existed.
        pub fn setToEntity(self: *Self, alloc: std.mem.Allocator, entity: Entity, component: C) !void {
            if (self.entity_index.get(entity)) |idx| {
                self.deinitComponent(idx);
                self.components.items[idx] = component;
            } else {
                try self.entity_index.put(alloc, entity, self.components.items.len);
                try self.index_entity.put(alloc, self.components.items.len, entity);
                try self.components.append(alloc, component);
            }
        }

        /// Deletes the components of the entity from the all inner stores
        /// if they was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, alloc: std.mem.Allocator, entity: Entity) !void {
            if (self.entity_index.get(entity)) |idx| {
                _ = self.index_entity.remove(idx);
                _ = self.entity_index.remove(entity);

                const last_idx: u8 = @intCast(self.components.items.len - 1);
                self.deinitComponent(idx);
                if (idx == last_idx) {
                    _ = self.components.pop();
                } else {
                    const last_entity = self.index_entity.get(last_idx).?;
                    self.components.items[idx] = self.components.items[self.components.items.len - 1];
                    self.components.items.len -= 1;
                    try self.entity_index.put(alloc, last_entity, idx);
                    try self.index_entity.put(alloc, idx, last_entity);
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
                self.components.items[idx].deinit();
            }
        }
    };
}
