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

        alloc: std.mem.Allocator,
        components: std.ArrayListUnmanaged(C),
        entity_index: std.AutoHashMapUnmanaged(Entity, u8),
        index_entity: std.AutoHashMapUnmanaged(u8, Entity),

        /// Creates instances of the inner storages.
        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .alloc = alloc,
                .components = std.ArrayListUnmanaged(C){},
                .entity_index = std.AutoHashMapUnmanaged(Entity, u8){},
                .index_entity = std.AutoHashMapUnmanaged(u8, Entity){},
            };
        }

        /// Deinits the inner storages and components.
        pub fn deinit(self: *Self) void {
            self.deinitComponents();
            self.components.deinit(self.alloc);
            self.entity_index.deinit(self.alloc);
            self.index_entity.deinit(self.alloc);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.deinitComponents();
            self.components.clearRetainingCapacity();
            self.entity_index.clearRetainingCapacity();
            self.index_entity.clearRetainingCapacity();
        }

        pub fn clear(self: *Self) void {
            self.deinitComponents();
            self.components.clearAndFree(self.alloc);
            self.entity_index.clearAndFree(self.alloc);
            self.index_entity.clearAndFree(self.alloc);
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
        pub fn setToEntity(self: *Self, entity: Entity, component: C) !void {
            if (self.entity_index.get(entity)) |idx| {
                self.components.items[idx] = component;
            } else {
                try self.entity_index.put(self.alloc, entity, @intCast(self.components.items.len));
                try self.index_entity.put(self.alloc, @intCast(self.components.items.len), entity);
                try self.components.append(self.alloc, component);
            }
        }

        /// Deletes the components of the entity from the all inner stores
        /// if they was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, entity: Entity) !void {
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
                    try self.entity_index.put(self.alloc, last_entity, idx);
                    try self.index_entity.put(self.alloc, idx, last_entity);
                }
            }
        }

        fn deinitComponents(self: *Self) void {
            for (0..self.components.items.len) |idx| {
                self.deinitComponent(idx);
            }
        }

        inline fn deinitComponent(self: *Self, idx: usize) void {
            if (std.meta.hasFn(C, "deinit")) {
                C.deinit(&self.components.items[idx]);
            }
        }
    };
}
