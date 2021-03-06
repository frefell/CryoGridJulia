
module OUT_subseaPF
#this_SUBSEAPF Manage and save output data for subsea permafrost
#manages a struct with forcing data, info on the performance of the
#current run and stores the results at certain times
#saves the accumulated results at the final time or if the run breaks
include("../Common/CryoGridTypes.jl")
include("../Common/matlab.jl")
using Statistics
using MAT
#using Libc
#using Filesystem

mutable struct OUT

    RES::CryoGridTypes.outresults
    TEMP::CryoGridTypes.outtemporary
    PARA::CryoGridTypes.outparameter
    FORCING#::CryoGridTypes.forcingdata
    BREAK::Bool
    RUNINFO::CryoGridTypes.runinfo #save: anzahl echte zeitschritte, rechenzeit (gesamt)
    #provide_variables::Function
    initalize_from_file::Function
    complete_init_out::Function
    store_out::Function

    function OUT()
        this = new()

        this.initalize_from_file = function(this::OUT)
            this.TEMP = CryoGridTypes.outtemporary([0.0], [0.0], [1.0]);

            this.PARA = CryoGridTypes.outparameter([0.0], [0.0], [0.0], [0.0]);

            this.BREAK = false;
            this.RUNINFO = CryoGridTypes.runinfo([time()], [0.0], [1000.0], [0.0], [0.0])
            return this
        end

        this.complete_init_out = function(this::OUT, forcing)
            this.TEMP.out_time .= forcing.PARA.start_time[1]; #start saving on the first time step, days for main loop
            this.TEMP.out_index .= 1.0;
            this.PARA.save_time .= (forcing.PARA.end_time[1]); #days for main loop
            #lastDisp, dispInterval, save_time, output_timestep
            this.PARA.lastDisp .= this.TEMP.out_time[1] ./365.25 -100.0; #years
            this.PARA.dispInterval .= 1500.0; #years
            this.PARA.output_timestep .= 100; #years

            #save forcing data
            this.FORCING = deepcopy(forcing.DATA);
            depthInterp = -[-50.0:2.0:2000.0;]; #depth points that everything gets interpolated to
            timestamp = [this.TEMP.out_time[1] ./365.25:this.PARA.output_timestep[1]:this.PARA.save_time[1] ./365.25;]; #years for saving
            emptyRes = NaN64 .* ones(length(depthInterp), length(timestamp));

            this.RES = CryoGridTypes.outresults(timestamp,  depthInterp, deepcopy(emptyRes), deepcopy(emptyRes), deepcopy(emptyRes), deepcopy(emptyRes), deepcopy(emptyRes));

            return this
        end

        this.store_out = function(this::OUT, t, TOP, BOTTOM, forcing, savename::String)
            #check if run is without errors
            if isnan(mean(TOP.NEXT.STATVAR.T))
                println(string("Time is ", floor(t[1]/365.25), " - temperature is NAN - terminating!"))
                this.BREAK = true;
            end

            if hasfield(typeof(TOP.NEXT.STATVAR), :saltConc) && isnan(mean(TOP.NEXT.STATVAR.saltConc))
                println(string("Time is ", floor(t[1]/365.25), " - salt concentration is NAN - terminating!"))
                this.BREAK = true;
            end

            #display current state every now and then
            if mod(t[1]/365.25,this.PARA.dispInterval[1]) == 0 ||          abs(this.PARA.lastDisp[1] - t[1]/365.25) > this.PARA.dispInterval[1]

                this.PARA.lastDisp .= t ./ 365.25; #years

                println(string("Time is ", floor(t[1]/365.25), " years bfi"))
                println("Current Forcing Temperature")
                println(forcing.TEMP.TForcing)
            end

            #update runinfo every step
            this.RUNINFO.timesteps[1] += 1.0;
            #this.RUNINFO.dt_min = min(this.RUNINFO.dt_min, run_info.current_timestep) ;
            #this.RUNINFO.dt_max = max(thithis.STATVAR.upperPoss.RUNINFO.dt_max, run_info.current_timestep);

            if t==this.TEMP.out_time || this.BREAK == true
                out_index = Int64(this.TEMP.out_index[1]);

                T = Array{Float64,1}()
                saltConc = Array{Float64,1}()
                thermCond = Array{Float64,1}()
                c_eff = Array{Float64,1}()
                liqWater = Array{Float64,1}()
                midpointDepth = Array{Float64,1}()
                layerDepth = Array{Float64,1}()

                CURRENT = TOP.NEXT;
                while ~isequal(CURRENT, BOTTOM)
                    #global CURRENT
                    uppermostGridCell = CURRENT.TEMP.uppermostGridCell[1]; #should be 1 for all modules without sedimentation

                    T = cat(T, CURRENT.STATVAR.T[uppermostGridCell:end], dims=1);
                    if forcing.PARA.saltForcingSwitch[1] == 0 #no salt diffusion
                        saltConc = cat(saltConc, CURRENT.STATVAR.saltConc[uppermostGridCell:end]./CURRENT.STATVAR.porosity[uppermostGridCell:end] .*CURRENT.STATVAR.liqWater[uppermostGridCell:end], dims=1);
                    else
                        saltConc = cat(saltConc, CURRENT.STATVAR.saltConc[uppermostGridCell:end], dims=1);
                    end
                    thermCond = cat(thermCond, CURRENT.STATVAR.thermCond[uppermostGridCell:end], dims=1);
                    c_eff = cat(c_eff, CURRENT.STATVAR.c_eff[uppermostGridCell:end], dims=1);
                    liqWater = cat(liqWater, CURRENT.STATVAR.liqWater[uppermostGridCell:end], dims=1);

                    layers = [CURRENT.STATVAR.upperPos; CURRENT.STATVAR.upperPos .- cumsum(CURRENT.STATVAR.layerThick,dims=1)];
                    layerDepth = cat(layerDepth, layers[uppermostGridCell:end], dims=1);

                    midpoints = CURRENT.STATVAR.upperPos .+ CURRENT.STATVAR.layerThick[1] ./ 2.0 .- cumsum(CURRENT.STATVAR.layerThick,dims=1);
                    midpointDepth = cat(midpointDepth, midpoints[uppermostGridCell:end], dims=1);

                    CURRENT = CURRENT.NEXT;
                end


                this.RES.T[:,out_index] = matlab.interp1(-(midpointDepth), T, -(this.RES.depthInterp), "linear", NaN)

                #display current state every now and then
                if mod(t[1]/365.25,this.PARA.dispInterval[1]) == 0 ||          abs(this.PARA.lastDisp[1] - t[1]/365.25) > this.PARA.dispInterval[1]
                    println("Current Uppermost Temperature")
                    println(T[1])
                end

                this.RES.saltConc[:,out_index] = reverse(matlab.interp1(reverse(midpointDepth), reverse(saltConc), reverse(this.RES.depthInterp), "linear", NaN))
                this.RES.thermCond[:,out_index] = reverse(matlab.interp1(reverse(layerDepth), reverse(thermCond), reverse(this.RES.depthInterp), "linear", NaN))
                this.RES.c_eff[:,out_index] = reverse(matlab.interp1(reverse(midpointDepth), reverse(c_eff), reverse(this.RES.depthInterp), "linear", NaN))
                this.RES.liqWater[:,out_index] = reverse(matlab.interp1(reverse(midpointDepth), reverse(liqWater), reverse(this.RES.depthInterp), "linear", NaN))


                if t==this.PARA.save_time || this.BREAK == true && ~(savename=="")
                    #if savename is empty, don't save the results

                    this.RUNINFO.endtime .= time() .- this.RUNINFO.starttime;


                    if (savename[end-3:end] == ".mat")
                        saveloc = savename;
                    else
                        folder = "Results/" * savename;
                        mkpath(folder);

                        println("Save in folder " * folder )
                        file = savename * ".mat";
                        saveloc = folder * "/" * file;
                    end

                    f = matopen(saveloc, "w")
                    #save stuff

                    #save organic/mineral/porosity
                    organic = Array{Float64,1}()
                    mineral = Array{Float64,1}()
                    porosity = Array{Float64,1}()
                    layerDepth = Array{Float64,1}()

                    CURRENT = TOP.NEXT;
                    while ~isequal(CURRENT, BOTTOM)
                        #global CURRENT
                        uppermostGridCell = CURRENT.TEMP.uppermostGridCell[1]; #should be 1 for all modules without sedimentation

                        organic = cat(organic, CURRENT.STATVAR.organic[uppermostGridCell:end], dims=1);
                        mineral = cat(mineral, CURRENT.STATVAR.mineral[uppermostGridCell:end], dims=1);
                        porosity = cat(porosity, CURRENT.STATVAR.porosity[uppermostGridCell:end], dims=1);
                        layers = [CURRENT.STATVAR.upperPos; CURRENT.STATVAR.upperPos .- cumsum(CURRENT.STATVAR.layerThick,dims=1)];
                        layerDepth = cat(layerDepth, layers[uppermostGridCell:end], dims=1);

                        CURRENT = CURRENT.NEXT;
                    end


                    organic = matlab.interp1(-(midpointDepth), organic, -(this.RES.depthInterp), "linear", NaN)
                    mineral = matlab.interp1(-(midpointDepth), mineral, -(this.RES.depthInterp), "linear", NaN)
                    porosity = matlab.interp1(-(midpointDepth), porosity, -(this.RES.depthInterp), "linear", NaN)

                    if false
                        #this is already saved in the stratigraphy file
                        write(f,"organic", organic)
                        write(f,"mineral", mineral)
                        write(f,"porosity", porosity)

                        #timestamp
                        #forcingTemperature
                        #uppermosteGridCell
                        write(f, "FORCING", this.FORCING)

                        modernT = this.RES.T[:,end];
                        modernIce = this.RES.liqWater[:,end];
                        write(f,"modernT", modernT)
                        write(f,"modernIce", modernIce)
                        #modern ice content
                        #modern lpfb
                    end

                    #or can be calculated from what we save
                    #age
                    #age if T>0
                    age = 100.0 .*sum(.~ isequal.(this.RES.T,NaN), dims=2)
                    age_Tg0 = 100.0 .*sum(this.RES.T .> 0, dims=2);
                    write(f,"age", age)
                    write(f,"age_Tg0", age_Tg0)


                    #lat
                    #lon
                    #elevation
                    write(f, "Lat", forcing.PARA.latitude)
                    write(f, "Lon", forcing.PARA.longitude)
                    write(f, "Elevation", forcing.PARA.altitude)
                    write(f, "Q", forcing.PARA.heatFlux_lb)

                    #temperature in 2D, maybe less fine before -50k years
                    #write(f, "RESULTS", this.RES)
                    write(f,"time", this.RES.time)
                    write(f,"depth", this.RES.depthInterp)
                    write(f,"T", this.RES.T)

                    close(f)
                    this.BREAK = true;
                    println("end of simulation")
                else
                    this.TEMP.out_index[1] += 1.0;
                    this.TEMP.out_time .= this.RES.time[Int64(this.TEMP.out_index[1])].*365.25;

                end

            end
            return this
        end
        return this
    end
end
end
