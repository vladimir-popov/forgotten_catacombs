// This is an implementation of the Entity Component System pattern,
// which is a core of the game.

const std = @import("std");

/// The id of an entity.
pub const Entity = u32;

/// The container of the components of the type `C`.
/// The components are stored in the array, and can be got
/// for an entity for O(1) thanks for additional indexes inside.
fn ComponentArray(comptime C: type) type {
    return struct {
        const Self = @This();
        // all components have to be stored in the array for perf. boost.
        components: std.ArrayList(C),
        entity_index: std.AutoHashMap(Entity, u8),
        index_entity: std.AutoHashMap(u8, Entity),

        /// Creates instances of the inner storages.
        fn init(alloc: std.mem.Allocator) Self {
            return .{
                .components = std.ArrayList(C).init(alloc),
                .entity_index = std.AutoHashMap(Entity, u8).init(alloc),
                .index_entity = std.AutoHashMap(u8, Entity).init(alloc),
            };
        }

        /// Deinits the inner storages.
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

        /// Adds the component of the type `C` for the entity.
        fn addToEntity(self: *Self, entity: Entity, component: C) void {
            self.entity_index.put(entity, @intCast(self.components.items.len)) catch |err|
                std.debug.panic("The memory error {any} happened on putting entity {d}", .{ err, entity });
            self.index_entity.put(@intCast(self.components.items.len), entity) catch |err|
                std.debug.panic("The memory error {any} happened on putting index to entity {d}", .{ err, entity });
            self.components.append(component) catch |err|
                std.debug.panic("The memory error {any} happened on appending a component", .{err});
        }

        /// Deletes the components of the entity from the all inner stores,
        /// if they was added before, or does nothing.
        fn removeFromEntity(self: *Self, entity: Entity) void {
            if (self.entity_index.get(entity)) |idx| {
                _ = self.index_entity.remove(idx);
                _ = self.entity_index.remove(entity);

                const last_idx: u8 = @intCast(self.components.items.len - 1);
                if (idx == last_idx) {
                    _ = self.components.pop();
                } else {
                    const last_entity = self.index_entity.get(last_idx).?;
                    self.components.items[idx] = self.components.pop();
                    self.entity_index.put(last_entity, idx) catch |err|
                        std.debug.panic("The memory error {any}", .{err});
                    self.index_entity.put(idx, last_entity) catch |err|
                        std.debug.panic("The memory error {any}", .{err});
                }
            }
        }
    };
}

/// The dynamically generated in compile time structure,
/// which has  fields for every type from the `ComponentTypes` array.
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

        const InnerState = struct {
            components_map: CM,
        };

        inner_state: InnerState,

        /// Initializes every field of the inner components map.
        /// The allocator is used for allocate inner storages.
        pub fn init(alloc: std.mem.Allocator) Self {
            var components_map: CM = undefined;

            inline for (@typeInfo(CM).Struct.fields) |field| {
                @field(components_map, field.name) = field.type.init(alloc);
            }

            return .{ .inner_state = .{ .components_map = components_map } };
        }

        /// Cleans up all inner storages.
        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(CM).Struct.fields) |field| {
                @field(self.inner_state.components_map, field.name).deinit();
            }
        }

        /// Returns the pointer to the component for the entity, if it was added before, or null.
        pub fn getForEntity(self: *Self, entity: Entity, comptime C: type) ?*C {
            return @field(self.inner_state.components_map, @typeName(C)).getForEntity(entity);
        }

        /// Adds the component of the type `C` to the entity.
        pub fn addToEntity(self: *Self, entity: Entity, comptime C: type, component: anytype) void {
            @field(self.inner_state.components_map, @typeName(C)).addToEntity(entity, component);
        }

        /// Removes the component of the type `C` from the entity if it was added before, or does nothing.
        pub fn removeFromEntity(self: *Self, entity: Entity, comptime C: type) void {
            @field(self.inner_state.components_map, @typeName(C)).removeFromEntity(entity);
        }

        /// Removes all components from all stores which belong to the entity.
        pub fn removeAllForEntity(self: *Self, entity: Entity) void {
            inline for (@typeInfo(CM).Struct.fields) |field| {
                @field(self.inner_state.components_map, field.name).removeFromEntity(entity);
            }
        }

        fn removeAllForEntityOpaque(ptr: *anyopaque, entity: Entity) void {
            var cm: *Self = @ptrCast(@alignCast(ptr));
            cm.removeAllForEntity(entity);
        }
    };
}

