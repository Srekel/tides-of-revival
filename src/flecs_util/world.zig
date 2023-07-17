const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

const Entity = ecs.entity_t;
const FlecsOrderByAction = fn (ecs.entity_t, ?*const anyopaque, ecs.entity_t, ?*const anyopaque) callconv(.C) c_int;

fn dummyFn(_: [*c]ecs.iter_t) callconv(.C) void {}

const SystemParameters = struct {
    ctx: ?*anyopaque,
};

pub const World = struct {
    world: *ecs.world_t,

    pub fn init() World {
        return .{ .world = ecs.init().? };
    }

    pub fn deinit(self: *World) void {
        _ = ecs.fini(self.world);
    }

    pub fn setTargetFps(self: World, fps: f32) void {
        ecs.set_target_fps(self.world, fps);
    }

    /// available at: https://www.flecs.dev/explorer/?remote=true
    /// test if running: http://localhost:27750/entity/flecs
    // pub fn enableWebExplorer(self: World) void {
    //     _ = ecs.set_id(self.world, flecs.c.FLECS__EEcsRest, flecs.c.FLECS__EEcsRest, @sizeOf(flecs.c.EcsRest), &std.mem.zeroes(flecs.c.EcsRest));
    // }

    /// -1 log level turns off logging
    pub fn setLogLevel(_: World, level: c_int, enable_colors: bool) void {
        _ = ecs.log_set_level(level);
        _ = ecs.log_enable_colors(enable_colors);
    }

    pub fn progress(self: World, delta_time: f32) void {
        _ = ecs.progress(self.world, delta_time);
    }

    pub fn getTypeStr(self: World, typ: ecs.type_t) [*c]u8 {
        return ecs.type_str(self.world, typ);
    }

    pub fn newEntity(self: World) Entity {
        return ecs.new_id(self.world);
    }

    pub fn newEntityWithName(self: World, name: [*c]const u8) Entity {
        var desc = std.mem.zeroInit(ecs.entity_desc_t, .{ .name = name });
        return ecs.entity_init(self.world, &desc);
    }

    pub fn newPrefab(self: World, name: [*c]const u8) ecs.entity_t {
        return ecs.new_prefab(self.world, name);
    }

    /// Allowed params: Entity, EntityId, type
    pub fn pair(self: World, relation: anytype, object: anytype) u64 {
        const Relation = @TypeOf(relation);
        const Object = @TypeOf(object);

        const rel_info = @typeInfo(Relation);
        const obj_info = @typeInfo(Object);

        std.debug.assert(rel_info == .Struct or rel_info == .Type or Relation == ecs.entity_t or Relation == ecs.entity_t or Relation == c_int);
        std.debug.assert(obj_info == .Struct or obj_info == .Type or Object == ecs.entity_t or Object == ecs.entity_t);

        const rel_id = switch (Relation) {
            c_int => @as(ecs.entity_t, @intCast(relation)),
            type => self.componentId(relation),
            ecs.entity_t => relation,
            ecs.entity_t => relation.id,
            else => unreachable,
        };

        const obj_id = switch (Object) {
            type => self.componentId(object),
            ecs.entity_t => object,
            ecs.entity_t => object.id,
            else => unreachable,
        };

        return ecs.ECS_PAIR | (rel_id << @as(u32, 32)) + @as(u32, @truncate(obj_id));
    }

    /// bulk registers a tuple of Types
    pub fn registerComponents(self: World, types: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(types)) == .Struct);
        inline for (types) |t| {
            _ = self.componentId(t);
        }
    }

    /// gets the EntityId for T creating it if it doesn't already exist
    pub fn componentId(self: World, comptime T: type) ecs.entity_t {
        return ecsu.meta.componentId(self.world, T);
    }

    /// creates a new type entity, or finds an existing one. A type entity is an entity with the EcsType component. The name will be generated
    /// by adding the Ids of each component so that order doesnt matter.
    pub fn newType(self: World, comptime Types: anytype) ecs.entity_t {
        var i: ecs.entity_t = 0;
        inline for (Types) |T| {
            i += self.componentId(T);
        }

        const name = std.fmt.allocPrintZ(std.heap.c_allocator, "Type{d}", .{i}) catch unreachable;
        return self.newTypeWithName(name, Types);
    }

    /// creates a new type entity, or finds an existing one. A type entity is an entity with the EcsType component.
    pub fn newTypeWithName(self: World, name: [*c]const u8, comptime Types: anytype) ecs.entity_t {
        var desc = std.mem.zeroes(ecs.type_desc_t);
        desc.entity = std.mem.zeroInit(ecs.entity_desc_t, .{ .name = name });

        inline for (Types, 0..) |T, i| {
            desc.ids[i] = self.componentId(T);
        }

        return ecs.type_init(self.world, &desc);
    }

    pub fn newTypeExpr(self: World, name: [*c]const u8, expr: [*c]const u8) ecs.entity_t {
        var desc = std.mem.zeroInit(ecs.type_desc_t, .{ .ids_expr = expr });
        desc.entity = std.mem.zeroInit(ecs.entity_desc_t, .{ .name = name });

        return ecs.type_init(self.world, &desc);
    }

    /// this operation will preallocate memory in the world for the specified number of entities
    pub fn dim(self: World, entity_count: i32) void {
        ecs.dim(self.world, entity_count);
    }

    /// this operation will preallocate memory for a type (table) for the specified number of entities
    pub fn dimType(self: World, ecs_type: ecs.type_t, entity_count: i32) void {
        ecs.dim_type(self.world, ecs_type, entity_count);
    }

    pub fn newSystem(self: World, name: [*c]const u8, phase: ecsu.Phase, signature: [*c]const u8, action: ecs.iter_action_t) void {
        var desc = std.mem.zeroes(ecs.system_desc_t);
        desc.entity.name = name;
        desc.entity.add[0] = @intFromEnum(phase);
        desc.query.filter.expr = signature;
        // desc.multi_threaded = true;
        desc.callback = action;
        _ = ecs.system_init(self.world, &desc);
    }

    pub fn newRunSystem(self: World, name: [*c]const u8, phase: ecsu.Phase, signature: [*c]const u8, action: ecs.iter_action_t) void {
        var desc = std.mem.zeroes(ecs.system_desc_t);
        desc.entity.name = name;
        desc.entity.add[0] = @intFromEnum(phase);
        desc.query.filter.expr = signature;
        // desc.multi_threaded = true;
        desc.callback = dummyFn;
        desc.run = action;
        _ = ecs.system_init(self.world, &desc);
    }

    pub fn newWrappedRunSystem(self: World, name: [*c]const u8, phase: ecsu.Phase, comptime Components: type, comptime action: fn (*ecsu.Iterator(Components)) void, params: SystemParameters) ecs.entity_t {
        var edesc = std.mem.zeroes(ecs.entity_desc_t);

        edesc.id = 0;
        edesc.name = name;
        edesc.add[0] = ecs.ecs_make_pair(ecs.EcsDependsOn, @intFromEnum(phase));
        edesc.add[1] = @intFromEnum(phase);

        var desc = std.mem.zeroes(ecs.system_desc_t);
        desc.entity = ecs.entity_init(self.world, &edesc);
        desc.query.filter = ecsu.meta.generateFilterDesc(self, Components);
        desc.callback = dummyFn;
        desc.run = wrapSystemFn(Components, action);
        desc.ctx = params.ctx;
        return ecs.system_init(self.world, &desc);
    }

    /// creates a Filter using the passed in struct
    pub fn filter(self: World, comptime Components: type) ecsu.Filter {
        std.debug.assert(@typeInfo(Components) == .Struct);
        var desc = ecsu.meta.generateFilterDesc(self, Components);
        return ecsu.Filter.init(self, &desc);
    }

    /// probably temporary until we find a better way to handle it better, but a way to
    /// iterate the passed components of children of the parent entity
    pub fn filterParent(self: World, comptime Components: type, parent: ecs.entity_t) ecsu.Filter {
        std.debug.assert(@typeInfo(Components) == .Struct);
        var desc = ecsu.meta.generateFilterDesc(self, Components);
        const component_info = @typeInfo(Components).Struct;
        desc.terms[component_info.fields.len].id = self.pair(ecs.ChildOf, parent);
        return ecsu.Filter.init(self, &desc);
    }

    /// creates a Query using the passed in struct
    pub fn query(self: World, comptime Components: type) ecsu.Query {
        std.debug.assert(@typeInfo(Components) == .Struct);
        var desc = std.mem.zeroes(ecs.query_desc_t);
        desc.filter = ecsu.meta.generateFilterDesc(self, Components);

        if (@hasDecl(Components, "order_by")) {
            ecsu.meta.validateOrderByFn(Components.order_by);
            const ti = @typeInfo(@TypeOf(Components.order_by));
            const OrderByType = ecsu.meta.FinalChild(ti.Fn.args[1].arg_type.?);
            ecsu.meta.validateOrderByType(Components, OrderByType);

            desc.order_by = wrapOrderByFn(OrderByType, Components.order_by);
            desc.order_by_component = self.componentId(OrderByType);
        }

        if (@hasDecl(Components, "instanced") and Components.instanced) desc.filter.instanced = true;

        return ecsu.Query.init(self, &desc);
    }

    /// adds a system to the World using the passed in struct
    pub fn system(self: World, comptime Components: type, phase: ecsu.Phase) void {
        std.debug.assert(@typeInfo(Components) == .Struct);
        std.debug.assert(@hasDecl(Components, "run"));
        std.debug.assert(@hasDecl(Components, "name"));

        var desc = std.mem.zeroes(ecs.system_desc_t);
        desc.callback = dummyFn;
        desc.entity.name = Components.name;
        desc.entity.add[0] = @intFromEnum(phase);
        // desc.multi_threaded = true;
        desc.run = wrapSystemFn(Components, Components.run);
        desc.query.filter = ecsu.meta.generateFilterDesc(self, Components);

        if (@hasDecl(Components, "order_by")) {
            ecsu.meta.validateOrderByFn(Components.order_by);
            const ti = @typeInfo(@TypeOf(Components.order_by));
            const OrderByType = ecsu.meta.FinalChild(ti.Fn.args[1].arg_type.?);
            ecsu.meta.validateOrderByType(Components, OrderByType);

            desc.query.order_by = wrapOrderByFn(OrderByType, Components.order_by);
            desc.query.order_by_component = self.componentId(OrderByType);
        }

        if (@hasDecl(Components, "instanced") and Components.instanced) desc.filter.instanced = true;

        _ = ecs.system_init(self.world, &desc);
    }

    /// adds an observer system to the World using the passed in struct (see systems)
    pub fn observer(self: World, comptime Components: type, event: ecsu.Event, ctx: ?*anyopaque) void {
        std.debug.assert(@typeInfo(Components) == .Struct);
        std.debug.assert(@hasDecl(Components, "run"));
        std.debug.assert(@hasDecl(Components, "name"));

        var desc = std.mem.zeroes(ecs.observer_desc_t);
        desc.callback = dummyFn;
        desc.ctx = ctx;
        // TODO
        // desc.entity.name = Components.name;
        desc.events[0] = @intFromEnum(event);

        desc.run = wrapSystemFn(Components, Components.run);
        desc.filter = ecsu.meta.generateFilterDesc(self, Components);

        if (@hasDecl(Components, "instanced") and Components.instanced) desc.filter.instanced = true;

        _ = ecs.observer_init(self.world, &desc);
    }

    pub fn setName(self: World, entity: ecs.entity_t, name: [*c]const u8) void {
        _ = ecs.set_name(self.world, entity, name);
    }

    pub fn getName(self: World, entity: ecs.entity_t) [*c]const u8 {
        return ecs.get_name(self.world, entity);
    }

    /// sets a component on entity. Can be either a pointer to a struct or a struct
    pub fn set(self: *World, entity: ecs.entity_t, ptr_or_struct: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(ptr_or_struct)) == .Pointer or @typeInfo(@TypeOf(ptr_or_struct)) == .Struct);

        const T = ecsu.meta.FinalChild(@TypeOf(ptr_or_struct));
        var component = if (@typeInfo(@TypeOf(ptr_or_struct)) == .Pointer) ptr_or_struct else &ptr_or_struct;
        _ = ecs.set_id(self.world, entity, self.componentId(T), @sizeOf(T), component);
    }

    pub fn getMut(self: *World, entity: ecs.entity_t, comptime T: type) *T {
        var ptr = ecs.get_mut_id(self.world, entity.id, ecsu.meta.componentId(self.world, T));
        return @ptrCast(@alignCast(ptr.?));
    }

    /// removes a component from an Entity
    pub fn remove(self: *World, entity: ecs.entity_t, comptime T: type) void {
        ecs.remove_id(self.world, entity, self.componentId(T));
    }

    /// removes all components from an Entity
    pub fn clear(self: *World, entity: ecs.entity_t) void {
        ecs.clear(self.world, entity);
    }

    /// removes the entity from the world
    pub fn delete(self: *World, entity: ecs.entity_t) void {
        ecs.delete(self.world, entity);
    }

    /// deletes all entities with the component
    pub fn deleteWith(self: *World, comptime T: type) void {
        ecs.delete_with(self.world, self.componentId(T));
    }

    /// remove all instances of the specified component
    pub fn removeAll(self: *World, comptime T: type) void {
        ecs.remove_all(self.world, self.componentId(T));
    }

    pub fn setSingleton(self: World, ptr_or_struct: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(ptr_or_struct)) == .Pointer or @typeInfo(@TypeOf(ptr_or_struct)) == .Struct);

        const T = ecsu.meta.FinalChild(@TypeOf(ptr_or_struct));
        var component = if (@typeInfo(@TypeOf(ptr_or_struct)) == .Pointer) ptr_or_struct else &ptr_or_struct;
        _ = ecs.set_id(self.world, self.componentId(T), self.componentId(T), @sizeOf(T), component);
    }

    // TODO: use ecs_get_mut_id optionally based on a bool perhaps or maybe if the passed in type is a pointer?
    pub fn getSingleton(self: World, comptime T: type) ?*const T {
        std.debug.assert(@typeInfo(T) == .Struct);
        var val = ecs.get_id(self.world, self.componentId(T), self.componentId(T));
        if (val == null) return null;
        return @as(*const T, @ptrCast(@alignCast(val)));
    }

    pub fn getSingletonMut(self: World, comptime T: type) ?*T {
        std.debug.assert(@typeInfo(T) == .Struct);
        var val = ecs.get_mut_id(self.world, self.componentId(T), self.componentId(T));
        if (val == null) return null;
        return @as(*T, @ptrCast(@alignCast(val)));
    }

    pub fn removeSingleton(self: World, comptime T: type) void {
        std.debug.assert(@typeInfo(T) == .Struct);
        ecs.remove_id(self.world, self.componentId(T), self.componentId(T));
    }
};

fn wrapSystemFn(comptime T: type, comptime cb: fn (*ecsu.Iterator(T)) void) fn ([*c]ecs.iter_t) callconv(.C) void {
    const Closure = struct {
        pub const callback: fn (*ecsu.Iterator(T)) void = cb;

        pub fn closure(it: [*c]ecs.iter_t) callconv(.C) void {
            var iter = ecsu.Iterator(T).init(it, ecs.iter_next);
            callback(&iter);
        }
    };
    return Closure.closure;
}

fn wrapOrderByFn(comptime T: type, comptime cb: fn (ecs.entity_t, *const T, ecs.entity_t, *const T) c_int) FlecsOrderByAction {
    const Closure = struct {
        pub fn closure(e1: ecs.entity_t, c1: ?*const anyopaque, e2: ecs.entity_t, c2: ?*const anyopaque) callconv(.C) c_int {
            return @call(.{ .modifier = .always_inline }, cb, .{ e1, ecsu.componentCast(T, c1), e2, ecsu.componentCast(T, c2) });
        }
    };
    return Closure.closure;
}
