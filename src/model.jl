import Base: copy, reset


abstract type DynamicsType end
abstract type Continuous <: DynamicsType end
abstract type Discrete <: DynamicsType end
abstract type Model{D<:DynamicsType} end

"""
$(TYPEDEF)

Dynamics model

Holds all information required to uniquely describe a dynamic system, including
a general nonlinear dynamics function of the form `ẋ = f(x,u)`, where x ∈ ℜⁿ are
the states and u ∈ ℜᵐ are the controls.

Dynamics function `Model.f` should be in the following forms:
    'f!(ẋ,x,u)' and modify ẋ in place
"""
struct AnalyticalModel{D} <:Model{D}
    f::Function   # dynamics f(ẋ,x,u)
    ∇f::Function  # dynamics jacobian
    n::Int        # number of states
    m::Int        # number of controls
    params::NamedTuple
    evals::Vector{Int}
    info::Dict{Symbol,Any}

    """ $(SIGNATURES)
    Create a dynamics model given a dynamics function and Jacobian, with n states and m controls.

    Dynamics function should be of the form
        f(ẋ,x,u,p) for Continuous models, where ẋ is the state derivative
        f(ẋ,x,u,p,dt) for Discrete models, where ẋ is the state at the next time step
        and x is the state vector, u is the control input vector, and p is a `NamedTuple` of static parameters (mass, gravity, etc.)

    Optionally pass in a dictionary `d` with model information.
    `check_functions` option runs verification checks on the dynamics function and Jacobian to make sure they have the correct forms.
    """
    function AnalyticalModel{D}(f::Function, ∇f::Function, n::Int64, m::Int64,
            p::NamedTuple=NamedTuple(), d::Dict{Symbol,Any}=Dict{Symbol,Any}();
            check_functions::Bool=false) where D<:DynamicsType
        d[:evals] = 0
        evals = [0,0]
        if check_functions
            # Make dynamics inplace
            if is_inplace_dynamics(f,n,m)
                f! = f
            else
                f! = wrap_inplace(f)
            end
            ∇f! = _check_jacobian(D,f,∇f,n,m)
            new{D}(f!,∇f!,n,m,p,evals,d)
        else
            new{D}(f,∇f,n,m,p,evals,d)
        end
    end
end

function AnalyticalModel{D}(f::Function, n::Int64, m::Int64, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) where D<:DynamicsType
    p = NamedTuple()
    ∇f, = generate_jacobian(D,f,n,m)
    AnalyticalModel{D}(f,∇f,n,m,p,d)
end

function AnalyticalModel{D}(f::Function, n::Int64, m::Int64, p::NamedTuple, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) where D<:DynamicsType
    f_p(ẋ,x,u) = f(ẋ,x,u,p)
    f_p(ẋ,x,u,p) = f(ẋ,x,u,p)
    ∇f, = generate_jacobian(D,f_p,n,m)
    AnalyticalModel{D}(f_p,∇f,n,m,p,d)
end


""" $(SIGNATURES)
Create a dynamics model, using ForwardDiff to generate the dynamics jacobian, with parameters
Dynamics function passes in parameters:
    f(ẋ,x,u,p)
    where p in NamedTuple of parameters
"""
Model(f::Function, n::Int64, m::Int64, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) =
    AnalyticalModel{Continuous}(f,n,m,d)

""" $(SIGNATURES)
Create a dynamics model, using ForwardDiff to generate the dynamics jacobian, without parameters
Dynamics function of the form:
    f(ẋ,x,u)
"""
Model(f::Function, n::Int64, m::Int64, p::NamedTuple, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) =
    AnalyticalModel{Continuous}(f,n,m,p,d)

""" $(SIGNATURES)
Create a dynamics model with an analytical Jacobian, with parameters
Dynamics functions pass in parameters:
    f(ẋ,x,u,p)
    ∇f(Z,x,u,p)
    where p in NamedTuple of parameters
"""
Model(f::Function, ∇f::Function, n::Int64, m::Int64, p::NamedTuple, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) = begin
    f_p(ẋ,x,u) = f(ẋ,x,u,p)
    f_p(ẋ,x,u,p) = f(ẋ,x,u,p)
    ∇f_p(Z,x,u) = ∇f(Z,x,u,p)
    AnalyticalModel{Continuous}(f_p,∇f_p,n,m,p,d, check_functions=true); end

