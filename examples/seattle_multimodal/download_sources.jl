#!/usr/bin/env julia

module SeattleSourceDownloader

using Dates
using Downloads
using SHA
using TOML
using TransportNetworkWelfare
using ZipFile

const EXAMPLE_ROOT = @__DIR__
const SOURCE_MANIFEST = joinpath(EXAMPLE_ROOT, "sources.toml")

sha256_file(path::AbstractString) = bytes2hex(open(SHA.sha256, path))
sha1_file(path::AbstractString) = bytes2hex(open(SHA.sha1, path))

function option(args, name; default=nothing)
    index = findfirst(==(name), args)
    index === nothing && return default
    index < length(args) || throw(ArgumentError("$name requires a value"))
    return args[index+1]
end

function verified_download(url::AbstractString, destination::AbstractString;
                           algorithm::Symbol=:sha256, expected::AbstractString,
                           headers=Pair{String,String}[], refresh::Bool=false)
    hash_file = algorithm == :sha256 ? sha256_file :
                algorithm == :sha1 ? sha1_file :
                throw(ArgumentError("unsupported hash algorithm $algorithm"))
    if isfile(destination) && !refresh
        observed = hash_file(destination)
        observed == lowercase(expected) || throw(ArgumentError(
            "cached source hash mismatch for $(basename(destination)): " *
            "expected $expected, observed $observed"))
        return destination
    end
    mkpath(dirname(destination))
    temporary = tempname(dirname(destination))
    try
        try
            Downloads.download(url, temporary; headers)
        catch
            throw(ArgumentError(
                "source download failed for $(replace(
                    url,
                    r"[?&](api_?key|apikey|access_token)=[^&]+" =>
                        s"\1=REDACTED",
                ))"))
        end
        observed = hash_file(temporary)
        observed == lowercase(expected) || throw(ArgumentError(
            "downloaded source hash mismatch for $(basename(destination)): " *
            "expected $expected, observed $observed"))
        mv(temporary, destination; force=true)
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
    return destination
end

function verified_copy(source::AbstractString, destination::AbstractString;
                       algorithm::Symbol=:sha1, expected::AbstractString,
                       refresh::Bool=false)
    isfile(source) || throw(ArgumentError("source archive not found: $source"))
    hash_file = algorithm == :sha256 ? sha256_file : sha1_file
    observed = hash_file(source)
    observed == lowercase(expected) || throw(ArgumentError(
        "provided archive hash mismatch: expected $expected, observed $observed"))
    if isfile(destination) && !refresh
        hash_file(destination) == lowercase(expected) || throw(ArgumentError(
            "cached archive hash mismatch: $destination"))
        return destination
    end
    mkpath(dirname(destination))
    cp(source, destination; force=refresh)
    return destination
end

function safe_member_path(destination::AbstractString, member::AbstractString)
    normalized = normpath(member)
    isabspath(normalized) && throw(ArgumentError("ZIP contains an absolute path"))
    startswith(normalized, "..") &&
        throw(ArgumentError("ZIP contains a path outside its extraction root"))
    output = normpath(joinpath(destination, normalized))
    startswith(output, normpath(destination) * Base.Filesystem.path_separator) ||
        throw(ArgumentError("ZIP member escapes its extraction root"))
    return output
end

function extract_zip(archive::AbstractString, destination::AbstractString;
                     keep::Function=member -> true)
    mkpath(destination)
    reader = ZipFile.Reader(archive)
    extracted = String[]
    try
        for file in reader.files
            name = replace(file.name, '\\' => '/')
            keep(name) || continue
            endswith(name, "/") && continue
            output = safe_member_path(destination, name)
            mkpath(dirname(output))
            open(output, "w") do io
                write(io, read(file))
            end
            push!(extracted, output)
        end
    finally
        close(reader)
    end
    isempty(extracted) && throw(ArgumentError(
        "no requested files were found in $(basename(archive))"))
    return sort!(extracted)
end

