module SeattleImpactTests

using Test

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "examples", "seattle_multimodal", "build_impacts.jl"))
const Impacts = SeattleTransitImpacts

function policy_rows(mode, multiplier)
    return [
        (edge_id="1_2", physical_link_id="1_2", origin="1", destination="2",
         mode=String(mode), hulten=0.10multiplier, realized_F=0.09multiplier,
         primitive_F=0.08multiplier,
         primitive_pass_through=0.01multiplier),
        (edge_id="2_1", physical_link_id="1_2", origin="2", destination="1",
         mode=String(mode), hulten=0.20multiplier, realized_F=0.18multiplier,
         primitive_F=0.16multiplier,
         primitive_pass_through=0.02multiplier),
        (edge_id="2_3", physical_link_id="2_3", origin="2", destination="3",
         mode=String(mode), hulten=0.05multiplier, realized_F=0.06multiplier,
         primitive_F=0.07multiplier,
         primitive_pass_through=-0.01multiplier),
    ]
end

@testset "Seattle corridor aggregation" begin
    bus = policy_rows(:bus, 1.0)
    corridors = Impacts.aggregate_corridors(bus; mode="bus")
    @test length(corridors) == 2
    reciprocal = only(row for row in corridors if row.corridor_id == "1_2")
    @test reciprocal.complete_reciprocal
    @test reciprocal.directions == 2
    @test reciprocal.hulten ≈ 0.30
    @test reciprocal.primitive_F ≈ 0.24
    one_way = only(row for row in corridors if row.corridor_id == "2_3")
    @test !one_way.complete_reciprocal
    @test one_way.directions == 1

    modes = Dict(
        :bus => bus,
        :rail => policy_rows(:rail, 0.5),
        :ferry => policy_rows(:ferry, 0.25),
    )
    combined = Impacts.aggregate_all_transit(modes)
    @test length(combined) == 3
    forward = only(row for row in combined if row.edge_id == "1_2")
    @test forward.hulten ≈ 0.175
    @test forward.primitive_F ≈ 0.14
    all_corridors = Impacts.aggregate_corridors(combined; mode="all_transit")
    @test length(all_corridors) == 2
end

@testset "Top-union and exact-build gates" begin
    rows = Impacts.aggregate_corridors(policy_rows(:bus, 1.0); mode="bus")
    @test length(Impacts.top_union(rows, 1)) >= 1
    mktempdir() do directory
        @test_throws ArgumentError Impacts.require_exact_build(directory)
        write(joinpath(directory, "build_manifest.json"),
              "{\"eta\":1.099,\"feed\":\"ad172e653aa881557a5f3cb84f2ace6819308600\"}\n")
        @test endswith(Impacts.require_exact_build(directory), "build_manifest.json")
    end
end

@testset "Metro route-activity comparison" begin
    mktempdir() do directory
        bundles = joinpath(directory, "route_bundles.csv")
        write(bundles,
              "bundle_id,edge_id,mode,weight,route_id,route_name,agency_id,origin,destination,service_count\n" *
              "route:r1,1_2,bus,1,r1,1,A,1,2,10\n" *
              "route:r1,2_3,bus,1,r1,1,A,2,3,8\n" *
              "route:r2,1_3,bus,1,r2,2,A,1,3,6\n" *
              "route:rail,1_2,rail,1,rail,L1,B,1,2,4\n")
        metro = joinpath(directory, "metro.csv")
        write(metro,
              "route,weekday_rides_fall_2016,weekday_rides_fall_2016_censored_below_50\n" *
              "1,2400,false\n" *
              "2,5600,false\n")
        report = Impacts.compare_route_activity(bundles, metro)
        @test length(report.comparison) == 2
        @test report.summary.metro_routes_matched == 2
        @test report.summary.metro_route_coverage == 1.0
        route_one = only(row for row in report.comparison if row.route_name == "1")
        @test route_one.scheduled_edge_traversals == 18
        @test route_one.metro_weekday_rides_fall_2016 == 2400
    end
end

end
