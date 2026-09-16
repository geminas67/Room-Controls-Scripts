--[[ 

  UCI Script Controls
  Author: Hope Roth, Q-SYS
  January, 2025
  Firmware Req: 9.12
  Version: 1.0
  
  ]] --

----* Constants and Variables *----

json = require("rapidjson")

-- a multi dimensional table used for page navigation
Pages = {
    {
        Buttons = {Controls.Nav_Intro},
        Layer = "Intro",
        SubLayers = {},
        CurrentSubLayer = 1,
        PageLabel = "An Introduction to CSS",
        Transition = "none",
        Instructions = Component.New("UCI Instructions")
    },
    {
        Buttons = {Controls.Nav_Text},
        Layer = "Text",
        ComboBox = Controls.Combo_TextType,
        SubLayers = {"Headers", "Fields", "ComboBoxes", "ListBoxes"},
        CurrentSubLayer = 1,
        PageLabel = "Text Options",
        Transition = "none",
        Instructions = Component.New("Text Instructions")
    },
    {
        Buttons = {Controls.Nav_Buttons},
        Layer = "Buttons",
        ComboBox = Controls.Combo_ButtonType,
        SubLayers = {"Standard", "Images", "Icons"},
        CurrentSubLayer = 1,
        PageLabel = "Button Options",
        Transition = "none",
        Instructions = Component.New("Buttons Instructions")
    },
    {
        Buttons = {Controls.Nav_Graphics},
        Layer = "Graphics",
        ComboBox = Controls.Combo_GraphicsType,
        SubLayers = {"GroupBoxes", "Polygons", "Base64"},
        CurrentSubLayer = 1,
        PageLabel = "Graphic Options",
        Transition = "none",
        Instructions = Component.New("Graphics Instructions")
    },
    {
        Buttons = {Controls.Nav_Meters},
        Layer = "Meters",
        ComboBox = Controls.Combo_MeterType,
        SubLayers = {"Classic", "Layer", "Filmstrip"},
        CurrentSubLayer = 1,
        PageLabel = "Meter Options",
        Transition = "none",
        Instructions = Component.New("Meters Instructions")
    },
    {
        Buttons = {Controls.Nav_Knobs},
        Layer = "Knobs",
        ComboBox = Controls.Combo_KnobType,
        SubLayers = {"Classic/Layer", "Filmstrip"},
        CurrentSubLayer = 1,
        PageLabel = "Knob Options",
        Transition = "none",
        Instructions = Component.New("Knobs Instructions")
    },
    {
        Buttons = {Controls.Nav_Faders},
        Layer = "Faders",
        ComboBox = Controls.Combo_FaderType,
        SubLayers = {"Classic", "Layer", "Filmstrip"},
        CurrentSubLayer = 1,
        PageLabel = "Fader Options",
        Transition = "none",
        Instructions = Component.New("Faders Instructions")
    }
}

-- the prompt in a group box that, when selected, reverts an associated UCI variable to blank
DefaultPrompt = "[CSS Default]"

-- border width options
BorderSizes = {
    "0px",
    "2px",
    "4px",
    "6px",
    "8px",
    "10px",
    "12px"
}

-- font selection options
Fonts = {
    "Adamina",
    "Droid Sans",
    "Lato",
    "Montserrat",
    "Noto Serif",
    "Open Sans",
    "Poppins",
    "Roboto",
    "Roboto Mono",
    "Roboto Slab",
    "Slabo 27px",
    "PlaywriteDEVAGuides",
    "Foglihten"
}

-- add the default prompt to all of our choices tables
table.insert(BorderSizes, DefaultPrompt)
table.insert(Fonts, DefaultPrompt)

----* Helper Functions *----

-- add sub-layer options to each sections combobox
function SetLayerCombo(page)
    local choicesTbl = {}
    for idx, v in ipairs(Pages[page].SubLayers) do -- iterate through the names of all the sublayers and add them to our options
        choicesTbl[idx] = {Text = v, Index = idx}
    end
    Pages[page].ComboBox.Choices = choicesTbl
    Pages[page].ComboBox.String = json.encode(choicesTbl[1]) -- default to the first option
end