""" $(SIGNATURES)
Create a dynamics model with an analytical Jacobian, without parameters
Dynamics functions pass of the form:
    f(ẋ,x,u)
    ∇f(Z,x,u)
"""
Model(f::Function, ∇f::Function, n::Int64, m::Int64, d::Dict{Symbol,Any}=Dict{Symbol,Any}()) = begin
    p = NamedTuple()
    AnalyticalModel{Continuous}(f,∇f,n,m,p,d, check_functions=true); end

function add_infeasible_controls(m::Model{D}) where D<:Discrete
    part_u = create_partition((model.m,model.n),(:u,:inf))
    function f(ẋ,x,u)
        model.f(ẋ,x,u[ui.u])
        ẋ .+= u[ui.inf]
    end
    AnalyticalModel(f,model.n,model.m+model.n,model.params,model.d)
end


""" $(SIGNATURES) Evaluate the dynamics at state `x` and control `x`
Keeps track of the number of evaluations
"""
function evaluate!(ẋ::AbstractVector,model::Model{Continuous},x,u)
    model.f(ẋ,x,u)
    model.evals[1] += 1
end
function evaluate!(ẋ::AbstractVector,model::Model{Discrete},x,u,dt)
    model.f(ẋ,x,u,dt)
    model.evals[1] += 1
end

""" $(SIGNATURES) Evaluate the dynamics and dynamics Jacobian simultaneously at state `x` and control `x`
Keeps track of the number of evaluations
"""
function evaluate!(Z::AbstractMatrix,ẋ::AbstractVector,model::Model{Continuous},x,u)
    model.∇f(Z,ẋ,x,u)
    model.evals[1] += 1
    model.evals[2] += 1
end
function evaluate!(Z::AbstractMatrix,ẋ::AbstractVector,model::Model{Discrete},x,u,dt)
    model.∇f(Z,ẋ,x,u,dt)
    model.evals[1] += 1
    model.evals[2] += 1
end

""" $(SIGNATURES) Evaluate the dynamics and dynamics Jacobian simultaneously at state `x` and control `x`
Keeps track of the number of evaluations
"""
jacobian!(Z::AbstractMatrix,ẋ::AbstractVector,model::Model{Continuous},x,u) = evaluate!(Z,ẋ,model,x,u)
jacobian!(Z::AbstractMatrix,ẋ::AbstractVector,model::Model{Discrete},x,u,dt) = evaluate!(Z,ẋ,model,x,u,dt)

""" $(SIGNATURES) Evaluate the dynamics Jacobian simultaneously at state `x` and control `x`
Keeps track of the number of evaluations
"""
function jacobian!(Z::AbstractMatrix,model::Model{Continuous},x,u)
    model.∇f(Z,x,u)
    model.evals[2] += 1
end
function jacobian!(Z::AbstractMatrix,model::Model{Discrete},x,u,dt)
    model.∇f(Z,x,u,dt)
    model.evals[2] += 1
end


""" $(SIGNATURES) Return the number of dynamics evaluations """
evals(model::Model) = model.evals[1]

""" $(SIGNATURES) Reset the evaluation counts for the model """
reset(model::Model) = begin model.evals[1] = 0; return nothing end

Base.length(model::Model{Discrete}) = model.n + model.m + 1
Base.length(model::Model{Continuous}) = model.n + model.m

PartedArrays.create_partition(model::Model{Discrete}) = create_partition((model.n,model.m,1),(:x,:u,:dt))
PartedArrays.create_partition2(model::Model{Discrete}) = create_partition2((model.n,),(model.n,model.m,1),(:x,),(:x,:u,:dt))
PartedArrays.create_partition(model::Model{Continuous}) = create_partition((model.n,model.m),(:x,:u))
PartedArrays.create_partition2(model::Model{Continuous}) = create_partition2((model.n,),(model.n,model.m),(:x,),(:x,:u))
PartedArrays.BlockVector(model::Model) = BlockArray(zeros(length(model)),create_partition(model))
PartedArrays.BlockVector(T::Type,model::Model) = BlockArray(zeros(T,length(model)),create_partition(model))
PartedArrays.BlockMatrix(model::Model) = BlockArray(zeros(model.n,length(model)),create_partition2(model))
PartedArrays.BlockMatrix(T::Type,model::Model) = BlockArray(zeros(T,model.n,length(model)),create_partition2(model))


