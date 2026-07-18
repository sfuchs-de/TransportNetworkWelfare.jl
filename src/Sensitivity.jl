function replace_project(project::Project;
                         alpha=project.parameters.alpha,
                         beta=project.parameters.beta,
                         modal=project.modal,
                         congestion=project.congestion)
    parameters = StructuralParameters(
        alpha, beta, project.parameters.sigma, project.parameters.route_curvature)
    return Project(
        project.config_path, project.root, project.name, project.schema_version,
        project.input, parameters, modal, congestion, project.policy,
        project.output_dir, project.sensitivity, project.condition_limit,
        project.tolerance, project.raw,
    )
end

function scaled_congestion(spec::AbstractCongestionSpecification, edge_scale::Real,
                           terminal_scale_factor::Real)
    all(value -> isfinite(value) && value >= 0, (edge_scale, terminal_scale_factor)) ||
        throw(ArgumentError("congestion scale factors must be finite and nonnegative"))
    edge = Dict(mode => lambda*edge_scale for (mode, lambda) in edge_lambdas(spec))
    terminal = Dict(mode => lambda*terminal_scale_factor for
                    (mode, lambda) in terminal_lambdas(spec))
    isempty(edge) && isempty(terminal) && return NoCongestion()
    isempty(terminal) && return EdgeCongestion(edge)
    isempty(edge) && return EndpointTerminalCongestion(terminal, terminal_scale(spec))
    return CompositeCongestion(
        EdgeCongestion(edge), EndpointTerminalCongestion(terminal, terminal_scale(spec)))
end

function replace_lambda(spec::AbstractCongestionSpecification, channel::Symbol, value::Real)
    isfinite(value) && value >= 0 ||
        throw(ArgumentError("congestion elasticity must be finite and nonnegative"))
    edge = copy(edge_lambdas(spec))
    terminal = copy(terminal_lambdas(spec))
    if channel == :lambda_road
        haskey(edge, :road) || throw(ArgumentError("the congestion specification has no road edge channel"))
        edge[:road] = Float64(value)
    elseif channel == :lambda_terminal
        isempty(terminal) && throw(ArgumentError("the congestion specification has no terminal channel"))
        for mode in keys(terminal)
            terminal[mode] = Float64(value)
        end
    else
        throw(ArgumentError("unknown congestion sensitivity channel: $channel"))
    end
    isempty(terminal) && return EdgeCongestion(edge)
    isempty(edge) && return EndpointTerminalCongestion(terminal, terminal_scale(spec))
    return CompositeCongestion(
        EdgeCongestion(edge), EndpointTerminalCongestion(terminal, terminal_scale(spec)))
end

function project_at(project::Project, parameter::Symbol, value::Real)
    if parameter == :alpha
        return replace_project(project; alpha=value)
    elseif parameter == :beta
        return replace_project(project; beta=value)
    elseif parameter == :net_dispersion
        return replace_project(project; beta=-Float64(value)-project.parameters.alpha)
    elseif parameter == :eta
        modal = project.modal isa ChoiceLogsum ? ChoiceLogsum(value) : ComponentCES(value)
        return replace_project(project; modal)
    elseif parameter == :common_congestion
        return replace_project(project; congestion=scaled_congestion(project.congestion, value, value))
    elseif parameter in (:lambda_road, :lambda_terminal)
        return replace_project(project; congestion=replace_lambda(project.congestion, parameter, value))
    end
    throw(ArgumentError("unsupported sensitivity parameter: $parameter"))
end

