pub const ecs = @import("zflecs");

pub const Entity = @import("entity.zig").Entity;
pub const Filter = @import("filter.zig").Filter;
pub const Iterator = @import("iterator.zig").Iterator;
pub const Query = @import("query.zig").Query;
pub const QueryBuilder = @import("query_builder.zig").QueryBuilder;
pub const TableIterator = @import("table_iterator.zig").TableIterator;
pub const Type = @import("type.zig").Type;
pub const World = @import("world.zig").World;
pub const column = @import("utils.zig").column;
pub const columnOpt = @import("utils.zig").columnOpt;
pub const columnNonQuery = @import("utils.zig").columnNonQuery;
pub const componentCast = @import("utils.zig").componentCast;
pub const meta = @import("meta.zig");

pub const ECS_HI_COMPONENT_ID = 256;

// Builtin pipeline tags
// pub const Phase = enum(ecs.id_t) {
//     monitor = ecs.Monitor,
//     // pipeline = ecs.Pipeline,
//     pre_frame = ecs.PreFrame,
//     on_load = ecs.OnLoad,
//     post_load = ecs.PostLoad,
//     pre_update = ecs.PreUpdate,
//     on_update = ecs.OnUpdate,
//     on_validate = ecs.OnValidate,
//     post_update = ecs.PostUpdate,
//     pre_store = ecs.PreStore,
//     on_store = ecs.OnStore,
//     post_frame = ecs.PostFrame,
// };

// pub const Event = enum(ecs.id_t) {
//     // Event. Triggers when an id (component, tag, pair) is added to an entity
//     on_add = ecs.OnAdd,
//     // Event. Triggers when an id (component, tag, pair) is removed from an entity
//     on_remove = ecs.OnRemove,
//     // Event. Triggers when a component is set for an entity
//     on_set = ecs.OnSet,
//     // Event. Triggers when a component is unset for an entity
//     un_set = ecs.UnSet,
//     // Event. Triggers when an entity is deleted.
//     on_delete = ecs.OnDelete,
//     // Event. Exactly-once trigger for when an entity matches/unmatches a filter
//     monitor = ecs.Monitor,
//     _,
// };
