--[[
  ComponentControlsFinder - Class-Based Implementation (SIMPLIFIED)
  Author: Nikolas Smith
 20257-16  Firmware Req: 10.0  Version: 10.2  
  Refactored to follow class-based pattern for modularity and reusability
  Use this to find components and their controls for other scripts
  
  SIMPLIFIED:
  - Removed failed control access methods
  - Streamlined debugging
  - Kept only the working Properties-based approach
]]--

-- Define control references
local controls = {
    compFound = Controls.compFound,
    txtFoundControls = Controls.txtFoundControls, -- Optional: for UI display
}

-- Utility: Get controls table from a component instance (simplified)
local function getControlsTable(component)
    if not component or not component.Properties then 
        return nil 
    end
    
    -- Q-SYS stores controls as numbered properties in the Properties table
    local controlsFound = {}
    for k, v in pairs(component.Properties) do
        if type(k) == "number" and type(v) == "table" and v.Name then
            controlsFound[v.Name] = v
        end
    end
    
    return next(controlsFound) and controlsFound or nil
end

--** Class Definition **--------
ComponentControlsFinder = {}
ComponentControlsFinder.__index = ComponentControlsFinder

function ComponentControlsFinder.new(config)
    local self = setmetatable({}, ComponentControlsFinder)
    self.clearString = "[Clear]"
    self.debugging = (config and config.debugging) or true
    self.foundControls = {} -- Will store {name = controlName, type = controlType}
    self.selectedComponentName = nil
    self.sortByType = (config and config.sortByType) or false
    self.includeComponentsWithoutControls = (config and config.includeComponentsWithoutControls) or false
    self:init()
    return self
end

function ComponentControlsFinder:debugPrint(str)
    if self.debugging then print("[ComponentControlsFinder] " .. tostring(str)) end
end

-- Main init: set up event handler for component selection
function ComponentControlsFinder:init()
    if controls.compFound then
        controls.compFound.EventHandler = function()
            self:updateFoundControls()
        end
        -- Populate component choices and do initial population
        self:populateComponentChoices()
        self:updateFoundControls()
    else
        self:debugPrint("compFound control not found!")
    end
end

