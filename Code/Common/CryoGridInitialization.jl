module CryoGridInitialization
include("../Common/matlab.jl")
include("../StrataModules/CryoGridConstants.jl")
include("../StrataModules/CryoGridTempSaltFunctionalities.jl")
include("../Common/CryoGridTypes.jl")
#include("SEDIMENT_T.jl")
using MAT

    mutable struct Bottom
        PREVIOUS
        init_bottom::Function

        function Bottom() #constructor function
            #default values
            this = new()

            this.init_bottom = function(this, bottom_stratum)
                this.PREVIOUS = bottom_stratum;
                return this
            end
            return this
        end
    end

    mutable struct Top
        NEXT
        init_top::Function

        function Top() #constructor function
            #default values
            this = new()

            this.init_top = function(this, top_stratum)
                this.NEXT = top_stratum;
                return this
            end
            return this
        end
    end

end



# To do
#=
function [TOP_CLASS, BOTTOM_CLASS, TOP, BOTTOM] = assemble_stratigraphy(class_list, stratigraphy_list, grid, forcing)

%find STRAT_classes with index 1 and append  information from all other
%classes with index 1 to a variable_list

grid.variable_names = [];
grid.variable_gridded = [];

for i=1:size(stratigraphy_list,1)  %find STRAT_class in the list
    if stratigraphy_list{i,2}==1
        if strcmp(class(stratigraphy_list{i,1}), 'STRAT_classes')
            class_stratigraphy = stratigraphy_list{i,1};
        else
            grid.variable_names = [grid.variable_names stratigraphy_list{i,1}.variable_names];
            grid.variable_gridded = [grid.variable_gridded stratigraphy_list{i,1}.variable_gridded];
        end
    end
end


i=1;
for j=1:size(class_list,1)
    if strcmp(class(class_list{j,1}), class_stratigraphy.class_name{i,1}) && class_list{j,2}==class_stratigraphy.class_index(i,1)
        TOP_CLASS = copy(class_list{j,1}); %make an identical copy of the class stored in class_list -> classes in class_list are fully independet of the ones in class_list
        TOP_CLASS = initialize_STATVAR_from_file(TOP_CLASS, grid, forcing, class_stratigraphy.depth(i,:));
        CURRENT = TOP_CLASS;
    end
end

for i=2:size(class_stratigraphy.class_name,1)
    for j=1:size(class_list,1)
        if strcmp(class(class_list{j,1}), class_stratigraphy.class_name{i,1}) && class_list{j,2}==class_stratigraphy.class_index(i,1)
            CURRENT.NEXT = copy(class_list{j,1}); %make an identical copy of the class stored in class_list
            CURRENT.NEXT.PREVIOUS = CURRENT;
            CURRENT.NEXT = initialize_STATVAR_from_file(CURRENT.NEXT, grid, forcing, class_stratigraphy.depth(i,:));

            CURRENT = CURRENT.NEXT;
        end
    end
end
BOTTOM_CLASS = CURRENT;
BOTTOM=Bottom();
BOTTOM = init_bottom(BOTTOM, BOTTOM_CLASS);
BOTTOM_CLASS.NEXT = BOTTOM;
TOP=Top();
TOP = init_top(TOP, TOP_CLASS);
TOP_CLASS.PREVIOUS = TOP;
=#
