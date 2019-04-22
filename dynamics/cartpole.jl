## Cartpole
import TrajectoryOptimization
traj_folder = joinpath(dirname(pathof(TrajectoryOptimization)),"..")
urdf_folder = joinpath(traj_folder, "dynamics/urdf")
urdf_cartpole = joinpath(urdf_folder, "cartpole.urdf")

cartpole_model_urdf = Model(urdf_cartpole,[1.;0.]) # underactuated, only control of slider

function cartpole_dynamics!(ẋ::AbstractVector{T}, x::AbstractVector{T}, u::AbstractVector{T}) where T
    mc = 10.0  # mass of the cart in kg (10)
    mp = 1.0    # mass of the pole (point mass at the end) in kg
    l = 0.5   # length of the pole in m
    g = 9.81  # gravity m/s^2

    q = x[1:2]
    qd = x[3:4]

    if isfinite(q[2])
        s = sin(q[2])
        c = cos(q[2])
    else
        s = Inf
        c = Inf
    end

    H = [mc+mp mp*l*c; mp*l*c mp*l^2]
    C = [0 -mp*qd[2]*l*s; 0 0]
    G = [0; mp*g*l*s]
    B = [1; 0]

    qdd = -H\(C*qd + G - B*U')

    ẋ[1:2] = qd
    ẋ[3:4] = qdd
    return nothing
end

n,m = 4,1
cartpole_model = Model(cartpole_dynamics!,n,m)
