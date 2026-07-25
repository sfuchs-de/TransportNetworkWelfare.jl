module SeattleSourceTests

using SHA
using Test
using ZipFile

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "examples", "seattle_multimodal", "download_sources.jl"))
const Downloader = SeattleSourceDownloader

function write_zip(path, files)
    writer = ZipFile.Writer(path)
    try
        for (name, contents) in files
            file = ZipFile.addfile(writer, name)
            write(file, contents)
        end
    finally
        close(writer)
    end
    return path
end

@testset "Safe and verified source extraction" begin
    mktempdir() do directory
        archive = write_zip(joinpath(directory, "source.zip"), [
            "folder/input.txt" => "verified\n",
        ])
        output = joinpath(directory, "output")
        paths = Downloader.extract_zip(archive, output)
        @test length(paths) == 1
        @test read(only(paths), String) == "verified\n"

        malicious = write_zip(joinpath(directory, "malicious.zip"), [
            "../escape.txt" => "not allowed",
        ])
        @test_throws ArgumentError Downloader.extract_zip(
            malicious, joinpath(directory, "blocked"))
        @test !isfile(joinpath(directory, "escape.txt"))
    end
end

@testset "Historical GTFS count and hash contract" begin
    mktempdir() do directory
        rows = Dict(
            "agency.txt" => "agency_id\nA\n",
            "routes.txt" => "route_id\nR\n",
            "stops.txt" => "stop_id\nS\n",
            "trips.txt" => "trip_id\nT\n",
            "shapes.txt" => "shape_id\nH\n",
            "stop_times.txt" => "trip_id\nT\n",
        )
        files = Dict{String,String}()
        for (name, contents) in rows
            path = joinpath(directory, name)
            write(path, contents)
            files[name] = bytes2hex(open(SHA.sha1, path))
        end
        specification = Dict{String,Any}(
            "files" => files,
            "expected_agencies" => 1,
            "expected_routes" => 1,
            "expected_stops" => 1,
            "expected_trips" => 1,
            "expected_shapes" => 1,
            "expected_stop_times" => 1,
        )
        report = Downloader.verify_gtfs(directory, specification)
        @test report.counts["routes"] == 1
        write(joinpath(directory, "routes.txt"), "route_id\nR\nR2\n")
        @test_throws ArgumentError Downloader.verify_gtfs(directory, specification)
    end
end

@testset "Historical GTFS acquisition fails closed" begin
    mktempdir() do directory
        specification = Dict{String,Any}(
            "feed_version_sha1" => repeat("a", 40),
            "download_endpoint" => "https://example.invalid/archive.zip",
        )
        withenv(
            "TRANSITLAND_API_KEY" => "",
            "SEATTLE_GTFS_2017_ARCHIVE" => "",
        ) do
            @test_throws ArgumentError Downloader.acquire_gtfs(
                directory, specification; refresh=false)
        end
    end
end

@testset "Metro route-activity parser" begin
    rows = Downloader.parse_metro_route_activity(
        "Appendix G: Route-level Ridership and Hours\n" *
        join(("$route    2,500    2,400    -100    65    66    1\n"
              for route in 1:190)))
    @test length(rows) == 190
end

end
