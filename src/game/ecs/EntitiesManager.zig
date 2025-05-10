const std = @import("std");
const Type = std.builtin.Type;
const Entity = @import("Entity.zig");
const ArraySet = @import("ArraySet.zig").ArraySet;
const ComponentsMap = @import("ComponentsMap.zig").ComponentsMap;
const ComponentsIterator = @import("ComponentsIterator.zig").ComponentsIterator;

/// The manager of the entities and components.
pub fn EntitiesManager(comptime ComponentsStruct: type) type {
    return struct {
        const Self = @This();

        const InnerState = struct {
            alloc: std.mem.Allocator,
            /// A new entity id
            next_entity: Entity,
            components_map: ComponentsMap(ComponentsStruct),
        };

        inner_state: *InnerState,

        /// Initializes every field of the inner components map.
        /// The allocator is used for allocate inner storages.
        pub fn init(alloc: std.mem.Allocator) !Self {
            const inner_state = try alloc.create(InnerState);
            inner_state.* = .{
                .alloc = alloc,
                .next_entity = .{ .id = 1 },
                .components_map = undefined,
            };

            const Arrays = @typeInfo(ComponentsMap(ComponentsStruct)).@"struct".fields;
            inline for (Arrays) |array| {
                @field(inner_state.components_map, array.name) =
                    array.type.init(alloc);
            }

            return .{ .inner_state = inner_state };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(ComponentsMap(ComponentsStruct)).@"struct".fields) |field| {
                @field(self.inner_state.components_map, field.name).deinit();
            }
            self.inner_state.alloc.destroy(self.inner_state);
            self.inner_state = undefined;
        }

        pub fn newEntity(self: Self) Entity {
            const entity = self.inner_state.next_entity;
            self.inner_state.next_entity.id += 1;
            return entity;
        }

        pub fn addNewEntity(self: Self, components: ComponentsStruct) !Entity {
            const entity = self.newEntity();
            try self.setComponentsToEntity(entity, components);
            return entity;
        }

        /// Aggregates requests of few components for the same entities at once
        pub fn iterator(self: Self, entities: []const Entity) ComponentsIterator(ComponentsStruct) {
            return .{ .entities = entities, .manager = self };
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn get(self: Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.inner_state.components_map, @typeName(C)).getForEntity(entity);
        }

        pub fn getUnsafe(self: Self, entity: Entity, comptime C: type) *C {
            return get(self, entity, C) orelse unreachable;
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

        /// Adds the component of the type `C` to the entity, or replace existed.
        pub fn set(self: Self, entity: Entity, component: anytype) !void {
            const C = @TypeOf(component);
            try @field(self.inner_state.components_map, @typeName(C)).setToEntity(entity, component);
        }

        pub fn getAll(self: Self, comptime C: type) []C {
            return @field(self.inner_state.components_map, @typeName(C)).components.items;
        }

        /// Removes the component of the type `C` from the entity if it was added before, or does nothing.
        pub fn remove(self: Self, entity: Entity, comptime C: type) !void {
            try @field(self.inner_state.components_map, @typeName(C)).removeFromEntity(entity);
        }

        /// Removes all components of the type `C` from all entities.
        pub fn removeAll(self: Self, comptime C: type) void {
            @field(self.inner_state.components_map, @typeName(C)).clear();
        }

        /// Removes all components from all stores which belong to the entity.
        pub fn removeEntity(self: Self, entity: Entity) !void {
            inline for (@typeInfo(ComponentsMap(ComponentsStruct)).@"struct".fields) |field| {
                try @field(self.inner_state.components_map, field.name).removeFromEntity(entity);
            }
        }

        /// Takes all components for the entity and set them to the appropriate
        /// fields of the `ComponentsStruct`.
        pub fn entityToStruct(self: Self, entity: Entity) !ComponentsStruct {
            var structure: ComponentsStruct = undefined;
            inline for (@typeInfo(ComponentsStruct).@"struct".fields) |field| {
                const field_type = @typeInfo(field.type);
                const type_name = @typeName(field_type.optional.child);
                if (@field(self.inner_state.components_map, type_name).getForEntity(entity)) |cmp_ptr|
                    @field(structure, field.name) = cmp_ptr.*
                else
                    @field(structure, field.name) = null;
            }
            return structure;
        }

        /// Sets all defined fields from the `ComponentsStruct` to the entity as the components
        pub fn setComponentsToEntity(self: Self, entity: Entity, components: ComponentsStruct) !void {
            inline for (@typeInfo(ComponentsStruct).@"struct".fields) |field| {
                if (@field(components, field.name)) |component| {
                    try self.set(entity, component);
                }
            }
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

        pub fn deinit(self: *Self) void {
            self.state.deinit();
            self.deinited.* = true;
        }
    };

    const TestComponents = struct {
        foo: ?TestComponent,
    };

    var manager = try EntitiesManager(TestComponents).init(std.testing.allocator);
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
        pub fn deinit(self: *@This()) void {
            self.deinited.* = true;
        }
    };
    const Components = struct { cmp: ?Cmp };

    defer std.testing.expectEqual(true, deinited_2) catch unreachable;
    var manager = try EntitiesManager(Components).init(std.testing.allocator);
    defer manager.deinit();

    const entity = manager.newEntity();
    try manager.set(entity, Cmp{ .value = 1, .deinited = &deinited_1 });

    // when:
    try manager.set(entity, Cmp{ .value = 2, .deinited = &deinited_2 });

    // then:
    try std.testing.expectEqual(2, manager.getUnsafe(entity, Cmp).value);
    try std.testing.expectEqual(true, deinited_1);
}

test "get entity as a struct" {
    // given:
    const Foo = struct { value: u8 };
    const Bar = struct { value: bool };

    const TestComponents = struct { foo: ?Foo, bar: ?Bar };

    var manager = try EntitiesManager(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    const entity = manager.newEntity();
    try manager.set(entity, Bar{ .value = true });

    // when:
    const structure = try manager.entityToStruct(entity);

    // then:
    try std.testing.expectEqual(null, structure.foo);
    try std.testing.expectEqualDeep(Bar{ .value = true }, structure.bar.?);
}

test "set all components as a struct to the entity" {
    // given:
    const Foo = struct { value: u8 };
    const Bar = struct { value: bool };

    const TestComponents = struct { foo: ?Foo = null, bar: ?Bar = null };

    var manager = try EntitiesManager(TestComponents).init(std.testing.allocator);
    defer manager.deinit();

    const entity = try manager.addNewEntity(.{ .foo = .{ .value = 42 } });

    // when:
    const foo = manager.get(entity, Foo);
    const bar = manager.get(entity, Bar);

    // then:
    try std.testing.expectEqualDeep(Foo{ .value = 42 }, foo.?.*);
    try std.testing.expectEqual(null, bar);
}