-- Populate the compFound combo box with all available component names
function ComponentControlsFinder:populateComponentChoices()
    if not controls.compFound then return end
    
    local componentNames = {}   
    local componentsWithControls = 0
    local totalComponents = 0
    
    -- Get all components from the system
    for _, comp in pairs(Component.GetComponents()) do
        totalComponents = totalComponents + 1
        if comp.Name and comp.Name ~= "" then
            local hasControls = comp.Properties and getControlsTable(comp)
            
            -- Only include components with controls, unless configured otherwise
            if hasControls or self.includeComponentsWithoutControls then
                table.insert(componentNames, comp.Name)
                if hasControls then
                    componentsWithControls = componentsWithControls + 1
                end
            end
        end
    end
    
    -- Sort alphabetically and add clear option
    table.sort(componentNames)
    table.insert(componentNames, self.clearString)
    
    -- Set the choices for the combo box
    controls.compFound.Choices = componentNames
    
    self:debugPrint(string.format("Found %d total components, %d with controls, showing %d in list", 
                    totalComponents, componentsWithControls, #componentNames - 1))
end

-- Update found controls for the selected component
function ComponentControlsFinder:updateFoundControls()
    local selectedName = controls.compFound and controls.compFound.String
    self.selectedComponentName = selectedName
    self.foundControls = {}
    
    if not selectedName or selectedName == self.clearString or selectedName == "" then
        self:debugPrint("No component selected or clear selected.")
        if controls.txtFoundControls then controls.txtFoundControls.String = "" end
        return
    end
    
    -- Find the component
    local comp = nil
    for _, c in pairs(Component.GetComponents()) do
        if c.Name == selectedName then
            comp = c
            break
        end
    end
    
    if not comp then
        self:debugPrint("Component not found: " .. tostring(selectedName))
        if controls.txtFoundControls then controls.txtFoundControls.String = "Component not found" end
        return
    end
    
    -- Get controls table
    local cTable = getControlsTable(comp)
    
    if not cTable then
        self:debugPrint("No controls found on component: " .. tostring(selectedName))
        if controls.txtFoundControls then controls.txtFoundControls.String = "No controls found" end
        return
    end
    
    -- Extract controls
    for k, v in pairs(cTable) do
        table.insert(self.foundControls, {name = k, type = type(v)})
    end
    
    -- Sort controls based on configuration
    if self.sortByType then
        self:sortControlsByType()
    else
        self:sortControlsByName()
    end
    
    self:debugPrint("Found " .. #self.foundControls .. " controls: " .. self:getControlNamesString())
    if controls.txtFoundControls then
        controls.txtFoundControls.String = self:getControlDisplayString()
    end
end

-- Sort controls alphabetically by name
function ComponentControlsFinder:sortControlsByName()
    table.sort(self.foundControls, function(a, b) return a.name < b.name end)
end

-- Sort controls by type, then by name within each type
function ComponentControlsFinder:sortControlsByType()
    table.sort(self.foundControls, function(a, b) 
        if a.type == b.type then
            return a.name < b.name
        else
            return a.type < b.type
        end
    end)
end

-- Get control names as comma-separated string
function ComponentControlsFinder:getControlNamesString()
    local names = {}
    for _, control in ipairs(self.foundControls) do
        table.insert(names, control.name)
    end
    return table.concat(names, ", ")
end

-- Get formatted display string with types
function ComponentControlsFinder:getControlDisplayString()
    if #self.foundControls == 0 then
        return "No controls found"
    end
    
    local lines = {}
    local currentType = nil
    
    for _, control in ipairs(self.foundControls) do
        if self.sortByType and control.type ~= currentType then
            currentType = control.type
            if #lines > 0 then table.insert(lines, "") end -- Add blank line between types
            table.insert(lines, "--- " .. currentType .. " ---")
        end
        table.insert(lines, control.name .. " (" .. control.type .. ")")
    end
    
    return table.concat(lines, "\n")
end

-- Toggle sorting method
function ComponentControlsFinder:toggleSorting()
    self.sortByType = not self.sortByType
    if self.sortByType then
        self:sortControlsByType()
    else
        self:sortControlsByName()
    end
    
    if controls.txtFoundControls then
        controls.txtFoundControls.String = self:getControlDisplayString()
    end
    
    self:debugPrint("Sorting changed to: " .. (self.sortByType and "by type" or "by name"))
end

-- Refresh component list (useful if components are added/removed dynamically)
function ComponentControlsFinder:refreshComponentList()
    self:populateComponentChoices()
    self:debugPrint("Component list refreshed")
end

-- Expose found controls for use by other scripts
function ComponentControlsFinder:getFoundControls()
    return self.foundControls
end

-- Get just the control names (for backward compatibility)
function ComponentControlsFinder:getFoundControlNames()
    local names = {}
    for _, control in ipairs(self.foundControls) do
        table.insert(names, control.name)
    end
    return names
end

-- Get controls filtered by type
function ComponentControlsFinder:getControlsByType(controlType)
    local filtered = {}
    for _, control in ipairs(self.foundControls) do
        if control.type == controlType then
            table.insert(filtered, control)
        end
    end
    return filtered
end

-- Get the currently selected component object
function ComponentControlsFinder:getSelectedComponent()
    if not self.selectedComponentName or self.selectedComponentName == self.clearString then
        return nil
    end
    
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Name == self.selectedComponentName then
            return comp
        end
    end
    return nil
end

-- Instantiate singleton for global use
_G.ComponentControlsFinder = ComponentControlsFinder.new({
    debugging = true,
    sortByType = false,
    includeComponentsWithoutControls = false -- Set to true to see all components
})