// This is an implementation of the Entity Component System pattern,
// which is a core of the game.

const std = @import("std");

/// The id of an entity.
pub const Entity = u32;

/// The container of the components of the type `C`.
/// The type `C` should have a function `fn deinit(component: *C) void` for invalidation the component.
///
/// The components are stored in the array, and can be got
/// for an entity for O(1) thanks for additional indexes inside.
pub fn ArraySet(comptime C: anytype) type {
    return struct {
        const Self = @This();
        // all components have to be stored in the array for perf. boost.
        components: std.ArrayList(C),
        entity_index: std.AutoHashMap(Entity, u8),
        index_entity: std.AutoHashMap(u8, Entity),

        /// Creates instances of the inner storages.
        pub fn init(alloc: std.mem.Allocator) Self {
            return .{
                .components = std.ArrayList(C).init(alloc),
                .entity_index = std.AutoHashMap(Entity, u8).init(alloc),
                .index_entity = std.AutoHashMap(u8, Entity).init(alloc),
            };
        }

        /// Deinits the inner storages and components.
        pub fn deinit(self: *Self) void {
            for (self.components.items) |*component| {
                component.deinit();
            }
            self.components.deinit();
            self.entity_index.deinit();
            self.index_entity.deinit();
        }

        pub fn clear(self: *Self) !void {
            for (self.components.items) |*component| {
                component.deinit();
            }
            try self.components.resize(0);
            self.entity_index.clearAndFree();
            self.index_entity.clearAndFree();
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
                self.components.items[idx].deinit();
                self.components.items[idx] = component;
            } else {
                try self.entity_index.put(entity, @intCast(self.components.items.len));
                try self.index_entity.put(@intCast(self.components.items.len), entity);
                try self.components.append(component);
            }
        }

        /// Deletes the components of the entity from the all inner stores,
        /// if they was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, entity: Entity) !void {
            if (self.entity_index.get(entity)) |idx| {
                _ = self.index_entity.remove(idx);
                _ = self.entity_index.remove(entity);

                // deinit the component before removing
                self.components.items[idx].deinit();

                const last_idx: u8 = @intCast(self.components.items.len - 1);
                if (idx == last_idx) {
                    _ = self.components.pop();
                } else {
                    const last_entity = self.index_entity.get(last_idx).?;
                    self.components.items[idx] = self.components.pop();
                    try self.entity_index.put(last_entity, idx);
                    try self.index_entity.put(idx, last_entity);
                }
            }
        }
    };
}

