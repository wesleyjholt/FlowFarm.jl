abstract type AbstractModelSet end

"""
    WindFarmModelSet(wakedeficitmodel, wake_deflection_model, wake_combination_model, local_ti_model)

Container for objects defining models to use in wind farm calculations

# Arguments
- `wake_defiict_model::AbstractWakeDeficitModel`: contains a struct defining the desired wake deficit model
- `wake_deflection_model::AbstractWakeDeflectionModel`: contains a struct defining the desired wake deflection model
- `wake_combination_model::AbstractWakeCombinationModel`: contains a struct defining the desired wake combination model
- `local_ti_model::AbstractTurbulenceIntensityModel`: contains a struct defining the desired turbulence intensity model
"""
struct WindFarmModelSet{DTM,DNM,CM,TIM} <: AbstractModelSet

    wake_deficit_model::DTM
    wake_deflection_model::DNM
    wake_combination_model::CM
    local_ti_model::TIM

end

"""
    rotate_to_wind_direction(xlocs, ylocs, wind_direction_met)

Rotates wind farm coordinates to be in wind direction reference where wind direction is to
the positive x.

# Arguments
- `xlocs::Array`: contains turbine east-west locations in the global reference frame
- `ylocs::Array`: contains turbine north-south locations in the global reference frame
- `wind_direction_met::Array`: contains wind direction in radians in meteorological standard 
    system (N=0 rad, proceeds CW, wind from direction given)
"""
function rotate_to_wind_direction(xlocs, ylocs, wind_direction_met)
    # use radians

    # convert from meteorological polar system (CW, 0 rad.=N) to standard polar system (CCW, 0 rad.=E)
    wind_direction_cart = (3.0*pi/2.0 - wind_direction_met)

    if wind_direction_cart < 0.0
        wind_direction_cart += 2.0*pi
    end

    cos_wdr = cos(-wind_direction_cart)
    sin_wdr = sin(-wind_direction_cart)

    # convert to cartesian coordinates with wind to positive x
    x_cart = xlocs*cos_wdr - ylocs*sin_wdr
    y_cart = xlocs*sin_wdr + ylocs*cos_wdr

    return x_cart, y_cart
end

