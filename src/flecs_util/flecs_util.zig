pub const ecs = @import("zflecs");

pub const Entity = @import("entity.zig").Entity;
pub const Filter = @import("filter.zig").Filter;
pub const Iterator = @import("iterator.zig").Iterator;
pub const Query = @import("query.zig").Query;
pub const QueryBuilder = @import("query_builder.zig").QueryBuilder;
pub const TableIterator = @import("table_iterator.zig").TableIterator;
pub const Type = @import("type.zig").type;
pub const World = @import("world.zig").World;
pub const column = @import("utils.zig").column;
pub const columnOpt = @import("utils.zig").columnOpt;
pub const columnNonQuery = @import("utils.zig").columnNonQuery;
pub const componentCast = @import("utils.zig").componentCast;
pub const meta = @import("meta.zig");

// pub const ECS_HI_COMPONENT_ID = 256;

// NOTE(Anders): This folder is essentially a copy of prime31's original bindings with various
// changes to make it suit Tides of Revival and to make it be a utility layer on top of the
// zig-gamedev bindings.
// https://github.com/prime31/zig-flecs
//
// 💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛
// With his blessing, all this code is now under the same license as Tides of Revival.
// 💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛💜🧡💗💚💛
//