/// Generated in compile time structure,
/// which has  fields for every type from the `ComponentsUnion` union.
fn ComponentsMap(comptime ComponentsUnion: anytype) type {
    const type_info = @typeInfo(ComponentsUnion);
    switch (type_info) {
        .Union => {},
        else => @compileError(
            std.fmt.comptimePrint("Components have to be grouped to an union, but found {any}", .{type_info}),
        ),
    }
    const union_fields = type_info.Union.fields;
    if (union_fields.len == 0) {
        @compileError("At least one component should exist");
    }

    // every type in the union should be unique:
    var tmp: [union_fields.len]std.builtin.Type.UnionField = undefined;
    @memcpy(&tmp, union_fields);
    std.sort.pdq(std.builtin.Type.UnionField, &tmp, {}, compareUnionFields);
    for (0..tmp.len - 1) |i| {
        if (tmp[i].type == tmp[i + 1].type) {
            @compileError(std.fmt.comptimePrint(
                "Both fields `{s}` and `{s}` have the same type `{any}` in the `{s}`, but components should have unique types.",
                .{ tmp[i].name, tmp[i + 1].name, tmp[i].type, @typeName(ComponentsUnion) },
            ));
        }
    }

    var struct_fields: [union_fields.len]std.builtin.Type.StructField = undefined;
    for (union_fields, 0..) |f, i| {
        struct_fields[i] = .{
            .name = @typeName(f.type),
            .type = ArraySet(f.type),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = struct_fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

/// Compares types of the two union fields. Used to check uniqueness of the components
fn compareUnionFields(_: void, a: std.builtin.Type.UnionField, b: std.builtin.Type.UnionField) bool {
    return a.type != b.type;
}

/// The manager of the components.
pub fn ComponentsManager(comptime ComponentsUnion: type) type {
    return struct {
        const Self = @This();

        const InnerState = struct {
            alloc: std.mem.Allocator,
            components_map: ComponentsMap(ComponentsUnion),
        };

        inner_state: *InnerState,

        /// Initializes every field of the inner components map.
        /// The allocator is used for allocate inner storages.
        pub fn init(alloc: std.mem.Allocator) !Self {
            const inner_state = try alloc.create(InnerState);
            inner_state.alloc = alloc;
            inner_state.components_map = undefined;

            const Arrays = @typeInfo(ComponentsMap(ComponentsUnion)).Struct.fields;
            inline for (Arrays) |array| {
                @field(inner_state.components_map, array.name) =
                    array.type.init(alloc);
            }

            return .{ .inner_state = inner_state };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(ComponentsMap(ComponentsUnion)).Struct.fields) |field| {
                @field(self.inner_state.components_map, field.name).deinit();
            }
            self.inner_state.alloc.destroy(self.inner_state);
        }

        pub fn getAll(self: Self, comptime C: type) []C {
            return self.arrayOf(C).components.items;
        }

        pub fn arrayOf(self: Self, comptime C: type) ArraySet(C) {
            return @field(self.inner_state.components_map, @typeName(C));
        }

        pub fn removeAll(self: *Self, comptime C: type) !void {
            try @field(self.inner_state.components_map, @typeName(C)).clear();
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn getForEntity(self: *const Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.inner_state.components_map, @typeName(C)).getForEntity(entity);
        }

        /// Adds the component of the type `C` to the entity, or replace existed.
        pub fn setToEntity(self: *Self, entity: Entity, component: anytype) !void {
            const C = @TypeOf(component);
            try @field(self.inner_state.components_map, @typeName(C)).setToEntity(entity, component);
        }

        /// Removes the component of the type `C` from the entity if it was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, entity: Entity, comptime C: type) !void {
            try @field(self.inner_state.components_map, @typeName(C)).removeFromEntity(entity);
        }

        /// Removes all components from all stores which belong to the entity.
        pub fn removeAllForEntity(self: *Self, entity: Entity) !void {
            inline for (@typeInfo(ComponentsMap(ComponentsUnion)).Struct.fields) |field| {
                try @field(self.inner_state.components_map, field.name).removeFromEntity(entity);
            }
        }
    };
}

test "ComponentsManager: Add/Get/Remove component" {
    const TestComponent = struct {
        const Self = @This();
        state: std.ArrayList(u8),
        fn init(value: u8) !Self {
            var instance: Self = .{ .state = try std.ArrayList(u8).initCapacity(std.testing.allocator, 1) };
            try instance.state.append(value);
            return instance;
        }

        fn deinit(self: *Self) void {
            self.state.deinit();
        }
    };

    const TestComponents = union {
        foo: TestComponent,
    };

    var manager = try ComponentsManager(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    // should return the component, which was added before
    const entity = 1;
    try manager.setToEntity(entity, try TestComponent.init(123));
    var component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqual(123, component.?.state.items[0]);

    // should return null for entity, without requested component
    component = manager.getForEntity(entity + 1, TestComponent);
    try std.testing.expectEqual(null, component);

    // should return null for removed component
    try manager.removeFromEntity(entity, TestComponent);
    component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqual(null, component);

    // and finally, no memory leak should happened
}

/// The manager of the entities and their components.
pub const EntitiesManager = struct {
    const Self = @This();

    /// The iterator over entities. It should be used to get
    /// entities from this manager.
    pub const EntitiesIterator = std.AutoHashMap(Entity, void).KeyIterator;

    next_entity: Entity,
    entities: std.AutoHashMap(Entity, void),

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{
            .next_entity = 0,
            .entities = std.AutoHashMap(Entity, void).init(alloc),
        };
    }

    /// Removes cleans up the inner entities storage.
    pub fn deinit(self: *Self) void {
        self.entities.deinit();
    }

    /// Generates an unique id for the new entity, puts it to the inner storage,
    /// and then returns as the result. The id is unique for whole life circle of
    /// this manager.
    pub fn newEntity(self: *Self) !Entity {
        const entity = self.next_entity;
        self.next_entity += 1;
        try self.entities.put(entity, {});
        return entity;
    }

    /// Removes all components of the entity and it self from the inner storage.
    pub fn removeEntity(self: *Self, entity: Entity) void {
        _ = self.entities.remove(entity);
    }

    pub inline fn iterator(self: *const Self) EntitiesIterator {
        return self.entities.keyIterator();
    }
};

pub fn ComponentsQuery(comptime ComponentsUnion: type) type {
    return struct {
        const Self = @This();
        entities: *const EntitiesManager,
        components: *const ComponentsManager(ComponentsUnion),

        pub fn Query2(comptime Cmp1: type, Cmp2: type) type {
            return struct {
                components: *const ComponentsManager(ComponentsUnion),
                entities_itr: EntitiesManager.EntitiesIterator,

                pub fn next(query: *@This()) ?struct { Entity, *Cmp1, *Cmp2 } {
                    while (query.entities_itr.next()) |entity_ptr| {
                        const entity = entity_ptr.*;
                        if (query.components.getForEntity(entity, Cmp1)) |c1| {
                            if (query.components.getForEntity(entity, Cmp2)) |c2| {
                                return .{ entity, c1, c2 };
                            }
                        }
                    }
                    return null;
                }
            };
        }

        pub fn get2(self: *const Self, comptime Cmp1: type, Cmp2: type) Query2(Cmp1, Cmp2) {
            return .{ .components = self.components, .entities_itr = self.entities.iterator() };
        }

        pub fn Query3(comptime Cmp1: type, Cmp2: type, Cmp3: type) type {
            return struct {
                components: *const ComponentsManager(ComponentsUnion),
                entities_itr: EntitiesManager.EntitiesIterator,

                pub fn next(query: *@This()) ?struct { Entity, *Cmp1, *Cmp2, *Cmp3 } {
                    while (query.entities_itr.next()) |entity_ptr| {
                        const entity = entity_ptr.*;
                        if (query.components.getForEntity(entity, Cmp1)) |c1| {
                            if (query.components.getForEntity(entity, Cmp2)) |c2| {
                                if (query.components.getForEntity(entity, Cmp3)) |c3| {
                                    return .{ entity, c1, c2, c3 };
                                }
                            }
                        }
                    }
                    return null;
                }
            };
        }

        pub fn get3(self: *const Self, comptime Cmp1: type, Cmp2: type, Cmp3: type) Query3(Cmp1, Cmp2, Cmp3) {
            return .{ .components = self.components, .entities_itr = self.entities.iterator() };
        }
    };
}
