--[[
	Controls
	Configurable input bindings. Every entry is a list so several keys can map
	to the same action. Values may be Enum.KeyCode or Enum.UserInputType.
	Displayed names are used by the HUD so the help panel never lies.
]]

local Controls = {
	Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	Crouch = { Enum.KeyCode.LeftControl, Enum.KeyCode.C },
	-- Jump uses Roblox's default (Space) so mobile/gamepad keep working.
	ExtendHand = { Enum.UserInputType.MouseButton2, Enum.KeyCode.F },
	Grab = { Enum.UserInputType.MouseButton1 },
	Interact = { Enum.KeyCode.E },
	ReachIncrease = { Enum.KeyCode.X },
	ReachDecrease = { Enum.KeyCode.Z },
	ToggleHelp = { Enum.KeyCode.H },
}

-- Behaviour options
Controls.CrouchIsToggle = false -- false: hold to crouch
Controls.GrabIsToggle = false -- false: hold the button to keep the object

Controls.DisplayNames = {
	Sprint = "Shift",
	Crouch = "Ctrl / C",
	Jump = "Espacio",
	ExtendHand = "Clic der. / F",
	Grab = "Clic izq.",
	Interact = "E",
	Reach = "Rueda / Z-X",
	ToggleHelp = "H",
}

return Controls
