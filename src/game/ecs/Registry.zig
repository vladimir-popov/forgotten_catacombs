const std = @import("std");
const Type = std.builtin.Type;
const Entity = @import("Entity.zig");
const ArraySet = @import("ArraySet.zig").ArraySet;

const log = std.log.scoped(.registry);

/// The manager of the entities and components.
pub fn Registry(comptime ComponentsStruct: type) type {
    return struct {
        const Self = @This();

        pub const ComponentsMap = @import("ComponentsMap.zig").ComponentsMap(ComponentsStruct);
        pub const TypeTag = std.meta.FieldEnum(ComponentsStruct);

        arena: std.heap.ArenaAllocator,
        // segmentation fault happens if use it as a structure
        components_map: *ComponentsMap,
        /// An id for a next new entity
        next_entity: Entity,

        /// Initializes every field of the inner components map.
        /// The allocator is used for allocate inner storages.
        pub fn init(alloc: std.mem.Allocator) !Self {
            // const arena = try alloc.create(std.heap.ArenaAllocator);
            var arena = std.heap.ArenaAllocator.init(alloc);
            var cm = try arena.allocator().create(ComponentsMap);

            const ArraySets = @typeInfo(ComponentsMap).@"struct".fields;
            inline for (ArraySets) |array_set| {
                @field(cm, array_set.name) = array_set.type.empty;
            }
            return .{
                .arena = arena,
                .next_entity = .{ .id = 1 },
                .components_map = cm,
            };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.arena.allocator();
        }

        /// Adds the component of the type `C` to the entity, or replace existed.
        pub fn set(self: *Self, entity: Entity, component: anytype) !void {
            const C = @TypeOf(component);
            try @field(self.components_map, @typeName(C)).setToEntity(self.allocator(), entity, component);
        }

        /// Sets all defined fields from the `ComponentsStruct` to the entity as the components.
        ///
        /// **Note:** for every component should be used the same allocator that was used to initialize
        /// this EntityManager. That allocator will be used to deinit components on removing.
        pub fn setComponentsToEntity(self: *Self, entity: Entity, components: ComponentsStruct) !void {
            inline for (@typeInfo(ComponentsStruct).@"struct".fields) |field| {
                if (@field(components, field.name)) |component| {
                    try self.set(entity, component);
                }
            }
        }

        pub fn newEntity(self: *Self) Entity {
            const entity = self.next_entity;
            self.next_entity.id += 1;
            return entity;
        }

        pub fn addNewEntity(self: *Self, components: ComponentsStruct) !Entity {
            const entity = self.newEntity();
            try self.setComponentsToEntity(entity, components);
            log.debug("New entity {d} added: {any}", .{ entity.id, components });
            return entity;
        }

        pub fn has(self: Self, entity: Entity, comptime C: type) bool {
            return @field(self.components_map, @typeName(C)).existsForEntity(entity);
        }

        /// Returns true if the entity has at least one component.
        pub fn contains(self: *Self, entity: Entity) bool {
            inline for (@typeInfo(ComponentsMap).@"struct".fields) |field| {
                if (@field(self.components_map, field.name).existsForEntity(entity)) {
                    return true;
                }
            }
            return false;
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn get(self: Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.components_map, @typeName(C)).getForEntity(entity);
        }

        pub fn getUnsafe(self: Self, entity: Entity, comptime C: type) *C {
            return get(self, entity, C) orelse unreachable;
        }

        pub fn getOrSet(self: *Self, entity: Entity, comptime C: type, default: C) !*C {
            return try @field(self.components_map, @typeName(C)).getOrSetForEntity(self.allocator(), entity, default);
        }

        pub fn get2(self: Self, entity: Entity, comptime C1: type, comptime C2: type) ?struct { *C1, *C2 } {
            if (self.get(entity, C1)) |c1| {
                if (self.get(entity, C2)) |c2| {
                    return .{ c1, c2 };
                }
            }
            return null;
        }

        pub fn get3(
            self: *const Self,
            entity: Entity,
            comptime C1: type,
            comptime C2: type,
            comptime C3: type,
        ) ?struct { *C1, *C2, *C3 } {
            if (self.get(entity, C1)) |c1| {
                if (self.get(entity, C2)) |c2| {
                    if (self.get(entity, C3)) |c3| {
                        return .{ c1, c2, c3 };
                    }
                }
            }
            return null;
        }

        pub fn get4(
            self: Self,
            entity: Entity,
            comptime C1: type,
            comptime C2: type,
            comptime C3: type,
            comptime C4: type,
        ) ?struct { *C1, *C2, *C3, *C4 } {
            if (self.get(entity, C1)) |c1| {
                if (self.get(entity, C2)) |c2| {
                    if (self.get(entity, C3)) |c3| {
                        if (self.get(entity, C4)) |c4| {
                            return .{ c1, c2, c3, c4 };
                        }
                    }
                }
            }
            return null;
        }

        pub fn query(self: Self, comptime C: type) ArraySet(C).Iterator {
            return @field(self.components_map, @typeName(C)).iterator();
        }

        pub fn Iterator2(comptime C1: type, C2: type) type {
            return struct {
                manager: Self,
                main_iterator: ArraySet(C1).Iterator,

                pub fn next(self: *@This()) ?struct { Entity, *C1, *C2 } {
                    while (self.main_iterator.next()) |tuple| {
                        const entity: Entity = tuple[0];
                        const c1: *C1 = tuple[1];
                        if (self.manager.get(entity, C2)) |c2|
                            return .{ entity, c1, c2 };
                    }
                    return null;
                }
            };
        }

        pub fn query2(self: Self, comptime C1: type, C2: type) Iterator2(C1, C2) {
            return .{
                .manager = self,
                .main_iterator = @field(self.components_map, @typeName(C1)).iterator(),
            };
        }

        pub fn Iterator3(comptime C1: type, C2: type, C3: type) type {
            return struct {
                manager: Self,
                main_iterator: ArraySet(C1).Iterator,

                pub fn next(self: *@This()) ?struct { Entity, *C1, *C2, *C3 } {
                    while (self.main_iterator.next()) |tuple| {
                        const entity: Entity = tuple[0];
                        const c1: *C1 = tuple[1];
                        if (self.manager.get2(entity, C2, C3)) |cc|
                            return .{ entity, c1, cc[0], cc[1] };
                    }
                    return null;
                }
            };
        }

        pub fn query3(self: Self, comptime C1: type, C2: type, C3: type) Iterator3(C1, C2, C3) {
            return .{
                .manager = self,
                .main_iterator = @field(self.components_map, @typeName(C1)).iterator(),
            };
        }

        pub fn Iterator4(comptime C1: type, C2: type, C3: type, C4: type) type {
            return struct {
                manager: Self,
                main_iterator: ArraySet(C1).Iterator,

                pub fn next(self: *@This()) ?struct { Entity, *C1, *C2, *C3, *C4 } {
                    while (self.main_iterator.next()) |tuple| {
                        const entity: Entity = tuple[0];
                        const c1: *C1 = tuple[1];
                        if (self.manager.get3(entity, C2, C3, C4)) |cc|
                            return .{ entity, c1, cc[0], cc[1], cc[2] };
                    }
                    return null;
                }
            };
        }

        pub fn query4(self: Self, comptime C1: type, C2: type, C3: type, C4: type) Iterator4(C1, C2, C3, C4) {
            return .{
                .manager = self,
                .main_iterator = @field(self.components_map, @typeName(C1)).iterator(),
            };
        }

        /// Removes the component of the type `C` from the entity if it was added before, or does nothing.
        pub fn remove(self: *Self, entity: Entity, comptime C: type) !void {
            try @field(self.components_map, @typeName(C)).removeFromEntity(self.allocator(), entity);
        }

        /// Removes all components of the type `C` from all entities.
        pub fn removeAll(self: *Self, comptime C: type) void {
            @field(self.components_map, @typeName(C)).clear();
        }

        /// Removes all components from all stores which belong to the entity.
        pub fn removeEntity(self: *Self, entity: Entity) !void {
            inline for (@typeInfo(ComponentsMap).@"struct".fields) |field| {
                try @field(self.components_map, field.name).removeFromEntity(self.allocator(), entity);
            }
        }

        /// Takes all components for the entity and set them to the appropriate
        /// fields of the `ComponentsStruct`.
        pub fn entityToStruct(self: Self, entity: Entity) !ComponentsStruct {
            var has_at_least_one_component: bool = false;
            var structure: ComponentsStruct = undefined;
            inline for (@typeInfo(ComponentsStruct).@"struct".fields) |field| {
                const field_type = @typeInfo(field.type);
                const type_name = @typeName(field_type.optional.child);
                if (@field(self.components_map, type_name).getForEntity(entity)) |cmp_ptr| {
                    @field(structure, field.name) = cmp_ptr.*;
                    has_at_least_one_component = true;
                } else {
                    @field(structure, field.name) = null;
                }
            }
            if (!has_at_least_one_component)
                log.warn("entityToStruct: Entity {d} doesn't have any component.", .{entity.id});

            return structure;
        }
    };
}