-- show the page for the currently selected section
function ShowPage(page)
    ShowInstructions(page) -- update the instructions section
    Controls.Txt_PageLabel.String = Pages[page].PageLabel -- show the appropriate label at the bottom of the page
    for idx, v in pairs(Pages) do
        Uci.SetLayerVisibility("Main", v.Layer, idx == page, v.Transition) -- show the common layer for the selection section
        ShowSubLayer(idx) -- show the appropriate sub-layer
        for _, v2 in pairs(v.Buttons) do -- highlight the currently selected nav button
            v2.Value = idx == page
        end
    end
end

-- dynamically update the instructions text field based on the current layer and sub-layer.
function ShowInstructions(page)
    local currentSubLayer = Pages[page].CurrentSubLayer
    Controls.Txt_Instructions.String = Pages[page].Instructions["text." .. currentSubLayer].String
    Pages[page].Instructions["text." .. currentSubLayer].EventHandler = function(ctl)
        Controls.Txt_Instructions.String = ctl.String
    end
end

-- show the approprriate sub-section
function ShowSubLayer(page)
    local layer = Pages[page].Layer
    local currentSubLayer = Pages[page].CurrentSubLayer
    for idx, v in pairs(Pages[page].SubLayers) do
        Uci.SetLayerVisibility("Main", layer .. "-" .. v, page == CurrentPage and idx == currentSubLayer, "none")
    end
end

-- set the border width of the panel by updating a UCI variable
function SetBorder()
    if Controls.Txt_ListBox.String == DefaultPrompt then
        print("Default Border Selected")
        Uci.Variables.BorderDecoration.String = "" -- clear UCI variable string
    else
        print("Border Selected: " .. Controls.Txt_ListBox.String)
        Uci.Variables.BorderDecoration.String = Controls.Txt_ListBox.String -- set UCI variable to selected border size
    end
end

-- set the panel font by updating a UCI variable
function SetFont()
    if Controls.Combo_FontSelect.String == DefaultPrompt then
        print("Default Font Selected")
        Uci.Variables.MyFont.String = "" -- clear UCI variable string
    else
        print("Font Selected: " .. Controls.Combo_FontSelect.String)
        Uci.Variables.MyFont.String = "\""..Controls.Combo_FontSelect.String.."\"" -- set UCI variable to selected font
    end
end

-- encode an image using Base64, everything has been condensed into one function to make it easier to copy/paste to other files
function SetImage()
    EncodedImg = Component.New("Encoded Image")["text.1"] -- Base64 Encoded Image String
    EncodedImg.EventHandler = SetImage -- subscribe to updates in our image string
    
    -- check for blank image string
    if EncodedImg.String == "" then
        print("No Image Provided")
        return
    end

    -- many Online Image Encoders include header info. because we need the raw data, we are stripping out everything up to and including a comma
    local commaLocation = string.find(EncodedImg.String, ",") -- find where image data starts
    formattedImage = string.sub(EncodedImg.String, commaLocation + 1) -- return just the data

    Controls.Btn_Base64_Legend.Legend = '{"DrawChrome":false,"IconData":"' .. formattedImage .. '"}' -- Set the Image Using a Button's Legend
    Uci.Variables.BackgroundImage.String = "url('data:image/png;base64," .. formattedImage .. "')" -- Set the Image Using a UCI Variable and a CSS Variable
end

----* Event Handlers *----
Controls.Txt_ListBox.EventHandler = SetBorder -- change in listbox/border-width selection
Controls.Combo_FontSelect.EventHandler = SetFont -- change in combobox/font selection

-- Navigation Controls
for idx, v in ipairs(Pages) do -- nav buttons
    for _, v2 in ipairs(v.Buttons) do
        v2.EventHandler = function()
            CurrentPage = idx
            ShowPage(idx)
        end
    end
    if v.ComboBox then --subsection comboboxes
        SetLayerCombo(idx)
        v.ComboBox.EventHandler = function(ctl)
            local pageInfo = json.decode(ctl.String)
            Pages[idx].CurrentSubLayer = pageInfo.Index
            ShowSubLayer(idx)
            ShowInstructions(idx)
        end
    end
end

----* Always Run *----
Controls.Txt_ListBox.Choices = BorderSizes
Controls.Combo_FontSelect.Choices = Fonts

SetBorder()
SetFont()
ShowPage(1)
SetImage()

--[[
Copyright 2025 QSC, LLC
Permission is hereby granted, free of charge, to any person obtaining a copy 
of this softwareand associated documentation files (the "Software"), to deal 
in the Software without restriction, including without limitation the rights 
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is furnished
to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all 
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]] --