"""
    point_velocity(loc, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
    rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, wtvelocities,
    wind_resource, model_set::AbstractModelSet;
    wind_farm_state_id=1, downwind_turbine_id=0)

Calculates the wind speed at a given point for a given state

# Arguments
- `loc::Array{TF,3}`: Location of interest
- `turbine_x::Array{TF,nTurbines}`: turbine east-west locations in the global 
    reference frame
- `turbine_y::Array{TF,nTurbines}`: turbine north-south locations in the global 
    reference frame
- `turbine_z::Array{TF,nTurbines}`: turbine base height in the global reference frame
- `turbine_yaw::Array{TF,nTurbines}`: turbine yaw for the given wind direction in 
    radians
- `turbine_ct::Array{TF,nTurbines}`: turbine north-south locations in the global 
    reference frame
- `turbine_ai::Array{TF,nTurbines}`: turbine axial induction for the given state
- `rotor_diameter::Array{TF,nTurbines}`: turbine rotor diameters
- `hub_height::Array{TF,nTurbines}`: turbine hub heights
- `turbine_local_ti::Array{TF,nTurbines}`: turbine local turbulence intensity for 
    the given state
- `sorted_turbine_index::Array{TF,nTurbines}`: array containing indices of wind turbines 
    from most upwind to most downwind turbine in the given state
- `wtvelocities::Array{TF,nTurbines}`: effective inflow wind speed for given state
- `wind_resource::DiscretizedWindResource`: contains wind resource discreption (directions,
    speeds, frequencies, etc)
- `wind_farm_state_id::Int`: index to correct state to use from wind resource provided.
    Defaults to 1
- `downwind_turbine_id::Int`: index of wind turbine of interest (if any). If not a point for
    calculating effective wind speed of a turbine, then provide 0 (default)
"""
function point_velocity(locx, locy, locz, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
                    rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, wtvelocities,
                    wind_resource, model_set::AbstractModelSet;
                    wind_farm_state_id=1, downwind_turbine_id=0, eps=1E-6)

    wakedeficitmodel = model_set.wake_deficit_model
    wakedeflectionmodel = model_set.wake_deflection_model
    wakecombinationmodel = model_set.wake_combination_model

    # extract flow information
    wind_speed = wind_resource.wind_speeds[wind_farm_state_id]
    reference_height = wind_resource.measurement_heights[wind_farm_state_id]
    wind_shear_model = wind_resource.wind_shear_model
    shear_exponent = wind_shear_model.shear_exponent

    # set ground height 
    ground_height = turbine_z[1]    # TODO: allow topology to be given

    # get number of turbines
    nturbines = length(turbine_x)

    # initialize deficit summation term to zero
    deficit_sum = 0.0

    # initialize point velocity with shear to zero
    point_velocity_with_shear = 0.0

    # loop through all turbines
    for u=1:nturbines

        # get index of upstream turbine
        upwind_turb_id = Int(sorted_turbine_index[u])

        # skip this loop if it would include a turbine's impact on itself)
        if upwind_turb_id==downwind_turbine_id; continue; end

        # downstream distance between upstream turbine and point
        x = locx - turbine_x[upwind_turb_id]

        if x > -eps*rotor_diameter[upwind_turb_id]
            
            # check turbine relative locations and use a spline to smooth the deficit jump
            # at the rotor hub location
            if x < 0.0
                
                # set horizontal and vertical deflection of upstream "wake"
                # calculate wake deflection of the current wake at epsilon
                horizontal_deflection = wake_deflection_model(turbine_x[upwind_turb_id] + eps*rotor_diameter[upwind_turb_id], locy, locz, turbine_x, turbine_yaw, turbine_ct,
                                upwind_turb_id, rotor_diameter, turbine_local_ti, wakedeflectionmodel)
                vertical_deflection = 0.0

                # get deficit at downstream end of spline
                deltav_downstream = wake_deficit_model(turbine_x[upwind_turb_id] + eps*rotor_diameter[upwind_turb_id], locy, locz, turbine_x, turbine_y, turbine_z, horizontal_deflection, vertical_deflection,
                                            upwind_turb_id, downwind_turbine_id, hub_height, rotor_diameter, turbine_ai,
                                            turbine_local_ti, turbine_ct, turbine_yaw, wakedeficitmodel)

                # set deficit derivative at downstream end of spline
                deltav_deriv_down_stream = 0.0

                # set deficit at upstream end of spline 
                deltav_upstream = 0.0

                # set deficit derivative at upstream end of spline
                deltav_deriv_up_stream = 0.0

                # calculate deltav using a hermite spline across the rotor hub region
                deltav = hermite_spline(locx, turbine_x[upwind_turb_id]-eps*rotor_diameter[upwind_turb_id], turbine_x[upwind_turb_id]+eps*rotor_diameter[upwind_turb_id], deltav_upstream, deltav_deriv_up_stream, deltav_downstream, deltav_deriv_down_stream)

            else

                # calculate wake deflection of the current wake at the point of interest
                horizontal_deflection = wake_deflection_model(locx, locy, locz, turbine_x, turbine_yaw, turbine_ct,
                                upwind_turb_id, rotor_diameter, turbine_local_ti, wakedeflectionmodel)

                vertical_deflection = 0.0

                # velocity difference in the wake
                deltav = wake_deficit_model(locx, locy, locz, turbine_x, turbine_y, turbine_z, horizontal_deflection, vertical_deflection,
                                upwind_turb_id, downwind_turbine_id, hub_height, rotor_diameter, turbine_ai,
                                turbine_local_ti, turbine_ct, turbine_yaw, wakedeficitmodel)
                # println("horizontal_deflection: ", horizontal_deflection)
            end

            # combine deficits according to selected wake combination method
            turb_inflow = wtvelocities[upwind_turb_id]
            deficit_sum = wake_combination_model(deltav, wind_speed, wtvelocities[upwind_turb_id], deficit_sum, wakecombinationmodel)
        end
    end

    # find velocity at point without shear
    point_velocity_without_shear = wind_speed - deficit_sum

    # adjust sample point velocity for shear
    point_velocity_with_shear = adjust_for_wind_shear(locz, point_velocity_without_shear, reference_height, ground_height, wind_shear_model)


    return point_velocity_with_shear

end

