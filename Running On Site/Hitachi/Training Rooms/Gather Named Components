for i, v in pairs(Component.GetComponents()) do
    print(i, v.Name, v.Type)
end


-- Get all components
local components = Component.GetComponents()
local listItems = {}

for i, v in pairs(components) do
    -- Format: "Name (Type)"
    table.insert(listItems, v.Name .. " (" .. v.Type .. ")")
end

table.sort(listItems)

-- Set the List Box choices
Controls.listNamedComponents.Choices = listItems