test "ComponentsManager: Add/Get/Remove component" {
    const TestComponent = struct { tag: []const u8 = undefined };
    var manager = ComponentsManager(.{TestComponent}).init(std.testing.allocator);
    defer manager.deinit();

    // should return the component, which was added before
    const entity = 1;
    manager.addToEntity(entity, TestComponent, .{ .tag = "test" });
    var component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqualStrings("test", component.?.tag);

    // should return null for entity, without requested component
    component = manager.getForEntity(entity + 1, TestComponent);
    try std.testing.expectEqual(null, component);

    // should return null for removed component
    manager.removeFromEntity(entity, TestComponent);
    component = manager.getForEntity(entity, TestComponent);
    try std.testing.expectEqual(null, component);
}

/// The manager of the entities.
const EntitiesManager = struct {
    const Self = @This();

    const InnerState = struct {
        entities: std.AutoHashMap(Entity, void),
        components_ptr: *anyopaque,
        last_entity: Entity,
    };

    inner_state: InnerState,
    removeAllComponentsForEntity: *const fn (components_manager: *anyopaque, entity: Entity) void,

    pub fn init(
        alloc: std.mem.Allocator,
        components_manager: *anyopaque,
        removeAllComponentsForEntity: *const fn (components_manager: *anyopaque, entity: Entity) void,
    ) Self {
        return .{
            .removeAllComponentsForEntity = removeAllComponentsForEntity,
            .inner_state = InnerState{
                .entities = std.AutoHashMap(Entity, void).init(alloc),
                .components_ptr = components_manager,
                .last_entity = 1,
            },
        };
    }

    /// Removes components from the components manager for every entity,
    /// and clean up the inner entities storage.
    pub fn deinit(self: *Self) void {
        var itr = self.inner_state.entities.iterator();
        while (itr.next()) |entity| {
            self.inner_state.components_ptr.removeAllComponentsForEntity(entity);
        }
        self.entities.deinit();
    }

    /// Generates an unique id for the new entity, puts it to the inner storage,
    /// and then returns as the result. The id is unique for whole life circle of
    /// this manager.
    pub fn newEntity(self: *Self) Entity {
        self.inner_state.last_entity += 1;
        const entity = self.inner_state.last_entity;
        _ = self.inner_state.entities.getOrPut(entity) catch |err|
            std.debug.panic("The memory error {any} happened on creating a new entity", .{err});
        return entity;
    }

    /// Removes all components of the entity and it self from the inner storage.
    pub fn removeEntity(self: *Self, entity: Entity) void {
        self.removeAllComponentsForEntity(self.inner_state.components_ptr, entity);
        _ = self.inner_state.entities.remove(entity);
    }

    /// The iterator over entities. It should be used to get
    /// entities from this manager.
    const Iterator = struct {
        key_terator: std.AutoHashMap(Entity, void).KeyIterator,

        pub fn next(self: *@This()) ?Entity {
            if (self.key_terator.next()) |entity_ptr| {
                return entity_ptr.*;
            } else {
                return null;
            }
        }
    };

    pub fn iterator(self: *Self) Iterator {
        return .{ .key_terator = self.inner_state.entities.keyIterator() };
    }
};

