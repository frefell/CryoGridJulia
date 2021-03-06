module SEDIMENT_T
#provides sediment module, with state variables T
#a partial differential equation for temperature is solved
#total salt is temporal constant

include("../Common/matlab.jl")
include("../StrataModules/CryoGridConstants.jl")
include("CryoGridTempSaltFunctionalities.jl")
include("../Common/CryoGridTypes.jl")
using MAT
using Statistics


mutable struct stratum
    #mandatory variables
    CONST::CryoGridTypes.constants        #constants
    PARA::CryoGridTypes.parameter         #external service parameters, all other
    STATVAR::CryoGridTypes.statvar      #energy, water content, etc.
    TEMP::CryoGridTypes.temporary         #derivatives in prognostic timestep and optimal timestep
    CHILD::stratum      #pointer to child stratum
    PREVIOUS   #pointer to previous stratum
    NEXT       #pointer to next stratum
    IA_PREVIOUS #pointer to interaction with previous stata
    IA_NEXT #pointer to interaction with next stratum

    #mandatory functions
    initialize::Function
    initialize_statvar::Function
    get_boundary_condition_u::Function
    get_boundary_condition_l::Function
    get_derivatives_prognostic::Function
    get_timestep::Function
    compute_diagnostic_first_cell::Function
    advance_prognostic::Function
    compute_diagnostic::Function
    child::Function
    initializeFromFile::Function

    #-------------------------------------------------------------------------------
    #mandatory functions for each class
    function stratum() #constructor function
        #default values
        this = new()
        this.CONST = CryoGridTypes.constants([0.0], [0.0], [0.0], [0.0], [0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0])
        this.PARA = CryoGridTypes.parameter([0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0],[0.0], [0.0],[0.0], [0.0], [0.0])
        this.STATVAR = CryoGridTypes.statvar([0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0], [0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0])
        this.TEMP = CryoGridTypes.temporary([0.0], [0.0], [0.0], [0.0],[0.0], [0.0], [0.0], [0.0], [1])

        #initialize stratum
        this.initialize = function(this::stratum, sedimenttype, upperPos::Float64=0.0, lowerPos::Float64=-1000.0, layerThick=2.0)
            initialize_CONST(this);
            initialize_PARA(this);

            this.STATVAR.upperPos .= upperPos;
            this.STATVAR.lowerPos .= lowerPos;

            if length(layerThick) > 1.0
                this.STATVAR.layerThick = layerThick;
            else
                this.STATVAR.layerThick = dropdims(layerThick .* ones(Int64(floor(abs(lowerPos - upperPos)/layerThick)), 1), dims=2);
            end

            this.STATVAR.soilType .= sedimenttype.soilType;
            this.STATVAR.mineral .= sedimenttype.mineral;
            this.STATVAR.organic .= sedimenttype.organic;
            this.STATVAR.saltConc .= sedimenttype.salinity;

            return this
        end

        #initialize state variable, such as steady state
        this.initialize_statvar = function(this::stratum)
            initialize_STATVAR(this);

            return this
        end

        #initialize stratum from file
        #don't use initialize_STATVAR with this, that is already included
        this.initializeFromFile = function(this::stratum, parameters)
            initialize_CONST(this);
            initialize_PARA(this);

            midpoints = parameters[:,1];
            layers = midpoints + 0.5 .* [-(midpoints[1:end-1]-midpoints[2:end]); -(midpoints[end-1] - midpoints[end])];
            layers = [midpoints[1] + 0.5 .*(midpoints[1]-midpoints[2]); layers];

            if layers[end] >= 0.0
                this.STATVAR.upperPos .= -layers[1];
                this.STATVAR.lowerPos .= -layers[end];
            else
                this.STATVAR.upperPos .= layers[1];
                this.STATVAR.lowerPos .= layers[end];
            end

            this.STATVAR.layerThick = abs.(layers[2:end] - layers[1:end-1]);

            this.STATVAR.soilType = parameters[:,6];
            this.STATVAR.mineral = parameters[:,2];
            this.STATVAR.organic = parameters[:,4];
            this.STATVAR.saltConc = parameters[:,5];
            this.STATVAR.porosity = parameters[:,3];
            this.STATVAR.water = 1.0 .- this.STATVAR.organic .- this.STATVAR.mineral;

            # make sure Tmelt is in Kelvin
            if mean(parameters[:,9]) <= 0 #then the values are in degree C
                this.STATVAR.Tmelt = parameters[:,9] .+ 273.15;
            else
                this.STATVAR.Tmelt = parameters[:,9]
            end

            this.PARA.a = parameters[:,7];
            this.PARA.b = parameters[:,8];

            #Calculate initial condition T0
            T = CryoGridTempSaltFunctionalities.steadyState(this); #steady state
            #or spinup - put that here
            this.STATVAR.T = T;  #[degree C]

            #conductivity, heat capacity and liquid water content
            this = CryoGridTempSaltFunctionalities.getThermalProps_noSaltDiffusion(this);
            return this
        end

        #initialize state variable, such as steady state
        this.initialize_statvar = function(this::stratum)
            initialize_STATVAR(this);

            return this
        end

        #get boundary condition if this is the upper element of the stratigrahy
        this.get_boundary_condition_u = function(this::stratum, forcing) #functions specific for individual class, allow changing from Dirichlet to SEB
            #dirichlet condition with forcing temperature
            T_ub = forcing.TEMP.TForcing;
            thermCond = this.STATVAR.thermCond;
            layerThick = this.STATVAR.layerThick;
            T = this.STATVAR.T;
            #get uppermostGridCell
            #is always 1 if not read from file (version 2017)
            this.TEMP.uppermostGridCell = forcing.TEMP.uppermostGridCell;

            upperIndex = min(this.TEMP.uppermostGridCell[1], length(T)[1]); #we need to use this function before T was initialized as a vector.

            #calculate resulting flux and save temporary variables for conductivity and spatial derivative calculations
            this.TEMP.T_ub = T_ub; #for conductivity and initial steady state
            this.TEMP.heatFlux_ub = thermCond[upperIndex]*(T[upperIndex] .- T_ub) / abs(layerThick[upperIndex] ./ 2.0);#for spatial derivative
            return this
        end

        #boundary conditions for elements in the middle of the stratigrphy are
        #calculated in the interactions

        #get boundary condition if this is the lowest element of the stratigraphy
        this.get_boundary_condition_l = function(this::stratum, forcing)
            #geothermal heat flux prevails
            this.TEMP.heatFlux_lb = forcing.PARA.heatFlux_lb;

            return this
        end

        #calculate spatial derivative
        this.get_derivatives_prognostic = function(this::stratum)
            this.TEMP.divT = get_derivative_temperature_only(this); #this gives a vector
            return this
        end

        #get minimal timestep for this stratum element
        this.get_timestep = function(this::stratum)
            courant_number = minimum(0.5 * this.STATVAR.c_eff./this.STATVAR.thermCond[1:end-1] .* (this.STATVAR.layerThick).^2);
            timestep = courant_number/(3600.0*24.0); #convert estimate from seconds to days
            #timestep = max(timestep, 1) #no time steps smaller than 1 day
            return timestep
        end

        #calculate advance in time of state variables
        this.advance_prognostic = function(this::stratum, timestep::Float64) #real timestep derived as minimum of several classes in days
            timestep = timestep*3600.0*24.0; #convert timestep from days to seconds
            this.STATVAR.T = this.STATVAR.T + timestep .* this.TEMP.divT;

            return this
        end

        #calculate diagnostic variable that only happen if this stratum element is the
        #upper element in the stratigraphy
        this.compute_diagnostic_first_cell = function(this::stratum, forcing)
            #marine sedimentation could be happening here

            return this
        end

        #calculate diagnostic variables
        this.compute_diagnostic = function(this::stratum, forcing)
            #update conductivity, heat capacity and liquid water content
            this = CryoGridTempSaltFunctionalities.getThermalProps_noSaltDiffusion(this);

            #isostatic movement could happen here
            return this
        end

        return this
    end