function dynamics(model::Model,xdot,x,u)
    model.f(xdot,x,u)
    model.evals[1] += 1
end

"""
$(TYPEDEF)
RigidBodyDynamics model. Wrapper for a RigidBodyDynamics Mechanism
"""
struct RBDModel{D} <: Model{D}
    f::Function # continuous dynamics (ie, differential equation)
    n::Int # number of states
    m::Int # number of controls
    mech::Mechanism  # RigidBodyDynamics Mechanism
    evals::Vector{Int}
    info::Dict{Symbol,Any}
end



"""
$(SIGNATURES)
Model(mech::Mechanism, torques::Array{Bool, 1}) Constructor for an underactuated mechanism, where torques is a binary array
that specifies whether a joint is actuated.
"""
function Model(mech::Mechanism, torques::Array)

    # construct a model using robot dynamics equation assembed from URDF file
    n = num_positions(mech) + num_velocities(mech) + num_additional_states(mech)
    num_joints = length(joints(mech))  # subtract off joint to world

    if length(torques) != num_joints
        error("Torque underactuation specified does not match mechanism dimensions")
    end

    m = convert(Int,sum(torques)) # number of actuated (ie, controllable) joints
    torque_matrix = 1.0*Matrix(I,num_joints,num_joints)[:,torques.== 1] # matrix to convert from control inputs to mechanism joints

    statecache = StateCache(mech)
    dynamicsresultscache = DynamicsResultCache(mech)

    function f(ẋ::AbstractVector{T},x::AbstractVector{T},u::AbstractVector{T}) where T
        state = statecache[T]
        dyn = dynamicsresultscache[T]
        dynamics!(view(ẋ,1:n), dyn, state, x, torque_matrix*u)
        return nothing
    end
    d = Dict{Symbol,Any}()

    evals = [0,]
    RBDModel{Continuous}(f, n, m, mech, evals, d)
end

"""
$(SIGNATURES)
 Construct model from a `Mechanism` type from `RigidBodyDynamics`
 """
function Model(mech::Mechanism)
    m = length(joints(mech))  # subtract off joint to world
    Model(mech,ones(m))
end


"""$(SIGNATURES) Construct a fully actuated model from a string to a urdf file"""
function Model(urdf::String)
    # construct model using string to urdf file
    mech = parse_urdf(urdf)
    Model(mech)
end

"""$(SIGNATURES) Construct a partially actuated model from a string to a urdf file, where torques is a binary array that specifies whether a joint is actuated."""
function Model(urdf::String,torques::Array{Float64,1})
    # underactuated system (potentially)
    mech = parse_urdf(urdf)
    Model(mech,torques)
end


"$(SIGNATURES) Generate a jacobian function for a given in-place function of the form f(v,x,u)"
generate_jacobian(f!::Function,n::Int,m::Int,p::Int=n) = generate_jacobian(Continuous,f!,n,m,p)
function generate_jacobian(::Type{Continuous},f!::Function,n::Int,m::Int,p::Int=n)
    inds = (x=1:n,u=n .+ (1:m), px=(1:p,1:n),pu=(1:p,n .+ (1:m)))
    Z = BlockArray(zeros(p,n+m),inds)
    z = zeros(n+m)
    v0 = zeros(p)
    f_aug(dZ::AbstractVector,z::AbstractVector) = f!(dZ,view(z,inds.x), view(z,inds.u))
    ∇fz(Z::AbstractMatrix,v::AbstractVector,z::AbstractVector) = ForwardDiff.jacobian!(Z,f_aug,v,z)
    ∇f!(Z::AbstractMatrix,v::AbstractVector,x::AbstractVector,u::AbstractVector) = begin
        z[inds.x] = x
        z[inds.u] = u
        ∇fz(Z,v,z)
        return nothing
    end
    ∇f!(Z::AbstractMatrix,x::AbstractVector,u::AbstractVector) = begin
        z[inds.x] = x
        z[inds.u] = u
        ∇fz(Z,v0,z)
        return nothing
    end
    ∇f!(x::AbstractVector,u::AbstractVector) = begin
        z[inds.x] = x
        z[inds.u] = u
        ∇fz(Z,v0,z)
        return Z
    end
    return ∇f!, f_aug
