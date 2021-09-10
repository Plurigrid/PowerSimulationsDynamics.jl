##################################################
############### LOAD DATA ########################
##################################################

include(joinpath(dirname(@__FILE__), "data_tests/test01.jl"))
omib_sys_file = System(PowerModelsData(omib_file_dir), runchecks = false)

##################################################
############### SOLVE PROBLEM ####################
##################################################
#Define Fault: Change of YBus
Ybus_change = NetworkSwitch(
    1.0, #change at t = 1.0
    Ybus_fault,
) #New YBus

@testset "Make Simulation" begin
    path1 = (joinpath(pwd(), "test-Base-1"))
    !isdir(path1) && mkdir(path1)
    try
        #Define Simulation Problem
        sim = Simulation(
            ResidualModel,
            omib_sys, #system
            path1,
            (0.0, 30.0), #time span
            Ybus_change;
            system_to_file = true,
        )
        @test sim.status == PSID.BUILT
        o_system = System(joinpath(path1, "input_system.json"))
        for b in get_components(Bus, o_system)
            b_sys = get_component(Bus, omib_sys, get_name(b))
            b_file = get_component(Bus, omib_sys_file, get_name(b))
            @test get_angle(b) == get_angle(b_sys)
            @test get_angle(b) == get_angle(b_file)
        end

    finally
        @info("removing test files")
        rm(path1, force = true, recursive = true)
    end

    path2 = (joinpath(pwd(), "test-Base-2"))
    !isdir(path2) && mkdir(path2)
    try
        #Define Simulation Problem
        sim = Simulation!(
            ResidualModel,
            omib_sys, #system
            path2,
            (0.0, 30.0), #time span
            Ybus_change;
            system_to_file = true,
        )
        @test sim.status == PSID.BUILT
        m_system = System(joinpath(path2, "initialized_system.json"))
        for b in get_components(Bus, m_system)
            b_sys = get_component(Bus, omib_sys, get_name(b))
            b_file = get_component(Bus, omib_sys_file, get_name(b))
            @test get_angle(b) == get_angle(b_sys)
            if get_bustype(b) == PSY.BusTypes.REF
                @test get_angle(b) == get_angle(b_file)
            else
                @test get_angle(b) != get_angle(b_file)
            end
        end

    finally
        @info("removing test files")
        rm(path2, force = true, recursive = true)
    end
end

@testset "Hybrid Line Indexing" begin
    ## Create threebus system with more dyn lines ##
    three_bus_file_dir = joinpath(dirname(@__FILE__), "data_tests/ThreeBusInverter.raw")
    threebus_sys_dyns = System(three_bus_file_dir, runchecks = false)
    add_source_to_ref(threebus_sys_dyns)

    dyn_branch12 =
        DynamicBranch(get_component(Branch, threebus_sys_dyns, "BUS 1-BUS 2-i_2"))
    dyn_branch23 =
        DynamicBranch(get_component(Branch, threebus_sys_dyns, "BUS 2-BUS 3-i_3"))

    add_component!(threebus_sys_dyns, dyn_branch12)
    add_component!(threebus_sys_dyns, dyn_branch23)

    # Attach dyn devices
    for g in get_components(Generator, threebus_sys_dyns)
        if get_number(get_bus(g)) == 102
            case_gen = dyn_gen_second_order(g)
            add_component!(threebus_sys_dyns, case_gen, g)
        elseif get_number(get_bus(g)) == 103
            case_inv = inv_case78(g)
            add_component!(threebus_sys_dyns, case_inv, g)
        end
    end

    # Tests for all Dynamic Lines
    sim = Simulation(ResidualModel, threebus_sys_dyns, mktempdir(), (0.0, 10.0))
    @test sim.status == PSID.BUILT
    sim_inputs = sim.simulation_inputs
    DAE_vector = PSID.get_DAE_vector(sim_inputs)
    @test all(DAE_vector)
    @test all(LinearAlgebra.diag(sim_inputs.mass_matrix) .> 0)
    total_shunts = PSID.get_total_shunts(sim_inputs)
    # Total shunts matrix follows same pattern as the rectangular Ybus
    for v in LinearAlgebra.diag(total_shunts[4:end, 1:3])
        @test v > 0
    end

    for v in LinearAlgebra.diag(total_shunts[1:3, 4:end])
        @test v < 0
    end

    for entry in LinearAlgebra.diag(sim_inputs.mass_matrix)
        @test entry > 0
    end
    voltage_buses_ix = PSID.get_voltage_buses_ix(sim_inputs)
    @test length(voltage_buses_ix) == 3
    @test isempty(PSID.get_current_buses_ix(sim_inputs))

    # Tests for dynamic lines with b = 0
    set_b!(dyn_branch12, (from = 0.0, to = 0.0))
    set_b!(dyn_branch23, (from = 0.0, to = 0.0))
    sim = Simulation(ResidualModel, threebus_sys_dyns, pwd(), (0.0, 10.0))
    @test sim.status == PSID.BUILT
    sim_inputs = sim.simulation_inputs
    DAE_vector = PSID.get_DAE_vector(sim_inputs)
    @test sum(.!DAE_vector) == 6
    for (ix, entry) in enumerate(DAE_vector)
        if !entry
            @test LinearAlgebra.diag(sim_inputs.mass_matrix)[ix] == 0
        elseif entry
            @test LinearAlgebra.diag(sim_inputs.mass_matrix)[ix] == 1
        else
            @test false
        end
    end

    total_shunts = PSID.get_total_shunts(sim_inputs)
    @test sum(LinearAlgebra.diag(total_shunts)) == 0.0
    voltage_buses_ix = PSID.get_voltage_buses_ix(sim_inputs)
    @test isempty(voltage_buses_ix)