function count_csv_records(path::AbstractString)
    lines = 0
    open(path) do io
        for _ in eachline(io)
            lines += 1
        end
    end
    lines > 0 || throw(ArgumentError("source table is empty: $path"))
    return lines-1
end

function verify_gtfs(root::AbstractString, specification)
    expected_files = Dict{String,String}(specification["files"])
    observed = Dict{String,String}()
    for (name, expected) in expected_files
        path = joinpath(root, name)
        isfile(path) || throw(ArgumentError("historical GTFS is missing $name"))
        observed[name] = sha1_file(path)
        observed[name] == expected || throw(ArgumentError(
            "historical GTFS $name hash mismatch"))
    end
    counts = Dict(
        "agencies" => count_csv_records(joinpath(root, "agency.txt")),
        "routes" => count_csv_records(joinpath(root, "routes.txt")),
        "stops" => count_csv_records(joinpath(root, "stops.txt")),
        "trips" => count_csv_records(joinpath(root, "trips.txt")),
        "shapes" => count_csv_records(joinpath(root, "shapes.txt")),
        "stop_times" => count_csv_records(joinpath(root, "stop_times.txt")),
    )
    for (name, expected_name) in (
        "agencies" => "expected_agencies",
        "routes" => "expected_routes",
        "stops" => "expected_stops",
        "trips" => "expected_trips",
        "shapes" => "expected_shapes",
        "stop_times" => "expected_stop_times",
    )
        counts[name] == Int(specification[expected_name]) ||
            throw(ArgumentError(
                "historical GTFS $name count mismatch: expected " *
                "$(specification[expected_name]), observed $(counts[name])"))
    end
    return (; hashes=observed, counts)
end

function acquire_aa(data_root, specification; refresh)
    directory = joinpath(data_root, "raw", "allen_arkolakis")
    archive = joinpath(directory, "RESTUD26454_Replication.zip")
    supplied = strip(get(ENV, "AA_REPLICATION_ARCHIVE", ""))
    if isempty(supplied)
        verified_download(
            String(specification["url"]), archive;
            expected=String(specification["archive_sha256"]), refresh)
    else
        verified_copy(
            supplied, archive; algorithm=:sha256,
            expected=String(specification["archive_sha256"]), refresh)
    end
    selected = Set((
        "ReplicationFinal/counterfactuals/seattle/node_lr_lf_seattle.csv",
        "ReplicationFinal/counterfactuals/seattle/sparse_adjmat_seattle.csv",
        "ReplicationFinal/counterfactuals/seattle/sparse_commute_seattle.csv",
        "ReplicationFinal/data/seattle/derived/grid_seattle_area_xwalk.txt",
    ))
    extracted_root = joinpath(directory, "extracted")
    paths = extract_zip(archive, extracted_root; keep=name -> name in selected)
    return Dict(
        "archive" => archive,
        "archive_sha256" => sha256_file(archive),
        "root" => joinpath(extracted_root, "ReplicationFinal"),
        "files" => Dict(relpath(path, extracted_root) => sha256_file(path) for path in paths),
    )
end

function acquire_acs(data_root, specification; refresh)
    key = strip(get(ENV, "CENSUS_API_KEY", ""))
    isempty(key) && throw(ArgumentError(
        "CENSUS_API_KEY is required to acquire the 2017 ACS response"))
    path = joinpath(data_root, "raw", "acs", "acs_2017_king_county_b08301.json")
    endpoint = String(specification["endpoint_without_key"])
    if isfile(path) && !refresh
        return Dict("path" => path, "sha256" => sha256_file(path))
    end
    mkpath(dirname(path))
    temporary = tempname(dirname(path))
    try
        try
            Downloads.download(endpoint * "&key=" * key, temporary)
        catch
            throw(ArgumentError(
                "the 2017 ACS request failed; the Census API key is not shown"))
        end
        occursin("B08301_010E", read(temporary, String)) ||
            throw(ArgumentError("the ACS response does not contain B08301_010E"))
        mv(temporary, path; force=true)
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
    return Dict("path" => path, "sha256" => sha256_file(path))
end

