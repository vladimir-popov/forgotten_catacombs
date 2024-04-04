const std = @import("std");
const Iterator = @import("Iterator.zig");

pub const Entity = u32;

/// The container of the components of the type `C`.
/// The components are stored in the array, and can be got
/// for an entity for O(1) thanks for additional index inside.
fn ComponentArray(comptime C: type) type {
    return struct {
        const Self = @This();
        // all components have to be stored in the array for perf. boost.
        components: std.ArrayList(C),
        entity_index: std.AutoHashMap(Entity, u8),
        index_entity: std.AutoHashMap(u8, Entity),

        /// Creates instances of the inner storages
        fn init(alloc: std.mem.Allocator) Self {
            return .{
                .components = std.ArrayList(C).init(alloc),
                .entity_index = std.AutoHashMap(Entity, u8).init(alloc),
                .index_entity = std.AutoHashMap(u8, Entity).init(alloc),
            };
        }

        /// Deinits inner storages
        fn deinit(self: *Self) void {
            self.components.deinit();
            self.entity_index.deinit();
            self.index_entity.deinit();
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        fn getForEntity(self: Self, entity: Entity) ?*C {
            if (self.entity_index.get(entity)) |idx| {
                return &self.components.items[idx];
            } else {
                return null;
            }
        }

        /// Adds the component of the type `C` to the entity.
        fn addToEntity(self: *Self, entity: Entity, component: C) std.mem.Allocator.Error!void {
            try self.entity_index.put(entity, @intCast(self.components.items.len));
            try self.index_entity.put(@intCast(self.components.items.len), entity);
            try self.components.append(component);
        }

        /// Deletes the components from the entity from all inner stores if it was added before,
        /// or does nothing.
        fn removeFromEntity(self: *Self, entity: Entity) std.mem.Allocator.Error!void {
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

/// The dynamically generated in compile time struct,
/// which has a field for every type from the `ComponentTypes` array.
fn ComponentsMap(comptime ComponentTypes: anytype) type {
    var fields: [ComponentTypes.len]std.builtin.Type.StructField = undefined;
    for (ComponentTypes, 0..) |t, i| {
        fields[i] = .{
            .name = @typeName(t),
            .type = ComponentArray(t),
            .default_value = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }
    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .fields = fields[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

/// The manager of the components.
fn ComponentsManager(comptime ComponentTypes: anytype) type {
    return struct {
        const Self = @This();
        const CM = ComponentsMap(ComponentTypes);

        alloc: std.mem.Allocator,
        components: *CM,

        /// Creates instances for all inner stores.
        pub fn init(alloc: std.mem.Allocator) !Self {
            const components_ptr = try alloc.create(CM);
            errdefer alloc.destroy(components_ptr);

            inline for (@typeInfo(CM).Struct.fields) |field| {
                @field(components_ptr.*, field.name) = field.type.init(alloc);
            }

            return .{ .alloc = alloc, .components = components_ptr };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: Self) void {
            inline for (@typeInfo(CM).Struct.fields) |field| {
                @field(self.components.*, field.name).deinit();
            }
            self.alloc.destroy(self.components);
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn getForEntity(self: Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.components.*, @typeName(C)).getForEntity(entity);
        }

        /// Adds the component of the type `C` to the entity.
        pub fn addToEntity(self: Self, entity: Entity, comptime C: type, component: anytype) std.mem.Allocator.Error!void {
            try @field(self.components.*, @typeName(C)).addToEntity(entity, component);
        }

        /// Removes the component of the type `C` from the entity if it was added before, or does nothing.
        pub fn removeFromEntity(self: Self, entity: Entity, comptime C: type) std.mem.Allocator.Error!void {
            try @field(self.components.*, @typeName(C)).removeFromEntity(entity);
        }

        /// Removes all components from all stores which belong to the entity.
        pub fn removeAllForEntity(self: Self, entity: Entity) std.mem.Allocator.Error!void {
            inline for (@typeInfo(CM).Struct.fields) |field| {
                try @field(self.components.*, field.name).removeFromEntity(entity);
            }
        }
    };
}

test "ComponentsManager: Add/Get/Remove component" {
    const TestComponent = struct { tag: []const u8 = undefined };
    const manager = try ComponentsManager(.{TestComponent}).init(std.testing.allocator);
    defer manager.deinit();

    // should return the component, which was added before
    const entity = 1;
    try manager.addToEntity(entity, TestComponent, .{ .tag = "test" });
    var component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqualStrings("test", component.?.tag);

    // should return null for entity, without requested component
    component = manager.getForEntity(entity + 1, TestComponent);
    try std.testing.expectEqual(null, component);

    // should return null for removed component
    try manager.removeFromEntity(entity, TestComponent);
    component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqual(null, component);
}

fn EntitiesManager(comptime CM: anytype) type {
    const InnerState = struct { last_entity: Entity };
    return struct {
        const Self = @This();

        entities: std.AutoHashMap(Entity, void),
        components_manager: *const CM,
        state: InnerState = InnerState{ .last_entity = 1 },

        pub fn init(alloc: std.mem.Allocator, components_manager: *const CM) Self {
            return .{ .components_manager = components_manager, .entities = std.AutoHashMap(Entity, void).init(alloc) };
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit();
        }

        pub fn newEntity(self: *Self) std.mem.Allocator.Error!Entity {
            self.state.last_entity += 1;
            const entity = self.state.last_entity;
            _ = try self.entities.getOrPut(entity);
            return entity;
        }

        pub fn removeEntity(self: *Self, entity: Entity) std.mem.Allocator.Error!void {
            try self.components_manager.removeAllForEntity(entity);
            _ = self.entities.remove(entity);
        }

        pub fn entitiesIterator(self: *Self) Iterator.AnyIterator(*Entity) {
            const Underlying = std.AutoHashMap(Entity, void).KeyIterator;
            var genItr = Iterator.GenericIterator(*Entity, Underlying, Underlying.next){
                .underlying = self.entities.keyIterator(),
            };
            return genItr.any();
        }
    };
}

test "EntitiesManager: Add/Remove" {
    const TestComponent = struct { tag: []const u8 = undefined };
    const CM = ComponentsManager(.{TestComponent});
    const cm = try CM.init(std.testing.allocator);
    defer cm.deinit();

    var em = EntitiesManager(CM).init(std.testing.allocator, &cm);
    defer em.deinit();

    const entity = try em.newEntity();
    try cm.addToEntity(entity, TestComponent, .{ .tag = "test" });

    // when:
    try em.removeEntity(entity);

    // then:
    try std.testing.expectEqual(null, cm.getForEntity(entity, TestComponent));
}

pub fn Game(comptime ComponentTypes: anytype, comptime Runtime: type, comptime Error: type) type {
    return struct {
        const Self = @This();

        const CM = ComponentsManager(ComponentTypes);
        const EM = EntitiesManager(ComponentsManager(ComponentTypes));
        const System = *const fn (gs: *Self, runtime: *Runtime) Error!void;

        components: CM,
        entities: EM,
        systems: std.ArrayList(System),

        pub fn init(alloc: std.mem.Allocator) !Self {
            const components = try CM.init(alloc);
            return .{
                .components = components,
                .entities = EM.init(alloc, &components),
                .systems = std.ArrayList(System).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entities.deinit();
            self.components.deinit();
            self.systems.deinit();
        }

        pub fn registerSystem(self: *Self, system: System) !void {
            try self.systems.append(system);
        }

        pub fn tick(self: *Self, runtime: *Runtime) Error!void {
            for (self.systems.items) |system| {
                try system(self, runtime);
            }
        }

        pub fn iterateComponents2(
            self: *Self,
            comptime A: type,
            comptime B: type,
        ) Iterator.AnyIterator(std.meta.Tuple(&[_]type{ *A, *B })) {
            const T = std.meta.Tuple(&[_]type{ *A, *B });
            const Underlying = struct {
                const USelf = @This();

                ctx: *Self,
                itr: Iterator.AnyIterator(*Entity),

                fn next(uself: *USelf) ?T {
                    std.debug.print("next\n", .{});
                    while (uself.itr.next()) |entity_ptr| {
                        std.debug.print("entity_ptr {any}\n", .{entity_ptr.*});
                        if (uself.ctx.components.getForEntity(entity_ptr.*, A)) |a_ptr| {
                            std.debug.print("a {any}\n", .{a_ptr.*});
                            if (uself.ctx.components.getForEntity(entity_ptr.*, B)) |b_ptr| {
                                std.debug.print("b {any}\n", .{b_ptr.*});
                                return .{ a_ptr, b_ptr };
                            }
                        }
                    }
                    return null;
                }
            };
            var itr = Iterator.GenericIterator(T, Underlying, Underlying.next){
                .underlying = Underlying{ .ctx = self, .itr = self.entities.entitiesIterator() },
            };
            return itr.any();
        }
    };
}

// test "Game: iterate over 2 components" {
//     const Comp1 = struct { tag1: u8 };
//     const Comp2 = struct { tag2: u8 };
//
//     var game = try Game(.{ Comp1, Comp2 }, void, anyerror).init(std.testing.allocator);
//     defer game.deinit();
//
//     const entity1 = try game.entities.newEntity();
//     const entity2 = try game.entities.newEntity();
//     const entity3 = try game.entities.newEntity();
//
//     try game.components.addToEntity(entity1, Comp1, .{ .tag1 = 1 });
//     try game.components.addToEntity(entity1, Comp2, .{ .tag2 = 2 });
//
//     try game.components.addToEntity(entity2, Comp2, .{ .tag2 = 3 });
//
//     try game.components.addToEntity(entity3, Comp1, .{ .tag1 = 4 });
//     try game.components.addToEntity(entity3, Comp2, .{ .tag2 = 5 });
//
//     var itr = game.iterateComponents2(Comp1, Comp2);
//     while (itr.next()) |tuple| {
//         std.debug.print("{any}\n", .{tuple});
//     }
// }