end

@testset "Test Branch Perturbations" begin
    line_trip = BranchTrip(1.0, Line, "NON_EXISTING_LINE_NAME")
    @test_throws IS.ConflictingInputsError PSID.get_affect(omib_sys, line_trip)
    branch_mult = BranchImpedanceChange(1.0, Line, "NON_EXISTING_LINE_NAME", 2.0)
    @test_throws IS.ConflictingInputsError PSID.get_affect(omib_sys, branch_mult)
    line_name = PSY.get_name(first(get_components(Line, omib_sys)))
    branch_mult = BranchImpedanceChange(1.0, Line, line_name, -1.0)
    @test_throws IS.ConflictingInputsError PSID.get_affect(omib_sys, branch_mult)
end

@testset "Test Network Kirchoff Calculation" begin
    voltages = [
        1.05
        1.019861574381897
        0.0
        -0.016803841801155062
    ]
    V_r = voltages[1:2]
    V_i = voltages[3:end]
    ybus_ = PSY.Ybus(omib_sys).data
    I_balance_ybus = -1 * ybus_ * (V_r + V_i .* 1im)
    inputs = PSID.SimulationInputs(ResidualModel, omib_sys)
    I_balance_sim = zeros(4)
    PSID.network_model(inputs, I_balance_sim, voltages)
    for i in 1:2
        @test isapprox(real(I_balance_ybus[i]), I_balance_sim[i])
        @test isapprox(imag(I_balance_ybus[i]), I_balance_sim[i + 2])
    end
end

@testset "Test Network Modification Callback Affects" begin
    three_bus_file_dir = joinpath(dirname(@__FILE__), "data_tests/ThreeBusInverter.raw")
    threebus_sys = System(three_bus_file_dir, runchecks = false)
    add_source_to_ref(threebus_sys)
    # Attach dyn devices
    for g in get_components(Generator, threebus_sys)
        if get_number(get_bus(g)) == 102
            case_gen = dyn_gen_second_order(g)
            add_component!(threebus_sys, case_gen, g)
        elseif get_number(get_bus(g)) == 103
            case_inv = inv_case78(g)
            add_component!(threebus_sys, case_inv, g)
        end
    end

    ybus_original = PSY.Ybus(threebus_sys)

    inputs = PSID.SimulationInputs(ResidualModel, threebus_sys)

    for i in 1:3, j in 1:3
        complex_ybus = ybus_original.data[i, j]
        @test inputs.ybus_rectangular[i, j] == real(complex_ybus)
        @test inputs.ybus_rectangular[i + 3, j + 3] == real(complex_ybus)
        @test inputs.ybus_rectangular[i + 3, j] == -imag(complex_ybus)
        @test inputs.ybus_rectangular[i, j + 3] == imag(complex_ybus)
    end

    br = get_component(Line, threebus_sys, "BUS 1-BUS 3-i_1")
    PSID.ybus_update!(inputs, br, -1.0)

    remove_component!(threebus_sys, br)
    ybus_line_trip = PSY.Ybus(threebus_sys)

    # Use is approx because the inversion of complex might be different in
    # floating point than the inversion of a single float
    for i in 1:3, j in 1:3
        complex_ybus = ybus_line_trip.data[i, j]
        @test isapprox(inputs.ybus_rectangular[i, j], real(complex_ybus), atol = 1e-10)
        @test isapprox(
            inputs.ybus_rectangular[i + 3, j + 3],
            real(complex_ybus),
            atol = 1e-10,
        )
        @test isapprox(inputs.ybus_rectangular[i + 3, j], -imag(complex_ybus), atol = 1e-10)
        @test isapprox(inputs.ybus_rectangular[i, j + 3], imag(complex_ybus), atol = 1e-10)
    end
end