function acquire_gtfs(data_root, specification; refresh)
    directory = joinpath(data_root, "raw", "king_county_gtfs_2017")
    archive = joinpath(directory, "$(specification["feed_version_sha1"]).zip")
    supplied = strip(get(ENV, "SEATTLE_GTFS_2017_ARCHIVE", ""))
    if !isempty(supplied)
        verified_copy(supplied, archive; expected=String(
            specification["feed_version_sha1"]), refresh)
    elseif !isfile(archive) || refresh
        key = strip(get(ENV, "TRANSITLAND_API_KEY", ""))
        isempty(key) && throw(ArgumentError(
            "exact 2017 GTFS unavailable: set TRANSITLAND_API_KEY with archive " *
            "access or SEATTLE_GTFS_2017_ARCHIVE"))
        verified_download(
            String(specification["download_endpoint"]), archive;
            algorithm=:sha1, expected=String(specification["feed_version_sha1"]),
            headers=["apikey" => key], refresh)
    end
    sha1_file(archive) == String(specification["feed_version_sha1"]) ||
        throw(ArgumentError("cached historical GTFS archive hash mismatch"))
    extracted = joinpath(directory, "extracted")
    extract_zip(archive, extracted)
    verification = verify_gtfs(extracted, specification)
    return Dict(
        "archive" => archive,
        "archive_sha1" => sha1_file(archive),
        "root" => extracted,
        "files" => verification.hashes,
        "counts" => verification.counts,
    )
end

function parse_metro_route_activity(text::AbstractString)
    pages = split(text, '\f')
    relevant = filter(page ->
        occursin("Route-level Ridership and Hours", page), pages)
    isempty(relevant) && throw(ArgumentError(
        "Metro report does not contain Appendix G route-activity tables"))
    pattern = r"^\s*([0-9]+(?:EX)?|[A-F] Line)\s+(<?[0-9,]+)\s+(<?[0-9,]+)\s+(-?[0-9,]+)\s+([0-9,]+)\s+([0-9,]+)\s+(-?[0-9,]+)\s*$"
    rows = NamedTuple[]
    seen = Set{String}()
    integer(value) = parse(Int, replace(String(value), "," => ""))
    for page in relevant, line in eachline(IOBuffer(page))
        match_result = match(pattern, line)
        match_result === nothing && continue
        route, rides_2015, rides_2016, change_rides,
            hours_2015, hours_2016, change_hours = match_result.captures
        route in seen && throw(ArgumentError(
            "Metro route-activity appendix contains duplicate route $route"))
        push!(seen, route)
        censored = startswith(rides_2016, "<")
        push!(rows, (;
            route,
            weekday_rides_fall_2015_reported=rides_2015,
            weekday_rides_fall_2016_reported=rides_2016,
            weekday_rides_fall_2016=censored ? missing : integer(rides_2016),
            weekday_rides_fall_2016_censored_below_50=censored,
            change_in_rides=integer(change_rides),
            weekday_platform_hours_fall_2015=integer(hours_2015),
            weekday_platform_hours_fall_2016=integer(hours_2016),
            change_in_platform_hours=integer(change_hours),
        ))
    end
    length(rows) >= 190 || throw(ArgumentError(
        "Metro route-activity extraction found only $(length(rows)) rows"))
    sort!(rows; by=row -> row.route)
    return rows
end

function extract_metro_route_activity(pdf::AbstractString,
                                      destination::AbstractString)
    executable = Sys.which("pdftotext")
    executable === nothing && throw(ArgumentError(
        "pdftotext is required to extract the Metro external-validation table"))
    temporary = tempname()
    try
        run(`$executable -layout $pdf $temporary`)
        rows = parse_metro_route_activity(read(temporary, String))
        TransportNetworkWelfare.write_table(destination, rows)
        version_output = IOBuffer()
        run(pipeline(
            `$executable -v`; stdout=version_output, stderr=version_output))
        version = strip(String(take!(version_output)))
        return (; path=destination, rows=length(rows),
                sha256=sha256_file(destination), pdftotext_version=version)
    finally
        isfile(temporary) && rm(temporary; force=true)
    end