end

function generate_jacobian(::Type{Discrete},fd!::Function,n::Int,m::Int)
    inds = (x=1:n,u=n .+ (1:m), dt=n+m+1, xx=(1:n,1:n),xu=(1:n,n .+ (1:m)), xdt=(1:n,n+m.+(1:1)))
    S0 = zeros(n,n+m+1)
    s = zeros(n+m+1)
    ẋ0 = zeros(n)

    fd_aug!(xdot,s) = fd!(xdot,view(s,inds.x),view(s,inds.u),s[inds.dt])
    Fd!(S,xdot,s) = ForwardDiff.jacobian!(S,fd_aug!,xdot,s)
    ∇fd!(S::AbstractMatrix,ẋ::AbstractVector,x::AbstractVector,u::AbstractVector,dt::Float64) = begin
        s[inds.x] = x
        s[inds.u] = u
        s[inds.dt] = dt
        Fd!(S,ẋ,s)
        return nothing
    end
    ∇fd!(S::AbstractMatrix,x::AbstractVector,u::AbstractVector,dt::Float64) = begin
        s[inds.x] = x
        s[inds.u] = u
        s[inds.dt] = dt
        Fd!(S,ẋ0,s)
        return nothing
    end
    ∇fd!(x::AbstractVector,u::AbstractVector,dt::Float64) = begin
        s[inds.x] = x
        s[inds.u] = u
        s[inds.dt] = dt
        Fd!(S0,ẋ0,s)
        return S0
    end
    return ∇fd!, fd_aug!
end

"""$(SIGNATURES)
Convert a continuous dynamics model into a discrete one using the given discretization function.
    The discretization function can either be one of the currently supported functions (midpoint, rk3, rk4) or a custom method that has the following form
    ```
    function discretizer(f::Function,dt::Float64)
        function fd!(xdot,x,u,dt)
            # Your code
            return nothing
        end
        return fd!
    end
    ```
"""
function Model{Discrete}(model::Model{Continuous},discretizer::Function)
    fd!,∇fd! = discretize(model.f,discretizer,model.n,model.m)
    AnalyticalModel{Discrete}(fd!,∇fd!,model.n,model.m,model.params,model.info)
end

function discretize(f::Function,discretizer::Function,n::Int,m::Int)
    inds = (x=1:n,u=n .+ (1:m), dt=n+m .+ (1:1), xx=(1:n,1:n),xu=(1:n,n .+ (1:m)), xdt=(1:n,n+m.+(1:1)))
    dt = 0.1  # TODO: remove this after getting rid of old discretization code
    fd! = discretizer(f,dt)
    ∇fd!, = generate_jacobian(Discrete,fd!,n,m)
    return fd!,∇fd!
end




"""
$(SIGNATURES)
Determine if the dynamics in model are in place. i.e. the function call is of
the form `f!(xdot,x,u)`, where `xdot` is modified in place. Returns a boolean.
"""
function is_inplace_dynamics(model::Model)::Bool
    x = rand(model.n)
    u = rand(model.m)
    xdot = rand(model.n)
    try
        model.f(xdot,x,u)
    catch x
        if x isa MethodError
            return false
        end
    end
    return true
end

function is_inplace_dynamics(f::Function,n::Int64,m::Int64)::Bool
    x = rand(n)
    u = rand(m)
    xdot = rand(n)
    try
        f(xdot,x,u)
    catch x
        if x isa MethodError
            return false
        end
    end
    return true
end

"""
$(SIGNATURES)
Makes the dynamics function `f(x,u)` appear to operate as an inplace operation of the
form `f!(xdot,x,u)`.
"""
function wrap_inplace(f::Function)
    f!(xdot,x,u) = copyto!(xdot, f(x,u))
    f!(xdot,x) = copyto!(xdot, f(x))
end