test "Add/Get/Remove component" {
    var deinited: bool = false;
    const TestComponent = struct {
        const Self = @This();
        state: std.ArrayList(u8),
        deinited: *bool,

        fn init(value: u8, ptr: *bool) !Self {
            var instance: Self = .{
                .state = try std.ArrayList(u8).initCapacity(std.testing.allocator, 1),
                .deinited = ptr,
            };
            try instance.state.append(value);
            return instance;
        }

        pub fn deinit(self: *Self, _: std.mem.Allocator) void {
            self.state.deinit();
            self.deinited.* = true;
        }
    };

    const TestComponents = struct {
        foo: ?TestComponent,
    };

    var manager = try Registry(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    // should return the component, which was added before
    const entity = manager.newEntity();
    try manager.set(entity, try TestComponent.init(123, &deinited));

    var component = manager.get(entity, TestComponent);
    try std.testing.expectEqual(123, component.?.state.items[0]);

    // should return null for entity, without requested component
    component = manager.get(.{ .id = entity.id + 1 }, TestComponent);
    try std.testing.expectEqual(null, component);

    // should return null for removed component
    try manager.remove(entity, TestComponent);
    component = manager.get(entity, TestComponent);
    try std.testing.expectEqual(null, component);

    // should deinit component on removing it
    try std.testing.expect(deinited);

    // and finally, no memory leak should happened
}

test "deinit entity on update" {
    // given:
    var deinited_1: bool = false;
    var deinited_2: bool = false;
    const Cmp = struct {
        value: u8,
        deinited: *bool,
        pub fn deinit(self: *@This(), _: std.mem.Allocator) void {
            self.deinited.* = true;
        }
    };
    const Components = struct { cmp: ?Cmp };

    var registry = try Registry(Components).init(std.testing.allocator);
    defer registry.deinit();

    const entity = registry.newEntity();
    try registry.set(entity, Cmp{ .value = 1, .deinited = &deinited_1 });

    // when:
    try registry.set(entity, Cmp{ .value = 2, .deinited = &deinited_2 });

    // then:
    try std.testing.expectEqual(2, registry.getUnsafe(entity, Cmp).value);
    try std.testing.expectEqual(true, deinited_1);
}

test "get entity as a struct" {
    // given:
    const Foo = struct { value: u8 };
    const Bar = struct { value: bool };

    const TestComponents = struct { foo: ?Foo, bar: ?Bar };

    var registry = try Registry(TestComponents).init(std.testing.allocator);
    defer registry.deinit();

    const entity = registry.newEntity();
    try registry.set(entity, Bar{ .value = true });

    // when:
    const structure = try registry.entityToStruct(entity);

    // then:
    try std.testing.expectEqual(null, structure.foo);
    try std.testing.expectEqualDeep(Bar{ .value = true }, structure.bar.?);
}

test "set all components as a struct to the entity" {
    // given:
    const Foo = struct { value: u8 };
    const Bar = struct { value: bool };

    const TestComponents = struct { foo: ?Foo = null, bar: ?Bar = null };

    var registry = try Registry(TestComponents).init(std.testing.allocator);
    defer registry.deinit();

    const entity = try registry.addNewEntity(.{ .foo = .{ .value = 42 } });

    // when:
    const foo = registry.get(entity, Foo);
    const bar = registry.get(entity, Bar);

    // then:
    try std.testing.expectEqualDeep(Foo{ .value = 42 }, foo.?.*);
    try std.testing.expectEqual(null, bar);
}