"""
    point_velocity(turbine_x, turbine_y, turbine_z, rotor_diameter, hub_height, turbine_yaw,
    sorted_turbine_index, ct_model, rotor_sample_points_y, rotor_sample_points_z, wind_resource,
    model_set::AbstractModelSet; wind_farm_state_id=1)

Calculates the wind speed at a given point for a given state

# Arguments
- `turbine_x::Array{TF,nTurbines}`: turbine east-west locations in the global 
    reference frame
- `turbine_y::Array{TF,nTurbines}`: turbine north-south locations in the global 
    reference frame
- `turbine_z::Array{TF,nTurbines}`: turbine base height in the global reference frame
- `rotor_diameter::Array{TF,nTurbines}`: turbine rotor diameters
- `hub_height::Array{TF,nTurbines}`: turbine hub heights
- `turbine_yaw::Array{TF,nTurbines}`: turbine yaw for the given wind direction in 
    radians
- `sorted_turbine_index::Array{TF,nTurbines}`: turbine north-south locations in the 
    global reference frame
- `ct_model::AbstractThrustCoefficientModel`: defines how the thrust coefficient changes 
    with state etc
- rotor_sample_points_y::Array{TF,N}`: horizontal wind location of points to sample across 
    the rotor swept area when calculating the effective wind speed for the wind turbine. 
    Points are centered at the hub (0,0) and scaled by the radius (1=tip of blades) 
- rotor_sample_points_z::Array{TF,N}`: vertical wind location of points to sample across the 
    rotor swept area when calculating the effective wind speed for the wind turbine. Points
    are centered at the hub (0,0) and scaled by the radius (1=tip of blades)
- `wind_resource::DiscretizedWindResource`: wind resource discreption (directions, speeds, 
    frequencies, etc)
- `model_set::AbstractModelSet`: defines wake-realated models to be used in analysis
- `wind_farm_state_id::Int`: index to correct state to use from wind resource provided.
    Defaults to 1
"""
function turbine_velocities_one_direction(turbine_x, turbine_y, turbine_z, rotor_diameter, hub_height, turbine_yaw,
                    sorted_turbine_index, ct_model, rotor_sample_points_y, rotor_sample_points_z, wind_resource,
                    model_set::AbstractModelSet; wind_farm_state_id=1, velocity_only=true)

    # get number of turbines and rotor sample point
    n_turbines = length(turbine_x)
    n_rotor_sample_points = length(rotor_sample_points_y)

    arr_type = promote_type(typeof(turbine_x[1]),typeof(turbine_y[1]),typeof(turbine_z[1]),typeof(rotor_diameter[1]),
                            typeof(hub_height[1]),typeof(turbine_yaw[1]))

    turbine_velocities = zeros(arr_type, n_turbines)
    turbine_ct = zeros(arr_type, n_turbines)
    turbine_ai = zeros(arr_type, n_turbines)
    turbine_local_ti = zeros(arr_type, n_turbines)

    for d=1:n_turbines

        # get index of downstream turbine
        downwind_turbine_id = Int(sorted_turbine_index[d])

        # initialize downstream wind turbine velocity to zero
        # println("start array: ", turbine_velocities[downwind_turbine_id])
        # wind_turbine_velocity = typeof(turbine_velocities[downwind_turbine_id])(0.0)
        wind_turbine_velocity = 0.0
        # turbine_velocities[downwind_turbine_id] = 0.0

        for p=1:n_rotor_sample_points


            # scale rotor sample point coordinate by rotor diameter (in rotor hub ref. frame)
            local_rotor_sample_point_y = rotor_sample_points_y[p]*0.5*rotor_diameter[downwind_turbine_id]
            local_rotor_sample_point_z = rotor_sample_points_z[p]*0.5*rotor_diameter[downwind_turbine_id]

            locx = turbine_x[downwind_turbine_id] .+ local_rotor_sample_point_y*sin(turbine_yaw[downwind_turbine_id])
            locy = turbine_y[downwind_turbine_id] .+ local_rotor_sample_point_y*cos(turbine_yaw[downwind_turbine_id])
            locz = turbine_z[downwind_turbine_id] .+ hub_height[downwind_turbine_id] + local_rotor_sample_point_z

            # calculate the velocity at given point
            point_velocity_with_shear = point_velocity(locx, locy, locz, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
                                    rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, turbine_velocities,
                                    wind_resource, model_set,
                                    wind_farm_state_id=wind_farm_state_id, downwind_turbine_id=downwind_turbine_id)

            # add sample point velocity to turbine velocity to be averaged later
            wind_turbine_velocity += point_velocity_with_shear

        end

        # final velocity calculation for downstream turbine (average equally across all points)
        wind_turbine_velocity /= n_rotor_sample_points

        turbine_velocities[downwind_turbine_id] = deepcopy(wind_turbine_velocity)

        # update thrust coefficient for downstream turbine
        turbine_ct[downwind_turbine_id] = calculate_ct(turbine_velocities[downwind_turbine_id], ct_model[downwind_turbine_id])

        # update axial induction for downstream turbine
        turbine_ai[downwind_turbine_id] = _ct_to_axial_ind_func(turbine_ct[downwind_turbine_id])

        # update local turbulence intensity for downstream turbine
        ambient_ti = wind_resource.ambient_tis[wind_farm_state_id]
        turbine_local_ti[downwind_turbine_id] = calculate_local_ti(turbine_x, turbine_y, ambient_ti, rotor_diameter, hub_height, turbine_yaw, turbine_local_ti, sorted_turbine_index,
                            turbine_velocities, turbine_ct, model_set.local_ti_model; turbine_id=downwind_turbine_id, tol=1E-6)

    end

    if velocity_only
        return turbine_velocities 
    else
        return turbine_velocities, turbine_ct, turbine_ai, turbine_local_ti
    end