end

function acquire_pdf(data_root, specification; refresh)
    path = verified_download(
        String(specification["url"]),
        joinpath(data_root, "raw", "metro_validation", "2017-system-evaluation.pdf");
        expected=String(specification["sha256"]), refresh)
    derived = joinpath(
        data_root, "derived", "metro_route_activity_fall_2016.csv")
    activity = extract_metro_route_activity(path, derived)
    return Dict(
        "path" => path,
        "sha256" => sha256_file(path),
        "route_activity_path" => activity.path,
        "route_activity_sha256" => activity.sha256,
        "route_activity_rows" => activity.rows,
        "pdftotext_version" => activity.pdftotext_version,
    )
end

function acquire_geography(data_root, specification; refresh)
    output = Dict{String,Any}()
    for name in ("place", "area_water", "county")
        item = specification[name]
        directory = joinpath(data_root, "raw", "geography", name)
        archive = verified_download(
            String(item["url"]), joinpath(directory, basename(String(item["url"])));
            expected=String(item["sha256"]), refresh)
        extracted = joinpath(directory, "extracted")
        paths = extract_zip(archive, extracted)
        output[name] = Dict(
            "archive" => archive,
            "sha256" => sha256_file(archive),
            "root" => extracted,
            "files" => basename.(paths),
        )
    end
    return output
end

function write_acquisition_manifest(root, manifest_path, acquired;
                                    complete::Bool, failure_stage=missing,
                                    failure=missing)
    manifest = Dict{String,Any}(
        "schema_version" => 1,
        "vintage" => 2017,
        "retrieved_at_utc" => string(now(UTC)),
        "source_manifest_sha256" => sha256_file(manifest_path),
        "data_root" => root,
        "sources" => acquired,
        "credentials_recorded" => false,
        "complete" => complete,
        "failure_stage" => failure_stage,
        "failure" => failure,
    )
    path = joinpath(root, "acquisition_manifest.json")
    open(path, "w") do io
        println(io, TransportNetworkWelfare.json_value(manifest))
    end
    return path
end

function acquire(data_root::AbstractString; refresh::Bool=false,
                 manifest_path::AbstractString=SOURCE_MANIFEST)
    root = abspath(data_root)
    mkpath(root)
    sources = TOML.parsefile(manifest_path)
    acquired = Dict{String,Any}()
    stages = (
        "allen_arkolakis" => () ->
            acquire_aa(root, sources["allen_arkolakis_replication"]; refresh),
        "metro_validation" => () ->
            acquire_pdf(root, sources["king_county_metro_2017_system_evaluation"]; refresh),
        "geography" => () ->
            acquire_geography(root, sources["census_tiger_2017"]; refresh),
        "acs" => () -> acquire_acs(root, sources["acs_2017"]; refresh),
        "gtfs" => () -> acquire_gtfs(root, sources["king_county_gtfs_2017"]; refresh),
    )
    for (stage, operation) in stages
        try
            acquired[stage] = operation()
            write_acquisition_manifest(
                root, manifest_path, acquired; complete=false)
        catch error
            message = sprint(showerror, error)
            write_acquisition_manifest(
                root, manifest_path, acquired; complete=false,
                failure_stage=stage, failure=message)
            rethrow()
        end
    end
    path = write_acquisition_manifest(
        root, manifest_path, acquired; complete=true)
    return (; path, manifest=acquired)
end

function main(args=ARGS)
    data_root = option(args, "--data-root";
        default=get(ENV, "SEATTLE_TRANSIT_DATA_ROOT", ""))
    isempty(strip(String(data_root))) && throw(ArgumentError(
        "set SEATTLE_TRANSIT_DATA_ROOT or pass --data-root"))
    result = acquire(String(data_root); refresh="--refresh" in args)
    println(TransportNetworkWelfare.json_value(Dict(
        "status" => "ok", "manifest" => result.path)))
    return 0
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    try
        exit(SeattleSourceDownloader.main())
    catch error
        showerror(stderr, error)
        println(stderr)
        exit(1)
    end
end
