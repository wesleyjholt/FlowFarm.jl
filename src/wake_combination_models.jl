abstract type AbstractWakeCombinationModel end

struct LinearFreestreamSuperposition <: AbstractWakeCombinationModel
    # Lissaman 1979
    # new_deficit_sum = old_deficit_sum + wind_speed*deltav

end

struct SumOfSquaresFreestreamSuperposition <: AbstractWakeCombinationModel
    # Katic et al. 1986
    # new_deficit_sum = sqrt(old_deficit_sum**2 + (wind_speed*deltav)**2)

end

struct SumOfSquaresLocalVelocitySuperposition <: AbstractWakeCombinationModel
    # Voutsinas 1990
    # new_deficit_sum = sqrt(old_deficit_sum**2 + (turb_inflow*deltav)**2)

end

struct LinearLocalVelocitySuperposition <: AbstractWakeCombinationModel
    # Niayifar and Porte Agel 2015, 2016
    # new_deficit_sum = old_deficit_sum + turb_inflow*deltav

end

function check_negative_deficits!(new_deficit_sum, wind_speed)
    if new_deficit_sum > wind_speed
        new_deficit_sum = wind_speed
    end
end

function wake_combination_model(deltav, wind_speed, turb_inflow, old_deficit_sum,  model::LinearFreestreamSuperposition)
    # Lissaman 1979

    new_deficit_sum = old_deficit_sum + wind_speed*deltav

    check_negative_deficits!(new_deficit_sum, wind_speed)
    
    return new_deficit_sum

end

function wake_combination_model(deltav, wind_speed, turb_inflow, old_deficit_sum, model::SumOfSquaresFreestreamSuperposition)
    # Katic et al. 1986

    new_deficit_sum = sqrt(old_deficit_sum^2 + (wind_speed*deltav)^2)
    
    check_negative_deficits!(new_deficit_sum, wind_speed)

    return new_deficit_sum

end

function wake_combination_model(deltav, wind_speed, turb_inflow, old_deficit_sum, model::SumOfSquaresLocalVelocitySuperposition)
    # Voutsinas 1990

    new_deficit_sum = sqrt(old_deficit_sum^2 + (turb_inflow*deltav)^2)
    
    check_negative_deficits!(new_deficit_sum, wind_speed)

    return new_deficit_sum

end

function wake_combination_model(deltav, wind_speed, turb_inflow, old_deficit_sum, model::LinearLocalVelocitySuperposition)
    # Niayifar and Porte Agel 2015, 2016

    new_deficit_sum = old_deficit_sum + turb_inflow*deltav
    
    check_negative_deficits!(new_deficit_sum, wind_speed)

    return new_deficit_sum

end