end

function turbine_velocities_one_direction(x, turbine_z, rotor_diameter, hub_height, turbine_yaw,
    sorted_turbine_index, ct_model, rotor_sample_points_y, rotor_sample_points_z, wind_resource,
    model_set::AbstractModelSet; wind_farm_state_id=1, velocity_only=true)

    n_turbines = Int(length(x)/2)
    println(typeof(x), n_turbines)
    turbine_x = x[1:n_turbines] 
    turbine_y = x[n_turbines+1:end]
    # println(turbine_x)
    println("turbine_x type ", typeof(turbine_x))
    println("type of x ", typeof(x))

    # get number of turbines and rotor sample point
    # n_turbines = length(turbine_x)
    n_rotor_sample_points = length(rotor_sample_points_y)

    arr_type = promote_type(typeof(turbine_x[1]),typeof(turbine_y[1]),typeof(turbine_z[1]),typeof(rotor_diameter[1]),
                typeof(hub_height[1]),typeof(turbine_yaw[1]))
    turbine_velocities = zeros(arr_type, n_turbines)
    turbine_ct = zeros(arr_type, n_turbines)
    turbine_ai = zeros(arr_type, n_turbines)
    turbine_local_ti = zeros(arr_type, n_turbines)

    for d=1:n_turbines

        # get index of downstream turbine
        downwind_turbine_id = Int(sorted_turbine_index[d])

        # initialize downstream wind turbine velocity to zero
        # println("start array: ", turbine_velocities[downwind_turbine_id])
        # wind_turbine_velocity = typeof(turbine_velocities[downwind_turbine_id])(0.0)
        wind_turbine_velocity = 0.0
        # turbine_velocities[downwind_turbine_id] = 0.0

        for p=1:n_rotor_sample_points


            # scale rotor sample point coordinate by rotor diameter (in rotor hub ref. frame)
            local_rotor_sample_point_y = rotor_sample_points_y[p]*0.5*rotor_diameter[downwind_turbine_id]
            local_rotor_sample_point_z = rotor_sample_points_z[p]*0.5*rotor_diameter[downwind_turbine_id]

            locx = turbine_x[downwind_turbine_id] .+ local_rotor_sample_point_y*sin(turbine_yaw[downwind_turbine_id])
            locy = turbine_y[downwind_turbine_id] .+ local_rotor_sample_point_y*cos(turbine_yaw[downwind_turbine_id])
            locz = turbine_z[downwind_turbine_id] .+ hub_height[downwind_turbine_id] + local_rotor_sample_point_z

            # calculate the velocity at given point
            point_velocity_with_shear = point_velocity(locx, locy, locz, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
                                rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, turbine_velocities,
                                wind_resource, model_set,
                                wind_farm_state_id=wind_farm_state_id, downwind_turbine_id=downwind_turbine_id)

            # add sample point velocity to turbine velocity to be averaged later
            wind_turbine_velocity += point_velocity_with_shear

        end

        # final velocity calculation for downstream turbine (average equally across all points)
        wind_turbine_velocity /= n_rotor_sample_points

        turbine_velocities[downwind_turbine_id] = deepcopy(wind_turbine_velocity)

        # update thrust coefficient for downstream turbine
        turbine_ct[downwind_turbine_id] = calculate_ct(turbine_velocities[downwind_turbine_id], ct_model[downwind_turbine_id])

        # update axial induction for downstream turbine
        turbine_ai[downwind_turbine_id] = _ct_to_axial_ind_func(turbine_ct[downwind_turbine_id])

        # update local turbulence intensity for downstream turbine
        ambient_ti = wind_resource.ambient_tis[wind_farm_state_id]
        turbine_local_ti[downwind_turbine_id] = calculate_local_ti(turbine_x, turbine_y, ambient_ti, rotor_diameter, hub_height, turbine_yaw, turbine_local_ti, sorted_turbine_index,
                    turbine_velocities, turbine_ct, model_set.local_ti_model; turbine_id=downwind_turbine_id, tol=1E-6)

    end

    if velocity_only
        return turbine_velocities 
    else
        return turbine_velocities, turbine_ct, turbine_ai, turbine_local_ti
    end