end

#-------------------------------------------------------------------------------
#individual functions of this class

function initialize_CONST(this::stratum)
    this = CryoGridConstants.getGlobalConst(this);
    return this
end

function initialize_PARA(this::stratum)
    this = CryoGridConstants.getGlobalPara(this)
    return this
end

function initialize_STATVAR(this::stratum)
    midptDepth = this.STATVAR.upperPos .+ this.STATVAR.layerThick[1] ./ 2.0 .-  cumsum(this.STATVAR.layerThick, dims=1);

    #calculate porosity
    porosityZero = 1.0 .- (this.STATVAR.mineral + this.STATVAR.organic);
    bulkDensityZero = 1.0 ./ ((porosityZero .+ 0.6845) ./ 1.8);
    bulkDensity = bulkDensityZero .+ 0.0037 .* abs.(midptDepth) .^ 0.766; #abs to avoid imaginary numbers!
    porosity = 1.80 .* bulkDensity .^ (-1.0) .- 0.6845;
    porosity[porosity .< 0.03] .= 0.03;

    #update state variables to be vectors
    this.STATVAR.porosity = porosity;
    this.STATVAR.mineral = this.STATVAR.mineral .* (1.0 .- porosity) ./ (this.STATVAR.mineral .+ this.STATVAR.organic);
    this.STATVAR.organic = this.STATVAR.organic .* (1.0 .- porosity) ./ (this.STATVAR.mineral .+ this.STATVAR.organic);
    this.STATVAR.water = 1.0 .- this.STATVAR.organic .- this.STATVAR.mineral;
    this.STATVAR.saltConc = this.STATVAR.saltConc .* ones(size(porosity));

    #calculate state variables that depend on the more constant ones
    Tmelt, a, b = CryoGridTempSaltFunctionalities.calculateTmelt(this);
    this.STATVAR.Tmelt = Tmelt; #in Kelvin!
    this.PARA.a = a;
    this.PARA.b = b;

    #Calculate initial condition T0
    T = CryoGridTempSaltFunctionalities.steadyState(this); #steady state
    #or spinup - put that here
    this.STATVAR.T = T;  #[degree C]

    #conductivity, heat capacity and liquid water content
    this = CryoGridTempSaltFunctionalities.getThermalProps_noSaltDiffusion(this);

    return this
