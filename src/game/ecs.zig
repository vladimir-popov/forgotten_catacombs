const std = @import("std");
const Type = std.builtin.Type;

/// The id of an entity.
pub const Entity = u32;

pub const EntitiesProvider = struct {
    next_entity: Entity = 0,

    /// Generates an unique id for the new entity.
    pub fn newEntity(self: *EntitiesProvider) Entity {
        const entity = self.next_entity;
        self.next_entity += 1;
        return entity;
    }
};

/// The container of the components of the type `C`.
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
            self.components.deinit();
            self.entity_index.deinit();
            self.index_entity.deinit();
        }

        pub fn clear(self: *Self) !void {
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
                self.components.items[idx] = component;
            } else {
                try self.entity_index.put(entity, @intCast(self.components.items.len));
                try self.index_entity.put(@intCast(self.components.items.len), entity);
                try self.components.append(component);
            }
        }

        /// Deletes the components of the entity from the all inner stores
        /// if they was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, entity: Entity) !void {
            if (self.entity_index.get(entity)) |idx| {
                _ = self.index_entity.remove(idx);
                _ = self.entity_index.remove(entity);

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
/// which has ArraySet for every type from the `ComponentsStruct`.
fn ComponentsMap(comptime ComponentsStruct: anytype) type {
    const type_info = @typeInfo(ComponentsStruct);
    switch (type_info) {
        .Struct => {},
        else => @compileError(
            std.fmt.comptimePrint(
                "Wrong `{s}` type. The components have to be grouped to the struct with optional types, but found `{any}`",
                .{ @typeName(ComponentsStruct), type_info },
            ),
        ),
    }
    const struct_fields = type_info.Struct.fields;
    if (struct_fields.len == 0) {
        @compileError("At least one component should exist");
    }

    var components: [struct_fields.len]Type.StructField = undefined;
    // every field inside the ComponentsStruct should be optional, but we need their child types
    for (struct_fields, 0..) |field, i| {
        switch (@typeInfo(field.type)) {
            .Optional => |opt| {
                components[i] = .{
                    .name = @typeName(opt.child),
                    .type = ArraySet(opt.child),
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = 0,
                };
            },
            else => {
                @compileError(std.fmt.comptimePrint(
                    "All fields in the `{s}` should be optional, but the `{s}: {any}` was found.",
                    .{ @typeName(ComponentsStruct), field.name, field.type },
                ));
            },
        }
    }
    // every type in the struct should be unique:
    std.sort.pdq(Type.StructField, &components, {}, compareTypes);
    for (0..components.len - 1) |i| {
        if (components[i].type == components[i + 1].type) {
            @compileError(std.fmt.comptimePrint(
                "The `{s}` has fields with the same type `{s}`, but all types of the components must be unique",
                .{ @typeName(ComponentsStruct), components[i].name },
            ));
        }
    }

    return @Type(.{
        .Struct = .{
            .layout = .auto,
            .fields = components[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

/// Compares types of the two fields of the ComponentsStruct.
/// Used to check uniqueness of the components.
fn compareTypes(_: void, a: Type.StructField, b: Type.StructField) bool {
    return a.type != b.type;
}

/// The manager of the components.
pub fn ComponentsManager(comptime ComponentsStruct: type) type {
    return struct {
        const Self = @This();

        const InnerState = struct {
            alloc: std.mem.Allocator,
            components_map: ComponentsMap(ComponentsStruct),
        };

        inner_state: *InnerState,

        /// Initializes every field of the inner components map.
        /// The allocator is used for allocate inner storages.
        pub fn init(alloc: std.mem.Allocator) !Self {
            const inner_state = try alloc.create(InnerState);
            inner_state.alloc = alloc;
            inner_state.components_map = undefined;

            const Arrays = @typeInfo(ComponentsMap(ComponentsStruct)).Struct.fields;
            inline for (Arrays) |array| {
                @field(inner_state.components_map, array.name) =
                    array.type.init(alloc);
            }

            return .{ .inner_state = inner_state };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(ComponentsMap(ComponentsStruct)).Struct.fields) |field| {
                @field(self.inner_state.components_map, field.name).deinit();
            }
            self.inner_state.alloc.destroy(self.inner_state);
        }

        pub fn getAll(self: Self, comptime C: type) []C {
            return self.arrayOf(C).components.items;
        }

        pub fn arrayOf(self: Self, comptime C: type) *ArraySet(C) {
            return &@field(self.inner_state.components_map, @typeName(C));
        }

        pub fn removeAll(self: *Self, comptime C: type) !void {
            try @field(self.inner_state.components_map, @typeName(C)).clear();
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn getForEntity(self: *const Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.inner_state.components_map, @typeName(C)).getForEntity(entity);
        }

        pub fn getForEntityUnsafe(self: *const Self, entity: Entity, comptime C: type) *C {
            return getForEntity(self, entity, C) orelse unreachable;
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
            inline for (@typeInfo(ComponentsMap(ComponentsStruct)).Struct.fields) |field| {
                try @field(self.inner_state.components_map, field.name).removeFromEntity(entity);
            }
        }

        pub fn entityToStruct(self: Self, entity: Entity) !ComponentsStruct {
            var structure: ComponentsStruct = undefined;
            inline for (@typeInfo(ComponentsStruct).Struct.fields) |field| {
                const field_type = @typeInfo(field.type);
                const type_name = @typeName(field_type.Optional.child);
                if (@field(self.inner_state.components_map, type_name).getForEntity(entity)) |cmp_ptr|
                    @field(structure, field.name) = cmp_ptr.*
                else
                    @field(structure, field.name) = null;
            }
            return structure;
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

    const TestComponents = struct {
        foo: ?TestComponent,
    };

    var manager = try ComponentsManager(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    // should return the component, which was added before
    const entity = 1;
    var component_instance = try TestComponent.init(123);
    defer component_instance.deinit();

    try manager.setToEntity(entity, component_instance);
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

test "ComponentsManager: get entity as struct" {
    // given:
    const Foo = struct { value: u8 };
    const Bar = struct { value: bool };

    const TestComponents = struct { foo: ?Foo, bar: ?Bar };

    const entity = 1;

    var manager = try ComponentsManager(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    try manager.setToEntity(entity, Bar{ .value = true });

    // when:
    const structure = try manager.entityToStruct(entity);

    // then:
    try std.testing.expectEqual(null, structure.foo);
    try std.testing.expectEqualDeep(Bar{ .value = true }, structure.bar.?);
}

pub fn ComponentsQuery(comptime ComponentsUnion: type) type {
    return struct {
        const Self = @This();

        entities: std.ArrayList(Entity),
        components_manager: ComponentsManager(ComponentsUnion),

        pub fn Query1(comptime Cmp: type) type {
            return struct {
                components: *ArraySet(Cmp),
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *Cmp } {
                    while (self.idx < self.components.components.items.len) {
                        defer self.idx += 1;
                        if (self.components.index_entity.get(self.idx)) |entity|
                            return .{ entity, &self.components.components.items[self.idx] };
                    }
                    return null;
                }
            };
        }

        pub fn get(self: *const Self, comptime Cmp: type) Query1(Cmp) {
            return .{ .components = self.components_manager.arrayOf(Cmp) };
        }

        pub fn Query2(comptime Cmp1: type, Cmp2: type) type {
            return struct {
                entities: []const Entity,
                components: ComponentsManager(ComponentsUnion),
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *Cmp1, *Cmp2 } {
                    while (self.idx < self.entities.len) {
                        const entity = self.entities[self.idx];
                        self.idx += 1;
                        if (self.components.getForEntity(entity, Cmp1)) |c1| {
                            if (self.components.getForEntity(entity, Cmp2)) |c2| {
                                return .{ entity, c1, c2 };
                            }
                        }
                    }
                    return null;
                }
            };
        }

        pub fn get2(self: *const Self, comptime Cmp1: type, Cmp2: type) Query2(Cmp1, Cmp2) {
            return .{ .components = self.components_manager, .entities = self.entities.items };
        }

        pub fn Query3(comptime Cmp1: type, Cmp2: type, Cmp3: type) type {
            return struct {
                entities: []const Entity,
                components: ComponentsManager(ComponentsUnion),
                idx: u8 = 0,

                pub fn next(self: *@This()) ?struct { Entity, *Cmp1, *Cmp2, *Cmp3 } {
                    while (self.idx < self.entities.len) {
                        const entity = self.entities[self.idx];
                        self.idx += 1;
                        if (self.components.getForEntity(entity, Cmp1)) |c1| {
                            if (self.components.getForEntity(entity, Cmp2)) |c2| {
                                if (self.components.getForEntity(entity, Cmp3)) |c3| {
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
            return .{ .components = self.components_manager, .entities = self.entities.items };
        }
    };
}