function model_at(model::TransportModel, project::Project; enforce_branch::Bool=false)
    if enforce_branch
        baseline = model.closures.c
        candidate = AdjointRSUE.coefs(
            project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
        project.parameters.alpha + project.parameters.beta < 0 ||
            throw(ArgumentError("sensitivity point is not net dispersive"))
        sign(candidate.e) == sign(baseline.e) ||
            throw(ArgumentError("sensitivity point leaves the baseline regular branch"))
        abs(candidate.e) >= 0.05 ||
            throw(ArgumentError("sensitivity point is too close to e=0"))
        1+project.parameters.alpha+project.parameters.beta >= 0.05 ||
            throw(ArgumentError("sensitivity point is too close to 1+alpha+beta=0"))
    end
    closures, basis = build_closures(project, model.data, model.basis)
    return TransportModel(project, model.data, basis, closures)
end

function check_sensitivity_branch(model::TransportModel, project::Project)
    baseline = model.closures.c
    candidate = AdjointRSUE.coefs(
        project.parameters.alpha, project.parameters.beta, project.parameters.sigma)
    project.parameters.alpha + project.parameters.beta < 0 ||
        throw(ArgumentError("sensitivity point is not net dispersive"))
    sign(candidate.e) == sign(baseline.e) ||
        throw(ArgumentError("sensitivity point leaves the baseline regular branch"))
    abs(candidate.e) >= 0.05 ||
        throw(ArgumentError("sensitivity point is too close to e=0"))
    1+project.parameters.alpha+project.parameters.beta >= 0.05 ||
        throw(ArgumentError("sensitivity point is too close to 1+alpha+beta=0"))
    return candidate
end

function evaluate_sensitivity_point(model::TransportModel, project::Project)
    c = check_sensitivity_branch(model, project)
    data, basis = model.data, model.basis
    point_basis = merge(basis, (;
        Qz_soft=route_state_matrix(data, basis, c; route=:soft),
        Qz_fixed=basis.Qz_fixed,
    ))
    J0 = AdjointRSUE.assemble_J(data.sx, data.sy, data.mu, data.lam, data.omega, c)
    B = IFTDecomposition.cost_loading_matrix(
        data.N, basis.active_network_edges, data.mu, data.lam, c.σ)
    closure = build_transport_closure(project, data, point_basis, B)
    J = J0+closure.Jc
    condition_J = cond(J)
    condition_within_limit(condition_J, project.condition_limit) ||
        error("sensitivity equilibrium exceeds the condition-number gate")
    condition_within_limit(closure.condition, project.condition_limit) ||
        error("sensitivity transport system exceeds the condition-number gate")
    q = AdjointRSUE.welfare_gradient(data.omega, c)
    adjoint = permutedims(J) \ q

    count = length(basis.policy_pairs)
    selector = sparsevec(basis.policy_pairs, fill(1/count, count), basis.P)
    Kedge = basis.Sagg*selector
    Xdirect = basis.L*(closure.Croute*Kedge)
    !closure.fixed_modal &&
        (Xdirect .+= modal_power(project.modal) .* (selector-basis.L*Kedge))
    if closure.Q == 0
        aggregate_cost = basis.Sagg*selector
        transport_residual = 0.0
    else
        qdirect = closure.A*Xdirect
        qresponse = closure.H \ qdirect
        aggregate_cost = basis.Sagg*(selector+closure.G*qresponse)
        transport_residual = norm(closure.H*qresponse-qdirect, Inf) /
            max(norm(qdirect, Inf), eps())
    end
    mean_directed = dot(adjoint, B*aggregate_cost)
    solve_residual = norm(permutedims(J)*adjoint-q, Inf)/max(norm(q, Inf), eps())
    finite_outputs = all(isfinite, (
        mean_directed, condition_J, closure.condition, solve_residual, transport_residual,
    ))
    verified = finite_outputs &&
        maximum((solve_residual, transport_residual)) <= project.tolerance
    return (;
        mean_directed_elasticity=mean_directed,
        mean_physical_elasticity=project.policy.unit == :directed_arc ? missing : 2mean_directed,
        e=c.e, rho=c.ρ, condition_F=condition_J,
        condition_transport_F=closure.condition,
        solve_residual, transport_residual, verified,
    )
end

"Trace the mean local welfare effect while changing one declared parameter."
function sensitivity_path(model::TransportModel, parameter::Symbol, values)
    rows = NamedTuple[]
    for value in Float64.(values)
        project = project_at(model.project, parameter, value)
        result = evaluate_sensitivity_point(model, project)
        result.verified || error(
            "sensitivity point $(parameter)=$(value) failed its numerical verification gate")
        push!(rows, (;
            parameter=String(parameter), value,
            result.mean_directed_elasticity,
            result.mean_physical_elasticity,
            mean_directed_gain_pct=100*project.policy.shock_fraction*
                result.mean_directed_elasticity,
            result.e, result.rho, result.condition_F, result.condition_transport_F,
            result.verified,
        ))
    end
    return rows
end

function sensitivity_path(project::Project, parameter::Symbol, values)
    return sensitivity_path(build_model(project), parameter, values)
end

function all_sensitivity_paths(model::TransportModel)
    rows = NamedTuple[]
    for parameter in sort!(collect(keys(model.project.sensitivity)); by=String)
        append!(rows, sensitivity_path(model, parameter, model.project.sensitivity[parameter]))
    end
    return rows
end
