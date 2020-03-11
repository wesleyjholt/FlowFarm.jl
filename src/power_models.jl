include("turbines.jl")
include("wind_resources.jl")

abstract type AbstractPowerModel end

struct ConstantCp{AF} <: AbstractPowerModel
    cp::AF
    generator_efficiency::AF
end

struct PowerCurveCubic{AF} <: AbstractPowerModel
    cut_in_speed::AF
    cut_out_speed::AF
    rated_speed::AF
    rated_power::AF
end

function calculate_turbine_power(turbine::AbstractTurbine, farmstate::SingleWindFarmState, wind_model::AbstractWindResourceModel, power_model::ConstantCp)

    id = turbine.id
    cp = power_model.cp[1]
    generator_efficiency = power_model.generator_efficiency[1]
    air_density = wind_model.air_density
    rotor_diameter = turbine.rotor_diameter[1]
    rotor_area = pi*(rotor_diameter^2)/4.0
    wt_velocity = farmstate.turbine_inflow_velcities[turbine.id[1]]

    wt_power = generator_efficiency*(0.5*air_density*rotor_area*cp*wt_velocity^3)

    return wt_power

end


# function calculate_turbine_power(turbine::AbstractTurbine, farmstate::SingleWindFarmState, wind_model::AbstractWindResourceModel, power_model::PowerCurveCubic)
#
#     id = turbine.id
#
#     cut_in_speed = power_model.cut_in_speed
#     cut_out_speed = power_model.cut_out_speed
#     rated_speed = power_model.rated_speed
#     rated_power = power_model.rated_power
#
#     generator_efficiency = power_model.generator_efficiency[1]
#     rotor_diameter = turbine.rotor_diameter[1]
#     rotor_area = pi*(rotor_diameter^2)/4.0
#     wt_velocity = farmstate.turbine_inflow_velcities[turbine.id[1]]
#
#     wt_power = generator_efficiency*(0.5*air_density*rotor_area*cp*wt_velocity^3)
#
#     return wt_power
#
# end