end

function get_derivative_temperature_only(this::stratum)
    #Read relevant data from this struct
    heatFlux_ub = this.TEMP.heatFlux_ub;    #should be generated in this.get_boundary_condition_u
    T_ub = this.TEMP.T_ub;
                                            #or in the interaction
    Q = this.TEMP.heatFlux_lb;              #should be generated in this.get_boundary_condition_l
                                            #or in the interaction
    T = this.STATVAR.T;

    layerDepth = [this.STATVAR.upperPos; this.STATVAR.upperPos .- cumsum(this.STATVAR.layerThick,dims=1)];
    midptDepth = this.STATVAR.upperPos .+ this.STATVAR.layerThick[1] ./ 2.0 .- cumsum(this.STATVAR.layerThick,dims=1);

    #determine bulk capacity and capacity
    c_temp = this.STATVAR.c_eff;

    #assign thermal conductivity
    #k lives on the edges, i.e. on layerDepth
    #however, we never need the last one
    thermCond = this.STATVAR.thermCond;

    #create output vector for temperature derivative
    divT = zeros(size(midptDepth));

    #calculate divergence
    #divT(i) = 1/c(i) (flux(i+1/2) - flux(i-1/2))/deltalayerDepth
    #where i is the position at a cell-midpoint, i.e. on midptDepth
    #and i +- 1/2 is the position at the cell-edge, i.e. on layerDepth

    #GhostCells above uppermostGridCell
    uppermostGridCell = this.TEMP.uppermostGridCell[1];

    @inbounds for i=1:uppermostGridCell-1
        divT[i]= thermCond[i]/c_temp[i]*(T_ub[1] .- T[i]) ./abs(layerDepth[i+1] .- layerDepth[i])^2;
    end

    #upper boundary condition
    #T(0) = TForcing
    #T(0) lives not on the midpoint of a ghost-cell,
    #but on the upper edge, hence the different deltaZ
    i = uppermostGridCell;
    divT[i] = (1.0 ./ c_temp[i]) * ( #conductivity of cell
                            thermCond[i+1]*(T[i+1] .- T[i]) ./ abs(midptDepth[i+1] .- midptDepth[i]) .- #flux lower edge of cell
                            heatFlux_ub[1]) ./ #flux upper edge of cell
                            abs(layerDepth[i+1] .- layerDepth[i]); #size of cell

    #derivative for soil
    @inbounds for i = uppermostGridCell+1:length(midptDepth) - 1
        divT[i]=(1.0 / c_temp[i]) * (
                            thermCond[i+1] * (T[i+1] - T[i]) / abs(midptDepth[i+1] - midptDepth[i]) - #flux lower edge
                            thermCond[i] * (T[i] - T[i-1]) / abs(midptDepth[i] - midptDepth[i-1])) / #flux upper edge
                            abs(layerDepth[i+1] - layerDepth[i]); #size of cell
    end

    #lower boundary condition
    # k(N+1)(T(N+1)-T(N))/(midptDepth(N+1) - midptDepth(N)) = Q
    #thermCond(N+1) is implicitely given in Q
    i = length(midptDepth);
    divT[i] = (1.0 / c_temp[i])*(
                            Q[1] .- #flux lower edge
                            thermCond[i] .* (T[i] .- T[i-1]) ./ abs(midptDepth[i] .- midptDepth[i-1])) ./ #flux upper edge
                            abs(layerDepth[i+1] .- layerDepth[i]); #size of cell

    return divT
end

end #module
