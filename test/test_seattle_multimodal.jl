module SeattleMultimodalTests

using Dates
using Test
using TransportNetworkWelfare

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "examples", "seattle_multimodal", "prepare.jl"))
const Builder = SeattleMultimodalBuilder

function write_gtfs_fixture(root)
    write(joinpath(root, "agency.txt"),
          "agency_id,agency_name,agency_url,agency_timezone\n" *
          "A,Test Transit,https://example.com,America/Los_Angeles\n")
    write(joinpath(root, "calendar.txt"),
          "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n" *
          "W,1,1,1,1,1,0,0,20170601,20170630\n")
    write(joinpath(root, "calendar_dates.txt"),
          "service_id,date,exception_type\n")
    write(joinpath(root, "routes.txt"),
          "route_id,agency_id,route_short_name,route_long_name,route_desc,route_type\n" *
          "R,A,R,Rail,,0\n" *
          "B,A,B,Bus,,3\n")
    write(joinpath(root, "trips.txt"),
          "route_id,service_id,trip_id\n" *
          "R,W,R1\n" *
          "B,W,B1\n")
    write(joinpath(root, "stops.txt"),
          "stop_id,stop_name,stop_lat,stop_lon,location_type\n" *
          "S1,One,47.6000,-122.3300,0\n" *
          "S2,Two,47.6050,-122.3200,0\n" *
          "S3,Three,47.6100,-122.3100,0\n")
    write(joinpath(root, "stop_times.txt"),
          "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n" *
          "R1,08:00:00,08:00:00,S1,1\n" *
          "R1,08:05:00,08:05:30,S2,2\n" *
          "R1,08:10:00,08:10:00,S3,3\n" *
          "B1,09:00:00,09:00:00,S3,1\n" *
          "B1,09:05:00,09:05:30,S2,2\n" *
          "B1,09:10:00,09:10:00,S1,3\n")
end

@testset "Census parser and grid aggregation" begin
    response = """
    [["NAME","B08301_001E","B08301_010E","state","county","tract","block group"],
     ["Block Group 1, King County, Washington","100","25","53","033","000100","1"],
     ["Block Group 2, King County, Washington","200","20","53","033","000200","1"]]
    """
    mktempdir() do directory
        response_path = joinpath(directory, "acs.json")
        write(response_path, response)
        acs = Builder.read_acs_commute_modes(response_path)
        @test length(acs.estimates) == 2
        @test acs.estimates["530330001001"].transit == 25

        crosswalk = joinpath(directory, "crosswalk.csv")
        write(crosswalk,
            "OBJECTID,POINT_X,POINT_Y,OBJECTID_1,GEOID,AREA,PERCENTAGE\n" *
            "-1,0,0,1,530330001001,1,100\n" *
            "-1,0,0,2,530330002001,1,100\n")
        aggregated = Builder.aggregate_transit_shares(
            crosswalk, acs, [1, 2])
        @test aggregated.shares ≈ [0.25, 0.10] atol=1e-12 rtol=0
        @test aggregated.area_coverage == 1
    end
end

@testset "GTFS mapping and model-consistent commuter routing" begin
    nodes = (
        ids=[1, 2, 3],
        longitude=[-122.3300, -122.3200, -122.3100],
        latitude=[47.6000, 47.6050, 47.6100],
    )
    road_arcs = [
        (; origin=1, destination=2, mode=:road, cost=300.0,
           service_count=1, route_count=1),
        (; origin=2, destination=1, mode=:road, cost=300.0,
           service_count=1, route_count=1),
        (; origin=2, destination=3, mode=:road, cost=300.0,
           service_count=1, route_count=1),
        (; origin=3, destination=2, mode=:road, cost=300.0,
           service_count=1, route_count=1),
    ]
    commute = [
        10.0 4.0 2.0
        3.0 8.0 5.0
        1.0 6.0 9.0
    ]
    mktempdir() do directory
        write_gtfs_fixture(directory)
        gtfs = Builder.read_gtfs_network(
            directory, nodes; service_date=Date(2017, 6, 14),
            max_snap_km=0.2, verify=false)
        @test gtfs.active_trips == 2
        @test gtfs.mapped_stops == 3
        @test Set(arc.mode for arc in gtfs.arcs) == Set((:bus, :rail))

        routed = Builder.route_commuters(
            commute, [0.5, 0.4, 0.3], road_arcs, gtfs.arcs;
            road_interiority_share=1e-8)
        @test routed.balance_error < 1e-12
        @test routed.fallback_to_road == 0
        @test routed.routed_transit ≈ routed.requested_transit atol=1e-12 rtol=0
        @test all(get(routed.flows, (arc.origin, arc.destination, :road), 0.0) > 0
                  for arc in road_arcs)

        output = joinpath(directory, "output")
        data = joinpath(output, "data")
        mkpath(data)
        Builder.write_nodes(joinpath(data, "nodes.csv"), nodes, routed)
        Builder.write_edge_modes(
            joinpath(data, "edge_modes.csv"), routed, road_arcs, gtfs.arcs)
        modes = sort!(unique(key[3] for key in keys(routed.flows));
                      by=mode -> (mode == :road ? "" : String(mode)))
        Builder.write_config(joinpath(output, "config.toml"), modes; eta=1.4)
        project = load_project(joinpath(output, "config.toml"))
        report = validate(project)
        @test report.valid
        @test report.stock_disagreement < 1e-12
        @test report.modes == ["road", "bus", "rail"]
    end
end

@testset "Seattle sources fail closed" begin
    withenv("CENSUS_API_KEY" => "") do
        @test_throws ArgumentError Builder.fetch_acs_commute_modes(
            joinpath(mktempdir(), "acs.json"))
    end
    mktempdir() do directory
        @test_throws ArgumentError Builder.verify_gtfs_sources(directory)
    end
end

@testset "Optional pinned Seattle integration" begin
    aa_root = get(ENV, "AA_REPLICATION_ROOT", "")
    gtfs_root = get(ENV, "SEATTLE_GTFS_2017_ROOT", "")
    acs_path = get(ENV, "SEATTLE_ACS_2017_PATH", "")
    if isempty(aa_root) || isempty(gtfs_root) || isempty(acs_path)
        @test_skip "set AA_REPLICATION_ROOT, SEATTLE_GTFS_2017_ROOT, and SEATTLE_ACS_2017_PATH"
    else
        mktempdir() do output
            result = Builder.build_example(
                aa_root, gtfs_root, acs_path, output; eta=1.099)
            @test result["nodes"] == 217
            @test result["road_arcs_available"] == 1_384
            @test result["road_links_available"] == 692
            @test result["routing"]["flow_balance_error"] < 1e-8
            @test result["historical_aadt_stock_disagreement"] > 0.1
        end
    end
end

end # module