"""$(SIGNATURES)
Checks jacobians of functions of the form `f(v,x,u)` to make sure they have the correct forms.
Jacobians should have the following three forms
```∇f(x,u)
∇f(Z,x,u)
∇f(Z,v,x,u)```
"""
function _test_jacobian(::Type{Continuous},∇f::Function)
    form = [true,true,true]
    form[1] = hasmethod(∇f,(AbstractVector,AbstractVector))
    form[2] = hasmethod(∇f,(AbstractMatrix,AbstractVector,AbstractVector))
    form[3] = hasmethod(∇f,(AbstractMatrix,AbstractVector,AbstractVector,AbstractVector))
    return form
end

"""$(SIGNATURES)
Checks jacobians of functions of the form `f(v,x,u,dt)` to make sure they have the correct forms.
Jacobians should have the following three forms
```∇f(x,u,dt)
∇f(S,x,u,dt)
∇f(S,v,x,u,dt)```
"""
function _test_jacobian(::Type{Discrete},∇f::Function)
    form = [true,true,true]
    form[1] = hasmethod(∇f,(AbstractVector,AbstractVector,Float64))
    form[2] = hasmethod(∇f,(AbstractMatrix,AbstractVector,AbstractVector,Float64))
    form[3] = hasmethod(∇f,(AbstractMatrix,AbstractVector,AbstractVector,AbstractVector,Float64))
    return form
end

_check_jacobian(f::Function,∇f::Function,n::Int,m::Int,p::Int=n) = _check_jacobian(Continuous,f,∇f,n,m,p)
function _check_jacobian(::Type{Continuous},f::Function,∇f::Function,n::Int,m::Int,p::Int=n)
    forms = _test_jacobian(Continuous,∇f)
    if !forms[2]
        throw("Jacobians must have the method ∇f(Z,x,u)")
    else
        inds = (x=1:n,u=n .+ (1:m), px=(1:p,1:n),pu=(1:p,n .+ (1:m)))
        Z = BlockArray(zeros(p,n+m),inds)
        z = zeros(n+m)

        # Copy the correct method form
        ∇f!(Z,x,u) = ∇f(Z,x,u)

        # Implement the missing method(s)
        if forms[1]
            ∇f!(x,u) = ∇f(x,u)
        else
            ∇f!(x,u) = begin
                ∇f!(Z,x,u)
                return Z
            end@test Z2.A == Z.A
@test !(Z2.A === Z.A)
Z2 .= rand(1:7,7)
@test Z2.x != Z.x
Zs = [Z,Z2]
Zs2 = copy(Zs)
@test Zs2[1].A == Zs[1].A
        end
        if forms[3]
            ∇f!(Z,v,x,u) = ∇f(Z,v,x,u)
        else
            ∇f!(Z,v,x,u) = begin
                x = z[inds.x]
                u = z[inds.u]
                f(v,x,u)
                ∇f!(Z,x,u)
            end
        end
    end
    return ∇f!
end

function _check_jacobian(::Type{Discrete},f::Function,∇f::Function,n::Int,m::Int,p::Int=n)
    forms = _test_jacobian(Discrete,∇f)
    if !forms[2]
        throw("Jacobians must have the method ∇f(Z,x,u,dt)")
    else
        inds = (x=1:n,u=n .+ (1:m), dt=n+m+1, xx=(1:n,1:n),xu=(1:n,n .+ (1:m)), xdt=(1:n,n+m.+(1:1)))
        S = BlockArray(zeros(p,n+m+1),inds)
        s = zeros(n+m+1)

        # Copy the correct method form
        ∇f!(S,x,u,dt) = ∇f(S,x,u,dt)

        # Implement the missing method(s)
        if forms[1]
            ∇f!(x,u,dt) = ∇f(x,u,dt)
        else
            ∇f!(x,u,dt) = begin
                ∇f!(S,x,u,dt)
                return S
            end
        end
        if forms[3]
            ∇f!(S,v,x,u,dt) = ∇f(S,v,x,u,dt)
        else
            ∇f!(S,v,x,u,dt) = begin
                x = s[inds.x]
                u = s[inds.u]
                dt = s[inds.dt]
                f(v,x,u,dt)
                ∇f!(S,x,u,dt)
            end
        end
    end
    return ∇f!
end

function _check_dynamics(f::Function,n::Int,m::Int)
    no_params = hasmethod(f,(AbstractVector,AbstractVector,AbstractVector))
    with_params = hasmethod(f,(AbstractVector,AbstractVector,AbstractVector,Any))
    return [no_params,with_params]
end