test "EntitiesManager: Add/Remove" {
    const TestComponent = struct { tag: []const u8 = undefined };
    const CM = ComponentsManager(.{TestComponent});
    var cm = CM.init(std.testing.allocator);
    defer cm.deinit();

    var em = EntitiesManager.init(std.testing.allocator, &cm, CM.removeAllForEntityOpaque);
    defer em.deinit();

    const entity = em.newEntity();
    cm.addToEntity(entity, TestComponent, .{ .tag = "test" });

    // when:
    em.removeEntity(entity);

    // then:
    try std.testing.expectEqual(null, cm.getForEntity(entity, TestComponent));
}

test "EntitiesManager: iterator" {
    const TestComponent = struct { tag: []const u8 = undefined };
    const CM = ComponentsManager(.{TestComponent});
    var cm = CM.init(std.testing.allocator);
    defer cm.deinit();

    var em = EntitiesManager.init(std.testing.allocator, &cm, CM.removeAllForEntityOpaque);
    defer em.deinit();

    const e1 = em.newEntity();
    const e2 = em.newEntity();

    var itr = em.iterator();
    var entitiesSum: u32 = 0;
    while (itr.next()) |entity| {
        std.debug.assert(entity == e1 or entity == e2);
        entitiesSum += entity;
    }
    try std.testing.expectEqual(e1 + e2, entitiesSum);
}

pub fn System(comptime GameType: type) type {
    return *const fn (game: *GameType) anyerror!void;
}

/// The global manager of all resources of the game. It must be a singleton.
/// Every operations over entities and components should be done with this
/// object.
pub fn Game(comptime Components: anytype, comptime Runtime: type) type {
    return struct {
        const Self = @This();

        const InnerState = struct {
            /// The allocator which is used for creating this inner state.
            alloc: std.mem.Allocator,
            components: ComponentsManager(Components),
            entities: EntitiesManager,
            systems: std.ArrayList(System(Self)),

            pub fn deinit(self: *@This()) void {
                self.entities.deinit();
                self.components.deinit();
                self.systems.deinit();
                self.alloc.destroy(self);
            }
        };
        /// To protect access to the inner state, everything is wrapped to the
        /// structure, and can be accessed only inside this type.
        inner_state: *anyopaque,

        /// A runtime in which the game is run.
        runtime: Runtime,

        /// private typed getter of the inner state
        inline fn st(self: Self) *InnerState {
            return @ptrCast(@alignCast(self.inner_state));
        }

        pub fn init(runtime: Runtime, alloc: std.mem.Allocator) Self {
            const state = alloc.create(InnerState) catch |err|
                std.debug.panic("The memory error {any} happened on crating the inner state of the game.", .{err});
            state.alloc = alloc;
            state.components = ComponentsManager(Components).init(alloc);
            state.entities = EntitiesManager.init(
                alloc,
                &state.components,
                ComponentsManager(Components).removeAllForEntityOpaque,
            );
            state.systems = std.ArrayList(System(Self)).init(alloc);

            return .{ .runtime = runtime, .inner_state = state };
        }

        pub fn deinit(self: *Self) void {
            self.st().deinit();
        }

        pub fn registerSystem(self: *Self, system: System(Self)) void {
            self.st().systems.append(system) catch |err|
                std.debug.panic("The memory error {any} happened on registration system.", .{err});
        }

        pub fn tick(self: *Self) anyerror!void {
            for (self.st().systems.items) |system| {
                try system(self);
            }
        }

        const EntityBuilder = struct {
            const EB = @This();

            entity: Entity,
            cm_ptr: *ComponentsManager(Components),

            pub fn addComponent(self: EB, comptime C: type, component: C) void {
                self.cm_ptr.addToEntity(self.entity, C, component);
            }
        };

        pub fn newEntity(self: Self) EntityBuilder {
            return .{ .entity = self.st().entities.newEntity(), .cm_ptr = &self.st().components };
        }

        pub fn entitiesIterator(self: *Self) EntitiesManager.Iterator {
            return self.st().entities.iterator();
        }

        pub fn getComponent(self: Self, entity: Entity, comptime C: type) ?*C {
            return self.st().components.getForEntity(entity, C);
        }
    };
}