end

# turbine_velocities_one_direction!(model_set::AbstractModelSet, problem_description::AbstractWindFarmProblem; wind_farm_state_id=1) = turbine_velocities_one_direction!([0.0], [0.0],
# model_set::AbstractModelSet, problem_description::AbstractWindFarmProblem; wind_farm_state_id=1)

"""
calculate_flow_field(xrange, yrange, zrange, model_set::AbstractModelSet, turbine_x, 
    turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai, rotor_diameter, hub_height, 
    turbine_local_ti, sorted_turbine_index, wtvelocities, wind_resource; wind_farm_state_id=1)

Generates a flow field for a given state and cross section

# Arguments
- `xrange::Range`: range defining east-west locations to sample in global reference frame
- `yrange::Range`: range defining north-west locations to sample in global reference frame
- `zrange::Range`: range defining vertical locations to sample in global reference frame
- `model_set::AbstractModelSet`: defines wake-realated models to be used in analysis
- `turbine_x::Array{TF,nTurbines}`: turbine east-west locations in the global 
    reference frame
- `turbine_y::Array{TF,nTurbines}`: turbine north-south locations in the global 
    reference frame
- `turbine_z::Array{TF,nTurbines}`: turbine base height in the global reference frame
- `turbine_yaw::Array{TF,nTurbines}`: turbine yaw for the given wind direction in 
    radians
- `turbine_ct::Array{TF,nTurbines}`: thrust coefficient of each turbine for the given state
- `turbine_ai::Array{TF,nTurbines}`: turbine axial induction for the given state
- `rotor_diameter::Array{TF,nTurbines}`: turbine rotor diameters
- `hub_height::Array{TF,nTurbines}`: turbine hub heights
- `turbine_local_ti::Array{TF,nTurbines}`: turbine local turbulence intensity for 
    the given state
- `sorted_turbine_index::Array{TF,nTurbines}`: turbine north-south locations in the 
    global reference frame
- `wtvelocities::Array{TF,nTurbines}`: effective inflow wind speed for given state
- `wind_resource::DiscretizedWindResource`: wind resource discreption (directions, speeds, 
    frequencies, etc)
- `wind_farm_state_id::Int`: index to correct state to use from wind resource provided.
    Defaults to 1
"""
function calculate_flow_field(xrange, yrange, zrange,
    model_set::AbstractModelSet, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
    rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, wtvelocities,
    wind_resource;
    wind_farm_state_id=1)

    xlen = length(xrange)
    ylen = length(yrange)
    zlen = length(zrange)
    npoints = xlen*ylen*zlen
    point_velocities = zeros(npoints)
    point_velocities = reshape(point_velocities, (zlen, ylen, xlen))

    for zi in 1:zlen
        for yi in 1:ylen
            for xi in 1:xlen
                locx = xrange[xi]
                locy = yrange[yi]
                locz = zrange[zi]
                locx, locy = rotate_to_wind_direction(locx, locy, wind_resource.wind_directions[wind_farm_state_id])

                point_velocities[zi, yi, xi] = point_velocity(locx, locy, locz, turbine_x, turbine_y, turbine_z, turbine_yaw, turbine_ct, turbine_ai,
                    rotor_diameter, hub_height, turbine_local_ti, sorted_turbine_index, wtvelocities,
                    wind_resource, model_set,
                    wind_farm_state_id=wind_farm_state_id, downwind_turbine_id=0)

            end
        end
    end

    if zlen == 1
        return point_velocities[1,1:ylen,1:xlen]
    elseif ylen == 1
        return point_velocities[1:zlen,1,1:xlen]
    elseif xlen == 1
        return point_velocities[1:zlen,1:ylen,1]
    end

end