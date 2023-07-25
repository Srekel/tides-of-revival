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

// NOTE(Anders): This folder is essentially a copy of prime31's original bindings with various
// changes to make it suit Tides of Revival and to make it be a utility layer on top of the
// zig-gamedev bindings.
// https://github.com/prime31/zig-flecs
//
// I consider my changes to this to be in the Public Domain but the original code is MIT.
// (onus is on you to figure out which is which and also to do what you want with this :) )
//
// Prime31's original license follows:

// MIT License

// Copyright (c) 2022 Colton Franklin

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
