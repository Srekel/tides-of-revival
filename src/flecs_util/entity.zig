const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

pub const Entity = struct {
    world: *ecs.world_t,
    id: ecs.entity_t,

    pub fn init(world: *ecs.world_t, id: ecs.entity_t) Entity {
        return .{
            .world = world,
            .id = id,
        };
    }

    fn getWorld(self: Entity) ecsu.World {
        return .{ .world = self.world };
    }

    pub fn format(value: Entity, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try std.fmt.format(writer, "Entity{{ {d} }}", .{value.id});
    }

    pub fn getFullpath(self: Entity) [*c]u8 {
        return ecs.get_path_w_sep(self.world, 0, self.id, ".", null);
    }

    pub fn setName(self: Entity, name: [*c]const u8) void {
        _ = ecs.set_name(self.world, self.id, name);
    }

    pub fn getName(self: Entity) [*c]const u8 {
        return ecs.get_name(self.world, self.id);
    }

    /// add an entity to an entity. This operation adds a single entity to the type of an entity. Type roles may be used in
    /// combination with the added entity.
    pub fn add(self: Entity, id_or_type: anytype) void {
        std.debug.assert(@TypeOf(id_or_type) == ecs.entity_t or @typeInfo(@TypeOf(id_or_type)) == .type);
        const id = if (@TypeOf(id_or_type) == ecs.entity_t) id_or_type else ecsu.meta.componentId(self.world, id_or_type);
        ecs.add_id(self.world, self.id, id);
    }

    /// shortcut for addPair(ChildOf, parent). Allowed parent types: Entity, EntityId, type
    pub fn childOf(self: Entity, parent: anytype) void {
        self.addPair(ecs.ChildOf, parent);
    }

    /// shortcut for addPair(IsA, base). Allowed base types: Entity, EntityId, type
    pub fn isA(self: Entity, base: anytype) void {
        self.addPair(ecs.IsA, base);
    }

    /// adds a relation to the object on the entity. Allowed params: Entity, EntityId, type
    pub fn addPair(self: Entity, relation: anytype, object: anytype) void {
        ecs.add_id(self.world, self.id, self.getWorld().pair(relation, object));
    }

    /// returns true if the entity has the relation to the object
    pub fn hasPair(self: Entity, relation: anytype, object: anytype) bool {
        return ecs.has_id(self.world, self.id, self.getWorld().pair(relation, object));
    }

    /// removes a relation to the object from the entity.
    pub fn removePair(self: Entity, relation: anytype, object: anytype) void {
        return ecs.remove_id(self.world, self.id, self.getWorld().pair(relation, object));
    }

    pub fn setPair(self: Entity, Relation: anytype, comptime object: type, data: Relation) void {
        const pair = self.getWorld().pair(Relation, object);
        const component = &data;
        _ = ecs.set_id(self.world, self.id, pair, @sizeOf(Relation), component);
    }

    /// sets a component on entity. Can be either a pointer to a struct or a struct
    pub fn set(self: Entity, ptr_or_struct: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(ptr_or_struct)) == .pointer or @typeInfo(@TypeOf(ptr_or_struct)) == .@"struct");

        const T = ecsu.meta.FinalChild(@TypeOf(ptr_or_struct));
        const component = if (@typeInfo(@TypeOf(ptr_or_struct)) == .pointer) ptr_or_struct else &ptr_or_struct;
        _ = ecs.set_id(self.world, self.id, ecsu.meta.componentId(self.world, T), @sizeOf(T), component);
    }

    /// sets a private instance of a component on entity. Useful for inheritance.
    pub fn setOverride(self: Entity, ptr_or_struct: anytype) void {
        std.debug.assert(@typeInfo(@TypeOf(ptr_or_struct)) == .pointer or @typeInfo(@TypeOf(ptr_or_struct)) == .@"struct");

        const T = ecsu.meta.FinalChild(@TypeOf(ptr_or_struct));
        const component = if (@typeInfo(@TypeOf(ptr_or_struct)) == .pointer) ptr_or_struct else &ptr_or_struct;
        const id = ecsu.meta.componentId(self.world, T);
        ecs.override_id(self.world, self.id, id);
        _ = ecs.set_id(self.world, self.id, id, @sizeOf(T), component);
    }

    /// sets a component as modified, and will trigger observers after being modified from a system
    pub fn setModified(self: Entity, id_or_type: anytype) void {
        std.debug.assert(@TypeOf(id_or_type) == ecs.entity_t or @typeInfo(@TypeOf(id_or_type)) == .type);
        const id = if (@TypeOf(id_or_type) == ecs.entity_t) id_or_type else ecsu.meta.componentId(self.world, id_or_type);
        ecs.modified_id(self.world, self.id, id);
    }

    /// gets a pointer to a type if the component is present on the entity
    pub fn get(self: Entity, comptime T: type) ?*const T {
        const ptr = ecs.get_id(self.world, self.id, ecsu.meta.componentId(self.world, T));
        if (ptr) |p| {
            return ecsu.componentCast(T, p);
        }
        return null;
    }

    pub fn getMut(self: Entity, comptime T: type) ?*T {
        const ptr = ecs.get_mut_id(self.world, self.id, ecsu.meta.componentId(self.world, T));
        if (ptr) |p| {
            return @ptrCast(@alignCast(p));
        }
        return null;
    }

    pub fn getComps(self: Entity, comptime T: type) T {
        var result: T = undefined;
        inline for (std.meta.fields(T)) |fld| {
            @field(result, fld.name) = self.getMut(@typeInfo(fld.type).pointer.child).?;
        }
        return result;
    }

    /// removes a component from an Entity
    pub fn remove(self: Entity, id_or_type: anytype) void {
        std.debug.assert(@TypeOf(id_or_type) == ecs.entity_t or @typeInfo(@TypeOf(id_or_type)) == .type);
        const id = if (@TypeOf(id_or_type) == ecs.entity_t) id_or_type else ecsu.meta.componentId(self.world, id_or_type);
        ecs.remove_id(self.world, self.id, id);
    }

    /// removes all components from an Entity
    pub fn clear(self: Entity) void {
        ecs.clear(self.world, self.id);
    }

    /// removes the entity from the world. Do not use this Entity after calling this!
    pub fn delete(self: Entity) void {
        ecs.delete(self.world, self.id);
    }

    /// returns true if the entity is alive
    pub fn isValid(self: Entity) bool {
        return self.id != 0;
    }

    /// returns true if the entity is alive
    pub fn isAlive(self: Entity) bool {
        return ecs.is_alive(self.world, self.id);
    }

    /// returns true if the entity has a matching component type
    pub fn has(self: Entity, id_or_type: anytype) bool {
        std.debug.assert(@TypeOf(id_or_type) == ecs.entity_t or @typeInfo(@TypeOf(id_or_type)) == .type);
        const id = if (@TypeOf(id_or_type) == ecs.entity_t) id_or_type else ecsu.meta.componentId(self.world, id_or_type);
        return ecs.has_id(self.world, self.id, id);
    }

    /// returns the type of the component, which contains all components
    pub fn getType(self: Entity) ecsu.type {
        return ecsu.type.init(self.world, ecs.get_type(self.world, self.id));
    }

    /// prints a json representation of an Entity. Note that world.enable_type_reflection should be true to
    /// get component values as well.
    pub fn printJsonRepresentation(self: Entity) void {
        const str = ecs.entity_to_json(self.world, self.id, null);
        std.debug.print("{s}\n", .{str});
        ecs.os_api.free_.?(str);
    }
};
