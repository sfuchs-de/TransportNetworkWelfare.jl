#!/usr/bin/env julia

using Printf

const EXAMPLE_ROOT = @__DIR__
const DATA_ROOT = joinpath(EXAMPLE_ROOT, "data")
const GRID_SIZE = 5
const TRANSIT_ROW = 3

node_id(row, column) = @sprintf("r%dc%d", row, column)
terminal_id(row, column) = "station_" * node_id(row, column)

function node_activity(row, column)
    on_spine = row == TRANSIT_ROW
    on_cross = column == 3
    at_center = on_spine && on_cross
    eastward_gradient = 0.10 * (column - 1)
    labor = 1.0 + (on_spine ? 1.0 : 0.0) + (on_cross ? 0.35 : 0.0) +
            (at_center ? 1.65 : 0.0) + eastward_gradient
    income = 1.0 + (on_spine ? 1.4 : 0.0) + (on_cross ? 0.45 : 0.0) +
             (at_center ? 2.15 : 0.0) + 1.4 * eastward_gradient
    return labor, income
end

function road_flow(kind::Symbol, row, column)
    local_gradient = 0.00004 * (GRID_SIZE * (row - 1) + column)
    if kind == :horizontal
        distance = abs(column + 0.5 - 3.0)
        return 0.0035 + (row == TRANSIT_ROW ? 0.0055 : 0.0) +
               (distance < 1.0 ? 0.0010 : 0.0) + local_gradient
    end
    distance = abs(row + 0.5 - 3.0)
    return 0.0035 + (column == 3 ? 0.0030 : 0.0) +
           (distance < 1.0 ? 0.0008 : 0.0) + local_gradient
end

function transit_flow(column)
    distance = abs(column + 0.5 - 3.0)
    return 0.0105 + (distance < 1.0 ? 0.0025 : 0.0) + 0.0002 * column
end

function write_nodes()
    path = joinpath(DATA_ROOT, "nodes.csv")
    open(path, "w") do io
        println(io, "node_id,labor,income,longitude,latitude")
        for row in 1:GRID_SIZE, column in 1:GRID_SIZE
            labor, income = node_activity(row, column)
            @printf(io, "%s,%.6f,%.6f,%.1f,%.1f\n",
                    node_id(row, column), labor, income,
                    Float64(column), Float64(GRID_SIZE + 1 - row))
        end
    end
    return path
end

function edge_row(io, edge_id, physical_id, origin, destination, mode, flow;
                  origin_terminal="", destination_terminal="")
    @printf(io, "%s,%s,%s,%s,%s,%.8f,%s,%s\n",
            edge_id, physical_id, origin, destination, mode, flow,
            origin_terminal, destination_terminal)
end

function write_edges()
    path = joinpath(DATA_ROOT, "edge_modes.csv")
    open(path, "w") do io
        println(io,
            "edge_id,physical_link_id,origin,destination,mode,flow," *
            "origin_terminal_id,destination_terminal_id")

        for row in 1:GRID_SIZE, column in 1:(GRID_SIZE - 1)
            west = node_id(row, column)
            east = node_id(row, column + 1)
            link = @sprintf("H_r%d_c%d", row, column)
            eastward = link * "_E"
            westward = link * "_W"
            road = road_flow(:horizontal, row, column)
            edge_row(io, eastward, link, west, east, "road", road)
            edge_row(io, westward, link, east, west, "road", road)
            if row == TRANSIT_ROW
                transit = transit_flow(column)
                edge_row(io, eastward, link, west, east, "transit", transit;
                    origin_terminal=terminal_id(row, column),
                    destination_terminal=terminal_id(row, column + 1))
                edge_row(io, westward, link, east, west, "transit", transit;
                    origin_terminal=terminal_id(row, column + 1),
                    destination_terminal=terminal_id(row, column))
            end
        end

        for row in 1:(GRID_SIZE - 1), column in 1:GRID_SIZE
            north = node_id(row, column)
            south = node_id(row + 1, column)
            link = @sprintf("V_r%d_c%d", row, column)
            southward = link * "_S"
            northward = link * "_N"
            road = road_flow(:vertical, row, column)
            edge_row(io, southward, link, north, south, "road", road)
            edge_row(io, northward, link, south, north, "road", road)
        end
    end
    return path
end

mkpath(DATA_ROOT)
println(write_nodes())
println(write_edges())
