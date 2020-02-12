include("wake_deficit_models.jl")
include("wake_deflection_models.jl")

abstract type AbstractWindFarmModel end
abstract type AbstractWindResourceModel end

struct WindFarm{AF,AS} <: AbstractWindFarmModel
    
    # farm design properties
    turbinex::AF
    turbiney::AF
    turbinez::AF
    turbine_definitions::AS

end

struct SingleWindFarmState{TF, AF, AI} <: AbstractWindFarmModel

    # farm properties in rotated frame
    turbinexw::AF
    turbineyw::AF
    sortedturbineindex::AI
    turbine_inflow_velcity::AF

end

struct DiscretizedWindResource{AF, TF} <: AbstractWindResourceModel
    
    winddirections::AF
    windspeeds::AF
    windpropabilities::AF
    measurementheight::AF
    shearexponent::TF

end

function rotate_to_wind_direction(xlocs, ylocs, wind_direction)

    nTurbines = length(xlocs)
    wd = -pi*(270. - wind_direction)/180. #shift to traditional wind direction coords and to radians
    xw = xlocs.*cos(wd)-ylocs.*sin(wd)
    yw = xlocs.*sin(wd)+ylocs.*cos(wd)
    return xw, yw

end

function adjust_for_wind_shear(loc, point_velocity_no_shear, reference_height, ground_height, shear_exp)

    # initialize adjusted wind speed to zero
    adjusted_wind_speed = 0.0

    # check that the point of interest is above ground level
    if loc[3] >= ground_height
        # adjusted wind speed for wind shear if point is above ground
        adjusted_wind_speed = point_velocity_no_shear*((loc[3]-ground_height)/(reference_height-ground_height))^shear_exp
    else 
        # if the point of interest is below ground, set the wind speed to 0.0
        adjusted_wind_speed = 0.0
    end

    return adjusted_wind_speed
end

function point_velocity(loc, turbine_id, direction_id,
    windfarm::WindFarm,
    windfarmstate::SingleWindFarmState,
    windresource::AbstractWindResourceModel,
    wakedeficitmodel::AbstractWakeDeficitModel, 
    wakedeflectionmodel::AbstractWakeDeflectionModel, 
    wakecombinationmodel::AbstractWakeCombinationModel)

    # extract turbine locations in rotated reference frame
    turbinexw = windfarmstate.turbinexw
    turbineyw = windfarmstate.turbineyw
    turbinez = windfarm.turbinez

    # extract turbine definitions
    turbines = windfarm.turbine_definitions

    # get sorted wind turbine index in currect direction
    sortedturbinexindex = windfarmstate.sortedturbineindex

    # get current inflow velocities at each turbine
    wtvelocities = windfarmstate.turbine_inflow_velcities

    # extract flow information
    wind_speed = windresource.wind_speed[direction_id]
    reference_height = windresource.measurementheight[direction_id]
    shear_exponent = windresource.shearexponent

    # get number of turbines
    nturbines = length(turbinexw)

    # initialize deficit summation term to zero
    deficit_sum = 0.0

    # initialize point velocity with shear to zero
    point_velocity_with_shear = 0.0
    
    # loop through all turbines
    for u=1:nturbines 
        
        # get index of upstream turbine
        turb = sortedturbinexindex[u]
        
        # skip this loop if it would include a turbine's impact on itself)
        if turb==turbine_id; continue; end

        # get turbine definition
        turbine = turbines[turb]
        
        # downstream distance between upstream turbine and point
        x = loc[1] - turbinexw[turb]
    
        # set this iterations velocity deficit to 0
        deltav = 0.0
        
        # check turbine relative locations
        if x > 0.0
        
            # calculate wake deflection of the current wake at the point of interest
            horizontal_deflection = deflection_model(loc, wakedeficitmodel, turbine)
            vertical_deflection = 0.0
            
            # velocity difference in the wake
            deltav = wake_deficit_model(loc, [horizontal_deflection, vertical_deflection], wakedeficitmodel, turbine)
            
            # combine deficits according to selected wake combination method 
            turb_inflow = wtvelocities[turb]
            deficit_sum += wake_combination_model(deltav, wind_speed, turb_inflow, deficit_sum, wakecombinationmodel)

        end
        
        # find velocity at point without shear
        point_velocity_without_shear = wind_speed - deficit_sum
        
        # adjust sample point velocity for shear
        point_velocity_with_shear = adjust_for_wind_shear(loc[3], point_velocity_without_shear, reference_height, turbinez[turb], shear_exponent)
        
    end

    return point_velocity_with_shear

end