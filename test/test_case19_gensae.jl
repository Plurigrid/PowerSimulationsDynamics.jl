"""
Validation PSSE/GENSAE:
This case study defines a three bus system with an infinite bus, GENSAE and a load.
The fault drop the line connecting the infinite bus and GENSAE.
"""

##################################################
############### SOLVE PROBLEM ####################
##################################################

#Define dyr files

names = [
    "GENSAE: Normal Saturation",
    #"GENSAE: High Saturation"
]

dyr_files = [
    joinpath(dirname(@__FILE__), "benchmarks/psse/GENSAE/ThreeBus_GENSAE.dyr"),
    #joinpath(dirname(@__FILE__), "benchmarks/psse/GENSAE/ThreeBus_GENSAE_HIGH_SAT.dyr"),
]

csv_files = (
    joinpath(dirname(@__FILE__), "benchmarks/psse/GENSAE/TEST_GENSAE.csv"),
    #joinpath(dirname(@__FILE__), "benchmarks/psse/GENSAE/TEST_GENSAE_HIGH_SAT.csv"),
)

init_conditions = [
    test_psse_gensae_init,
    #test_psse_gensae_high_sat_init
]

eigs_values = [test19_eigvals]

raw_file_dir = joinpath(dirname(@__FILE__), "benchmarks/psse/GENSAE/ThreeBusMulti.raw")
tspan = (0.0, 20.0)

function test_gensae_implicit(dyr_file, csv_file, init_cond, eigs_value)
    path = (joinpath(pwd(), "test-psse-gensae"))
    !isdir(path) && mkdir(path)
    try
        sys = System(raw_file_dir, dyr_file)

        #Define Simulation Problem
        sim = Simulation!(
            ImplicitModel,
            sys, #system
            path,
            tspan, #time span
            BranchTrip(1.0, "BUS 1-BUS 2-i_1"), #Type of Fault
        ) #Type of Fault

        #Obtain small signal results for initial conditions
        small_sig = small_signal_analysis(sim)
        eigs = small_sig.eigenvalues
        @test small_sig.stable

        #Solve problem
        execute!(sim, IDA(), dtmax = 0.005, saveat = 0.005)

        #Obtain data for angles
        series = get_state_series(sim, ("generator-102-1", :δ))
        t = series[1]
        δ = series[2]

        series2 = get_voltagemag_series(sim, 102)

        t_psse, δ_psse = get_csv_delta(csv_file)

        diff = [0.0]
        res = get_init_values_for_comparison(sim)
        for (k, v) in init_cond
            diff[1] += LinearAlgebra.norm(res[k] - v)
        end
        #Test Initial Condition
        @test (diff[1] < 1e-3)
        #Test Eigenvalues
        @test LinearAlgebra.norm(eigs - eigs_value) < 1e-3
        #Test Solution DiffEq
        @test sim.solution.retcode == :Success

        #Test Transient Simulation Results
        # PSSE results are in Degrees
        @test LinearAlgebra.norm(δ - (δ_psse .* pi / 180), Inf) <= 1e-1
        @test LinearAlgebra.norm(t - round.(t_psse, digits = 3)) == 0.0

    finally
        @info("removing test files")
        rm(path, force = true, recursive = true)
    end
end

function test_gensae_mass_matrix(dyr_file, csv_file, init_cond, eigs_value)
    path = (joinpath(pwd(), "test-psse-gensae"))
    !isdir(path) && mkdir(path)
    try
        sys = System(raw_file_dir, dyr_file)

        #Define Simulation Problem
        sim = Simulation!(
            MassMatrixModel,
            sys, #system
            path,
            tspan, #time span
            BranchTrip(1.0, "BUS 1-BUS 2-i_1"), #Type of Fault
        ) #Type of Fault

        #Obtain small signal results for initial conditions
        small_sig = small_signal_analysis(sim)
        eigs = small_sig.eigenvalues
        @test small_sig.stable

        #Solve problem
        execute!(sim, Rodas5(), dtmax = 0.005, saveat = 0.005)

        #Obtain data for angles
        series = get_state_series(sim, ("generator-102-1", :δ))
        t = series[1]
        δ = series[2]

        series2 = get_voltagemag_series(sim, 102)

        t_psse, δ_psse = get_csv_delta(csv_file)

        diff = [0.0]
        res = get_init_values_for_comparison(sim)
        for (k, v) in init_cond
            diff[1] += LinearAlgebra.norm(res[k] - v)
        end
        #Test Initial Condition
        @test (diff[1] < 1e-3)
        #Test Eigenvalues
        @test LinearAlgebra.norm(eigs - eigs_value) < 1e-3
        #Test Solution DiffEq
        @test sim.solution.retcode == :Success

        #Test Transient Simulation Results
        # PSSE results are in Degrees
        @test LinearAlgebra.norm(δ - (δ_psse .* pi / 180), Inf) <= 1e-1
        @test LinearAlgebra.norm(t - round.(t_psse, digits = 3)) == 0.0

    finally
        @info("removing test files")
        rm(path, force = true, recursive = true)
    end
end

@testset "Test 19 GENSAE ImplicitModel" begin
    for (ix, name) in enumerate(names)
        @testset "$(name)" begin
            dyr_file = dyr_files[ix]
            csv_file = csv_files[ix]
            init_cond = init_conditions[ix]
            eigs_value = eigs_values[ix]
            test_gensae_implicit(dyr_file, csv_file, init_cond, eigs_value)
        end
    end
end

@testset "Test 19 GENSAE MassMatrixModel" begin
    for (ix, name) in enumerate(names)
        @testset "$(name)" begin
            dyr_file = dyr_files[ix]
            csv_file = csv_files[ix]
            init_cond = init_conditions[ix]
            eigs_value = eigs_values[ix]
            test_gensae_mass_matrix(dyr_file, csv_file, init_cond, eigs_value)
        end
    end
end
