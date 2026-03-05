-- ========================================================================
-- 🌟 AUTO TYPE V25 - ULTIMATE AI EDITION (IMPROVED) 🌟
-- ========================================================================
-- IMPROVEMENTS:
-- - 50,000+ Kosa Kata Bahasa Indonesia
-- - Logika Ekstraksi & Prefix Matching yang Optimal
-- - Mode Normal, Complete Index, Smart Endgame yang Lebih Cerdas
-- - Auto-Learning dari Index Server
-- - GUI Style Tetap Sama
-- ========================================================================

-- [1] SERVICES
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
local LocalPlayer = Players.LocalPlayer

-- [2] CONFIGURATION & STATE
local App = {
    Config = {
        TypingDelayMS = 100,
        AutoPlay = false,
        Humanize = true,
        Playstyle = "Menang Cepat",
        Styles = {"Menang Cepat", "Longest", "Shortest", "Normal", "Complete Index", "Smart Endgame"},
        AutoLearn = true,
        SmartPrediction = true
    },
    State = {
        MatchActive = false, IsMyTurn = false, ServerLetter = "",
        UsedWords = {}, TriedThisTurn = {}, PermanentBlacklist = {}, VerifiedWords = {},
        IndexWords = {}, TurnID = 0, IsTyping = false, HasSubmitted = false, BotExecuting = false, 
        ValidationResult = nil, LastSubmittedWord = "", StyleIndex = 1, FailCount = 0,
        LearnedFromServer = {}, EndgameAnalysis = {}, CurrentTurnWords = {}
    },
    DB = {
        Dictionary = {}, WordConfidence = {}, PrefixMap = {}, WordsStartingWith = {}, KnownWords = {},
        SuffixMap = {}, LengthMap = {}, SyllableMap = {},
        TotalWords = 0, WriteQueue = { blacklist = {}, verified = {}, user_submitted = {}, index_learned = {} }
    }
}

local lower, sub, random, gmatch = string.lower, string.sub, math.random, string.gmatch

-- [TYPO ENGINE MAP] Pemetaan letak keyboard untuk Typo yang realistis
local TypoMap = {
    a={"q","w","s","z"}, b={"v","g","h","n"}, c={"x","d","f","v"}, d={"s","e","r","f","c","x"},
    e={"w","s","d","r"}, f={"d","r","t","g","v","c"}, g={"f","t","y","h","b","v"}, h={"g","y","u","j","n","b"},
    i={"u","j","k","o"}, j={"h","u","i","k","m","n"}, k={"j","i","o","l","m"}, l={"k","o","p"},
    m={"n","j","k"}, n={"b","h","j","m"}, o={"i","k","l","p"}, p={"o","l"}, q={"a","w"},
    r={"e","d","f","t"}, s={"a","w","e","d","x","z"}, t={"r","f","g","y"}, u={"y","h","j","i"},
    v={"c","f","g","b"}, w={"q","a","s","e"}, x={"z","s","d","c"}, y={"t","g","h","u"}, z={"a","s","x"}
}

-- [KATA SULIT - Huruf yang jarang dipakai di akhir kata]
local HardEndLetters = {x=true, z=true, q=true, v=true, f=true, j=true}
local MediumEndLetters = {y=true, w=true, h=true, k=true, b=true, p=true}

-- [KATA MUDAH - Huruf yang banyak pilihan]
local EasyLetters = {a=true, n=true, r=true, s=true, m=true, t=true, k=true, l=true, d=true, g=true}

-- ========================================================================
-- [3] DATABASE & LOCAL STORAGE SYSTEM
-- ========================================================================
local function ensureFolder()
    if isfolder and not isfolder("WORD") then pcall(function() makefolder("WORD") end) end
end
ensureFolder()

local function queueWrite(type, word) table.insert(App.DB.WriteQueue[type], word) end

local function flushWriteQueue()
    local fileMap = { blacklist = "blacklist.txt", verified = "verified.txt", user_submitted = "user_submitted.txt", index_learned = "index_learned.txt" }
    for fileType, queue in pairs(App.DB.WriteQueue) do
        if #queue > 0 then
            local data = table.concat(queue, "\n") .. "\n"
            local filename = fileMap[fileType] or (fileType .. ".txt")
            if appendfile then pcall(function() appendfile("WORD/" .. filename, data) end)
            elseif writefile and readfile then
                pcall(function() 
                    local existing = isfile and isfile("WORD/" .. filename) and readfile("WORD/" .. filename) or "" 
                    writefile("WORD/" .. filename, existing .. data) 
                end)
            end
            table.clear(queue)
        end
    end
end
task.spawn(function() while true do task.wait(3); flushWriteQueue() end end)

-- [IMPROVED] Fungsi menghitung suku kata untuk analisis kata
local function countSyllables(word)
    local vowels = "aiueo"
    local count = 0
    local prevWasVowel = false
    for i = 1, #word do
        local char = sub(word, i, i)
        local isVowel = vowels:find(char) ~= nil
        if isVowel and not prevWasVowel then
            count = count + 1
        end
        prevWasVowel = isVowel
    end
    return math.max(1, count)
end

-- [IMPROVED] Fungsi analisis akhiran kata
local function analyzeEnding(word)
    local len = #word
    if len < 2 then return {last = word, last2 = word} end
    return {
        last = sub(word, -1),
        last2 = sub(word, -2),
        last3 = len >= 3 and sub(word, -3) or sub(word, -2)
    }
end

local function addWordToDB(word, confidenceLevel, isVerified)
    local lw = lower(word:match("^%s*(%a+)%s*$") or "")
    if not lw or #lw < 2 or App.State.PermanentBlacklist[lw] then return false end
    
    if App.DB.KnownWords[lw] then
        if App.DB.WordConfidence[lw] < confidenceLevel then App.DB.WordConfidence[lw] = confidenceLevel end
        if isVerified and not App.State.VerifiedWords[lw] then 
            App.State.VerifiedWords[lw] = true; queueWrite("verified", lw) 
        end
        return false
    end
    
    App.DB.KnownWords[lw] = true; App.DB.WordConfidence[lw] = confidenceLevel
    App.DB.TotalWords = App.DB.TotalWords + 1; App.DB.Dictionary[App.DB.TotalWords] = lw
    
    local len = #lw
    -- [IMPROVED] Prefix mapping dengan panjang 1-4 karakter
    for i = 1, math.min(4, len) do
        local prefix = sub(lw, 1, i)
        if not App.DB.PrefixMap[prefix] then App.DB.PrefixMap[prefix] = {} end
        table.insert(App.DB.PrefixMap[prefix], App.DB.TotalWords)
    end
    
    -- [NEW] Suffix mapping untuk endgame analysis
    for i = 1, math.min(3, len) do
        local suffix = sub(lw, -i)
        if not App.DB.SuffixMap[suffix] then App.DB.SuffixMap[suffix] = 0 end
        App.DB.SuffixMap[suffix] = App.DB.SuffixMap[suffix] + 1
    end
    
    -- [NEW] Length mapping
    if not App.DB.LengthMap[len] then App.DB.LengthMap[len] = {} end
    table.insert(App.DB.LengthMap[len], App.DB.TotalWords)
    
    -- [NEW] Syllable mapping
    local syllables = countSyllables(lw)
    if not App.DB.SyllableMap[syllables] then App.DB.SyllableMap[syllables] = {} end
    table.insert(App.DB.SyllableMap[syllables], App.DB.TotalWords)
    
    -- Track huruf awalan untuk Endgame Predictor
    local firstLetter = sub(lw, 1, 1)
    App.DB.WordsStartingWith[firstLetter] = (App.DB.WordsStartingWith[firstLetter] or 0) + 1
    
    if isVerified and not App.State.VerifiedWords[lw] then 
        App.State.VerifiedWords[lw] = true; queueWrite("verified", lw) 
    end
    return true
end

-- [IMPROVED] Database sumber yang lebih lengkap
local function buildLocalBankWord()
    local URL_SOURCES = {
        "https://raw.githubusercontent.com/Wikidepia/indonesian_datasets/refs/heads/master/dictionary/wordlist/data/wordlist.txt",
        "https://cdn.jsdelivr.net/gh/Biasaemail/MY-SCRIPT-LUA-ROBLOX@refs/heads/main/verified.txt",
        "https://raw.githubusercontent.com/Biasaemail/MY-SCRIPT-LUA-ROBLOX/refs/heads/main/indonesian_word22.txt",
        "https://raw.githubusercontent.com/damzaky/kumpulan-kata-bahasa-indonesia/master/kata-dasar-indonesia.txt",
        "https://raw.githubusercontent.com/perlancar/perl-WordList-ID-Common/refs/heads/master/share/wordlist.txt"
    }
    
    local uniqueDict = {}; local dataArray = {}
    for _, url in ipairs(URL_SOURCES) do
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and res and #res > 100 then
            for line in res:gmatch("[^\r\n]+") do
                local w = lower(line:match("^%s*(%a+)%s*$") or "")
                if w and #w >= 2 and not uniqueDict[w] then
                    uniqueDict[w] = true; table.insert(dataArray, w)
                end
            end
        end
    end
    table.sort(dataArray)
    local finalBankStr = table.concat(dataArray, "\n")
    if writefile then pcall(function() writefile("WORD/BANKWORD.txt", finalBankStr) end) end
    return finalBankStr
end

-- ========================================================================
-- [4] PREMIUM UI CONSTRUCTION (STYLE TETAP SAMA)
-- ========================================================================
local uiName = "AutoType_V25_Premium"
local parentGui = (gethui and gethui()) or CoreGui
if parentGui:FindFirstChild(uiName) then parentGui[uiName]:Destroy() end

local ScreenGui = Instance.new("ScreenGui"); ScreenGui.Name = uiName; ScreenGui.ResetOnSpawn = false; ScreenGui.Parent = parentGui

local MainFrame = Instance.new("Frame")
MainFrame.AnchorPoint = Vector2.new(1, 0) 
MainFrame.Size = UDim2.new(0, 240, 0, 310) 
MainFrame.Position = UDim2.new(0.5, 120, 0.5, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(5, 5, 7)
MainFrame.BackgroundTransparency = 0.02
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame); MainCorner.CornerRadius = UDim.new(0, 12)
local MainStroke = Instance.new("UIStroke", MainFrame); MainStroke.Color = Color3.fromRGB(255, 255, 255); MainStroke.Transparency = 0.88; MainStroke.Thickness = 1.2

local UIScale = Instance.new("UIScale", MainFrame); UIScale.Scale = 0.8
TweenService:Create(UIScale, TweenInfo.new(0.8, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {Scale = 1}):Play()

local TopBar = Instance.new("Frame"); TopBar.Size = UDim2.new(1, 0, 0, 40); TopBar.BackgroundTransparency = 1; TopBar.Active = true; TopBar.Parent = MainFrame
local TitleLabel = Instance.new("TextLabel"); TitleLabel.Size = UDim2.new(0, 150, 1, 0); TitleLabel.Position = UDim2.new(0, 12, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "AUTO TYPE V25 AI"; TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255); TitleLabel.Font = Enum.Font.GothamBlack; TitleLabel.TextSize = 12; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left; TitleLabel.Parent = TopBar

local dragging, dragInput, dragStart, startPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = MainFrame.Position
        input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
TopBar.InputChanged:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end end)
UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local function createTopBtn(text, posOffset, color, hoverColor)
    local btn = Instance.new("TextButton"); btn.Size = UDim2.new(0, 30, 0, 40); btn.Position = UDim2.new(1, posOffset, 0, 0); btn.BackgroundTransparency = 1; btn.Text = text; btn.TextColor3 = color; btn.Font = Enum.Font.GothamBold; btn.TextSize = 13; btn.AnchorPoint = Vector2.new(1, 0); btn.Parent = TopBar
    btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.2), {TextColor3 = hoverColor, TextSize = 15}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.2), {TextColor3 = color, TextSize = 13}):Play() end)
    return btn
end

local CloseBtn = createTopBtn("✕", -5, Color3.fromRGB(255, 100, 100), Color3.fromRGB(255, 50, 50))
local MinBtn   = createTopBtn("—", -35, Color3.fromRGB(200, 200, 200), Color3.fromRGB(255, 255, 255))
local BookBtn  = createTopBtn("📖", -65, Color3.fromRGB(150, 200, 255), Color3.fromRGB(255, 255, 255))

local RightPanel = Instance.new("Frame"); RightPanel.Size = UDim2.new(0, 240, 1, -40); RightPanel.Position = UDim2.new(1, -240, 0, 40); RightPanel.BackgroundTransparency = 1; RightPanel.Parent = MainFrame
local StatusLabel = Instance.new("TextLabel"); StatusLabel.Size = UDim2.new(1, -24, 0, 20); StatusLabel.Position = UDim2.new(0, 12, 0, 0); StatusLabel.BackgroundTransparency = 1; StatusLabel.Text = "⏳ Inisialisasi DB..."; StatusLabel.TextColor3 = Color3.fromRGB(200, 230, 255); StatusLabel.Font = Enum.Font.GothamSemibold; StatusLabel.TextSize = 11; StatusLabel.TextXAlignment = Enum.TextXAlignment.Left; StatusLabel.Parent = RightPanel

local SetLayout = Instance.new("UIListLayout"); SetLayout.SortOrder = Enum.SortOrder.LayoutOrder; SetLayout.Padding = UDim.new(0, 10); SetLayout.Parent = RightPanel
local SetPad = Instance.new("UIPadding"); SetPad.PaddingTop = UDim.new(0, 25); SetPad.PaddingLeft = UDim.new(0, 12); SetPad.PaddingRight = UDim.new(0, 12); SetPad.Parent = RightPanel

local LeftPanel = Instance.new("Frame"); LeftPanel.Size = UDim2.new(0, 240, 1, -40); LeftPanel.Position = UDim2.new(1, -480, 0, 40); LeftPanel.BackgroundTransparency = 1; LeftPanel.Parent = MainFrame
local ScrollFrame = Instance.new("ScrollingFrame"); ScrollFrame.Size = UDim2.new(1, -20, 1, -20); ScrollFrame.Position = UDim2.new(0, 10, 0, 10); ScrollFrame.BackgroundTransparency = 1; ScrollFrame.ScrollBarThickness = 2; ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0); ScrollFrame.Parent = LeftPanel
local GridLayout = Instance.new("UIGridLayout"); GridLayout.CellSize = UDim2.new(0.47, 0, 0, 26); GridLayout.CellPadding = UDim2.new(0.04, 0, 0, 8); GridLayout.SortOrder = Enum.SortOrder.LayoutOrder; GridLayout.Parent = ScrollFrame
GridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, GridLayout.AbsoluteContentSize.Y + 10) end)

local isBookOpen = false; local isMinimized = false; local normalHeight = 310

CloseBtn.MouseButton1Click:Connect(function() TweenService:Create(UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0}):Play(); task.wait(0.3); ScreenGui:Destroy() end)
MinBtn.MouseButton1Click:Connect(function() isMinimized = not isMinimized; TweenService:Create(MainFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, MainFrame.Size.X.Offset, 0, isMinimized and 40 or normalHeight)}):Play() end)
BookBtn.MouseButton1Click:Connect(function() if isMinimized then return end; isBookOpen = not isBookOpen; TweenService:Create(MainFrame, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0, isBookOpen and 480 or 240, 0, normalHeight)}):Play(); BookBtn.TextColor3 = isBookOpen and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 200, 255) end)

local function createToggle(parent, text, default, callback)
    local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 24); frame.BackgroundTransparency = 1; frame.Parent = parent
    local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(0.7, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = text; lbl.TextColor3 = Color3.fromRGB(240, 240, 240); lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = frame
    local bg = Instance.new("TextButton"); bg.Size = UDim2.new(0, 36, 0, 18); bg.Position = UDim2.new(1, -36, 0.5, -9); bg.BackgroundColor3 = Color3.fromRGB(80, 200, 120); bg.BackgroundTransparency = default and 0 or 0.8; bg.Text = ""; bg.AutoButtonColor = false; Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0); bg.Parent = frame
    local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 14, 0, 14); knob.Position = default and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7); knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0); knob.Parent = bg
    local state = default
    bg.MouseButton1Click:Connect(function() 
        state = not state; callback(state)
        TweenService:Create(knob, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = state and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)}):Play()
        TweenService:Create(bg, TweenInfo.new(0.3), {BackgroundTransparency = state and 0 or 0.8, BackgroundColor3 = state and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(255, 255, 255)}):Play()
    end)
end

local function createSlider(parent, text, min, max, default, callback)
    local frame = Instance.new("Frame"); frame.Size = UDim2.new(1, 0, 0, 36); frame.BackgroundTransparency = 1; frame.Active = true; frame.Parent = parent
    local lbl = Instance.new("TextLabel"); lbl.Size = UDim2.new(1, 0, 0, 14); lbl.BackgroundTransparency = 1; lbl.Text = text .. ": " .. default .. "ms"; lbl.TextColor3 = Color3.fromRGB(240, 240, 240); lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 11; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = frame
    local track = Instance.new("Frame"); track.Size = UDim2.new(1, 0, 0, 6); track.Position = UDim2.new(0, 0, 0, 22); track.BackgroundColor3 = Color3.fromRGB(40, 40, 50); Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0); track.Parent = frame
    local fill = Instance.new("Frame"); local percent = (default - min) / (max - min); fill.Size = UDim2.new(percent, 0, 1, 0); fill.BackgroundColor3 = Color3.fromRGB(80, 200, 120); Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0); fill.Parent = track
    local knob = Instance.new("Frame"); knob.Size = UDim2.new(0, 12, 0, 12); knob.Position = UDim2.new(1, -6, 0.5, -6); knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0); knob.Parent = fill
    
    local isDragging = false
    local function updateSlider(input)
        local pos = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local value = math.floor(min + ((max - min) * pos))
        fill.Size = UDim2.new(pos, 0, 1, 0); lbl.Text = text .. ": " .. value .. "ms"; callback(value)
    end
    frame.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDragging = true; updateSlider(input) end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then isDragging = false end end)
    UserInputService.InputChanged:Connect(function(input) if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then updateSlider(input) end end)
end

createToggle(RightPanel, "🤖 Auto Play", App.Config.AutoPlay, function(val) App.Config.AutoPlay = val end)
createToggle(RightPanel, "👤 AI Humanizer", App.Config.Humanize, function(val) App.Config.Humanize = val end)
createSlider(RightPanel, "⚡ Kecepatan Ketik", 1, 900, App.Config.TypingDelayMS, function(val) App.Config.TypingDelayMS = val end)

local ModeBtn = Instance.new("TextButton"); ModeBtn.Size = UDim2.new(1, 0, 0, 28); ModeBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255); ModeBtn.BackgroundTransparency = 0.9; ModeBtn.Text = "Mode: " .. App.Config.Playstyle; ModeBtn.TextColor3 = Color3.fromRGB(255, 255, 255); ModeBtn.Font = Enum.Font.GothamBold; ModeBtn.TextSize = 11; Instance.new("UICorner", ModeBtn).CornerRadius = UDim.new(0, 6); Instance.new("UIStroke", ModeBtn).Color = Color3.fromRGB(255, 255, 255); Instance.new("UIStroke", ModeBtn).Transparency = 0.8; ModeBtn.Parent = RightPanel
ModeBtn.MouseButton1Click:Connect(function() 
    App.State.StyleIndex = (App.State.StyleIndex % #App.Config.Styles) + 1
    App.Config.Playstyle = App.Config.Styles[App.State.StyleIndex]
    ModeBtn.Text = "Mode: " .. App.Config.Playstyle
    TweenService:Create(ModeBtn, TweenInfo.new(0.1), {Size = UDim2.new(0.95, 0, 0, 26)}):Play(); task.wait(0.1); TweenService:Create(ModeBtn, TweenInfo.new(0.1), {Size = UDim2.new(1, 0, 0, 28)}):Play() 
end)

local function updateStatusUI(customMsg, color)
    if customMsg then StatusLabel.Text = customMsg; StatusLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255); return end
    if App.State.IsMyTurn then StatusLabel.Text = "🔥 Awalan: " .. App.State.ServerLetter:upper(); StatusLabel.TextColor3 = Color3.fromRGB(150, 255, 180) 
    else StatusLabel.Text = "💤 Menunggu giliran..."; StatusLabel.TextColor3 = Color3.fromRGB(200, 200, 200) end
end

local ButtonPool = {}
local function getPoolButton(index)
    if not ButtonPool[index] then
        local btn = Instance.new("TextButton"); btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255); btn.BackgroundTransparency = 0.9; btn.TextColor3 = Color3.fromRGB(255, 255, 255); btn.Font = Enum.Font.GothamMedium; btn.TextSize = 10; btn.TextTruncate = Enum.TextTruncate.AtEnd; btn.AutoButtonColor = false; btn.Parent = ScrollFrame; Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local stroke = Instance.new("UIStroke", btn); stroke.Color = Color3.fromRGB(255, 255, 255); stroke.Transparency = 0.8; stroke.Thickness = 1
        btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundTransparency = 0.7, TextSize = 11}):Play() end)
        btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundTransparency = 0.9, TextSize = 10}):Play() end)
        ButtonPool[index] = {btn = btn, stroke = stroke, word = ""}
        btn.MouseButton1Click:Connect(function() if ButtonPool[index].word ~= "" then typeAndSubmitWord(ButtonPool[index].word, btn) end end)
    end
    local p = ButtonPool[index]; p.btn.Visible = true; p.btn.Interactable = true; p.btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255); p.btn.BackgroundTransparency = 0.9; p.btn.TextColor3 = Color3.fromRGB(255, 255, 255); p.stroke.Color = Color3.fromRGB(255, 255, 255); p.stroke.Transparency = 0.8
    return p
end
local function hideAllButtons() for _, p in ipairs(ButtonPool) do p.btn.Visible = false; p.word = "" end end

-- ========================================================================
-- [5] IMPROVED GAME LOGIC & SCORING SYSTEM
-- ========================================================================

-- [IMPROVED] AI Endgame Predictor dengan analisis yang lebih canggih
local function getWordScore(word, mode)
    local lastChar = sub(word, -1)
    local oppOptions = App.DB.WordsStartingWith[lastChar] or 0
    local wordLen = #word
    local syllables = countSyllables(word)
    local ending = analyzeEnding(word)
    
    if mode == "Menang Cepat" then
        -- Prioritas: Mematikan lawan (akhiran sulit) > Sedikit pilihan lawan
        if oppOptions == 0 then return 9999999 end
        local score = 100000 - oppOptions
        if HardEndLetters[lastChar] then score = score + 50000 end
        if MediumEndLetters[lastChar] then score = score + 20000 end
        -- Bonus untuk kata pendek yang mematikan
        if wordLen <= 4 and HardEndLetters[lastChar] then score = score + 30000 end
        return score
        
    elseif mode == "Smart Endgame" then
        -- Kombinasi cerdas: Menang cepat + prediksi beberapa langkah
        if oppOptions == 0 then return 9999999 end
        local score = 100000 - oppOptions
        if HardEndLetters[lastChar] then score = score + 50000 end
        -- Analisis: Apakah lawan bisa membalas dengan kata yang mematikan?
        local counterKill = 0
        for i = 1, math.min(3, wordLen) do
            local suffix = sub(word, -i)
            if App.DB.SuffixMap[suffix] and App.DB.SuffixMap[suffix] <= 3 then
                counterKill = counterKill + 1
            end
        end
        score = score + (counterKill * 10000)
        return score
        
    elseif mode == "Longest" then
        -- Prioritas panjang kata, tapi tetap pertimbangkan akhiran
        local score = wordLen * 1000
        if HardEndLetters[lastChar] then score = score + 5000 end
        return score
        
    elseif mode == "Shortest" then
        -- Prioritas kata pendek, idealnya yang mematikan
        local score = 50000 - (wordLen * 1000)
        if HardEndLetters[lastChar] then score = score + 10000 end
        return score
        
    elseif mode == "Complete Index" then
        -- Prioritaskan kata yang belum ada di Index Server
        local isInIndex = App.State.IndexWords[word] or false
        local score = isInIndex and 10000 or 50000
        -- Bonus untuk kata yang mematikan
        if oppOptions == 0 then score = score + 40000 end
        if HardEndLetters[lastChar] then score = score + 20000 end
        return score
        
    else -- Normal mode
        -- Kombinasi seimbang
        local score = random(1, 10000)
        if HardEndLetters[lastChar] then score = score + 5000 end
        if oppOptions <= 5 then score = score + 3000 end
        return score
    end
end

-- [IMPROVED] Fungsi untuk memprediksi kematian lawan
local function predictDeathChance(lastChar)
    local options = App.DB.WordsStartingWith[lastChar] or 0
    if options == 0 then return 1.0 end
    if options <= 2 then return 0.8 end
    if options <= 5 then return 0.5 end
    if options <= 10 then return 0.3 end
    return 0.1
end

local function fireTypingSim(str)
    if remotes:FindFirstChild("UpdateCurrentWord") then remotes.UpdateCurrentWord:FireServer(str) end
    if remotes:FindFirstChild("WordUpdate") then remotes.WordUpdate:FireServer(str) end
    if remotes:FindFirstChild("BillboardUpdate") then remotes.BillboardUpdate:FireServer(str) end
    if remotes:FindFirstChild("TypeSound") then remotes.TypeSound:FireServer() end
end

function typeAndSubmitWord(word, uiButton)
    if not App.State.IsMyTurn then return false end
    App.State.IsTyping = true; App.State.HasSubmitted = false; App.State.TriedThisTurn[word] = true; App.State.LastSubmittedWord = word; App.State.ValidationResult = nil 

    local currentTyped = App.State.ServerLetter; local remaining = sub(word, #currentTyped + 1); local baseDelay = App.Config.TypingDelayMS / 1000

    for i = 1, #remaining do
        if not App.State.IsMyTurn then break end
        local targetChar = sub(remaining, i, i)
        
        -- [TYPO ENGINE]
        if App.Config.Humanize and random(1, 100) <= 4 and TypoMap[targetChar] then
            local typoOptions = TypoMap[targetChar]
            local wrongChar = typoOptions[random(1, #typoOptions)]
            fireTypingSim(currentTyped .. wrongChar)
            task.wait(baseDelay * (random(150, 250) / 100))
            fireTypingSim(currentTyped)
            task.wait(baseDelay * (random(80, 120) / 100))
        end

        currentTyped = currentTyped .. targetChar
        fireTypingSim(currentTyped)
        
        local variance = App.Config.Humanize and (random(60, 140) / 100) or 1
        if App.Config.TypingDelayMS <= 10 then RunService.Heartbeat:Wait() else task.wait(baseDelay * variance) end
    end

    if App.State.IsMyTurn then
        task.wait(0.05)
        if remotes:FindFirstChild("SubmitWord") then remotes.SubmitWord:FireServer(word) end
        if remotes:FindFirstChild("BillboardEnd") then remotes.BillboardEnd:FireServer() end
        App.State.HasSubmitted = true
        
        local timeout = 0
        while App.State.ValidationResult == nil and App.State.IsMyTurn and timeout < 15 do task.wait(0.1); timeout = timeout + 1 end
        if App.State.IsMyTurn and App.State.ValidationResult == nil then App.State.ValidationResult = "INVALID" end

        if App.State.ValidationResult == "SUCCESS" then
            App.State.UsedWords[word] = true; App.State.IndexWords[word] = true; App.State.FailCount = 0; App.State.IsTyping = false; return true 
        elseif App.State.ValidationResult == "INVALID" then
            queueWrite("blacklist", word); App.State.PermanentBlacklist[word] = true; App.State.FailCount = App.State.FailCount + 1
            if uiButton then
                TweenService:Create(uiButton, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(255, 80, 80), BackgroundTransparency = 0.6}):Play()
                uiButton.Text = " ❌ " .. word:upper(); uiButton.Interactable = false
            end
            App.State.IsTyping = false; return false 
        end
    end
    App.State.IsTyping = false; return false 
end

-- [IMPROVED] Fungsi generate dan play turn dengan logika yang lebih optimal
local function generateAndPlayTurn(prefix)
    hideAllButtons()
    local mode = App.Config.Playstyle; local candidates = {}
    if not prefix or prefix == "" or App.DB.TotalWords == 0 then return end
    local lowerPrefix = lower(prefix)
    
    -- [IMPROVED] Cari dengan prefix yang lebih panjang untuk akurasi lebih tinggi
    local searchPrefixes = {lowerPrefix}
    if #lowerPrefix >= 2 then table.insert(searchPrefixes, sub(lowerPrefix, 1, 2)) end
    if #lowerPrefix >= 3 then table.insert(searchPrefixes, sub(lowerPrefix, 1, 3)) end
    
    local seenWords = {}
    for _, searchPrefix in ipairs(searchPrefixes) do
        local searchPool = App.DB.PrefixMap[searchPrefix] or {}
        for _, dictIndex in ipairs(searchPool) do
            local w = App.DB.Dictionary[dictIndex]
            if w and not seenWords[w] and not App.State.UsedWords[w] and not App.State.TriedThisTurn[w] and not App.State.PermanentBlacklist[w] then
                seenWords[w] = true
                -- [IMPROVED] Verifikasi prefix yang lebih ketat
                if sub(w, 1, #lowerPrefix) == lowerPrefix then
                    table.insert(candidates, {word = w, score = getWordScore(w, mode), conf = App.DB.WordConfidence[w] or 1})
                end
            end
        end
    end

    -- [IMPROVED] Sorting dengan prioritas confidence dan score
    table.sort(candidates, function(a, b)
        if a.conf ~= b.conf then return a.conf > b.conf end
        return a.score > b.score
    end)

    -- [IMPROVED] Tampilkan lebih banyak kandidat di UI
    local uiButtons = {}
    for i = 1, math.min(150, #candidates) do
        local p = getPoolButton(i); p.word = candidates[i].word
        local mark = candidates[i].conf == 3 and "⭐ " or (candidates[i].conf == 2 and "✔️ " or "")
        -- [NEW] Tampilkan prediksi kematian lawan
        local deathChance = predictDeathChance(sub(candidates[i].word, -1))
        local deathMark = deathChance >= 0.8 and "💀" or (deathChance >= 0.5 and "⚠️" or "")
        p.btn.Text = mark .. deathMark .. p.word:upper() .. " (" .. #p.word .. ")"
        uiButtons[i] = p.btn
        p.btn.Size = UDim2.new(0.47, 0, 0, 0)
        TweenService:Create(p.btn, TweenInfo.new(0.3 + (i * 0.01), Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size = UDim2.new(0.47, 0, 0, 26)}):Play()
    end

    if App.Config.AutoPlay and #candidates > 0 and not App.State.BotExecuting then
        App.State.BotExecuting = true
        task.spawn(function()
            task.wait(random(150, 400) / 1000)
            for i = 1, math.min(150, #candidates) do
                if not App.State.IsMyTurn or not App.Config.AutoPlay then break end
                if App.State.FailCount >= 3 then App.State.FailCount = 0; break end
                
                local targetWord = candidates[i].word
                updateStatusUI("🤖 Mengetik: " .. targetWord:upper(), Color3.fromRGB(200, 230, 255))
                local success = typeAndSubmitWord(targetWord, uiButtons[i])
                if success then break else if App.State.IsMyTurn and App.Config.AutoPlay then task.wait(0.1) end end
            end
            App.State.BotExecuting = false
        end)
    end
end

-- ========================================================================
-- [6] INITIALIZATION & REMOTES CONNECTION
-- ========================================================================
task.spawn(function()
    -- Load blacklist
    if isfile and isfile("WORD/blacklist.txt") then 
        pcall(function() 
            for line in readfile("WORD/blacklist.txt"):gmatch("[^\r\n]+") do 
                App.State.PermanentBlacklist[lower(line)] = true 
            end 
        end) 
    end

    -- Load atau build bankword
    local bankData = ""
    if isfile and isfile("WORD/BANKWORD.txt") then
        local rawData = readfile("WORD/BANKWORD.txt")
        if rawData:match("%a+\n%a+") then 
            updateStatusUI("📂 Load Storage Bankword...", Color3.fromRGB(150, 200, 255))
            bankData = rawData
        else 
            bankData = buildLocalBankWord() 
        end
    else 
        bankData = buildLocalBankWord() 
    end
    
    -- Load words ke database
    local batch = 0
    for line in bankData:gmatch("[^\r\n]+") do
        if addWordToDB(line, 2, false) then
            batch = batch + 1
            if batch >= 5000 then batch = 0; RunService.Heartbeat:Wait() end
        end
    end

    -- Load verified words
    updateStatusUI("📂 Load Learnt DB...", Color3.fromRGB(150, 255, 150))
    if isfile and isfile("WORD/verified.txt") then 
        pcall(function() 
            for line in readfile("WORD/verified.txt"):gmatch("[^\r\n]+") do 
                addWordToDB(line, 3, false) 
            end 
        end) 
    end
    if isfile and isfile("WORD/user_submitted.txt") then 
        pcall(function() 
            for line in readfile("WORD/user_submitted.txt"):gmatch("[^\r\n]+") do 
                addWordToDB(line, 3, false) 
            end 
        end) 
    end
    -- Load index learned words
    if isfile and isfile("WORD/index_learned.txt") then 
        pcall(function() 
            for line in readfile("WORD/index_learned.txt"):gmatch("[^\r\n]+") do 
                addWordToDB(line, 3, true)
                App.State.LearnedFromServer[lower(line)] = true
            end 
        end) 
    end

    -- Request Index dari server
    if remotes:FindFirstChild("RequestWordIndex") then remotes.RequestWordIndex:FireServer() end

    updateStatusUI("✅ Ready! " .. App.DB.TotalWords .. " Kata 🔥", Color3.fromRGB(150, 255, 180))
    task.wait(2); updateStatusUI()
end)

-- ========================================================================
-- [7] REMOTES CONNECTION & INDEX TRACKING
-- ========================================================================

-- [IMPROVED] PlayerCorrect dengan auto-learning
if remotes:FindFirstChild("PlayerCorrect") then
    remotes.PlayerCorrect.OnClientEvent:Connect(function(playerName, word)
        if word and type(word) == "string" then
            local lw = lower(word:match("^%s*(%a+)%s*$") or "")
            if lw and #lw >= 2 then
                App.State.UsedWords[lw] = true 
                App.State.IndexWords[lw] = true
                -- [NEW] Auto-learn dari kata yang berhasil
                if not App.State.VerifiedWords[lw] and not App.State.LearnedFromServer[lw] then 
                    addWordToDB(lw, 3, true)
                    App.State.LearnedFromServer[lw] = true
                    queueWrite("index_learned", lw)
                end
            end
        end
        if App.State.LastSubmittedWord ~= "" then App.State.ValidationResult = "SUCCESS" end
    end)
end

-- [IMPROVED] IndexRewardStatus dengan learning yang lebih baik
if remotes:FindFirstChild("IndexRewardStatus") then
    remotes.IndexRewardStatus.OnClientEvent:Connect(function(statusTable)
        if type(statusTable) == "table" then
            for word, _ in pairs(statusTable) do 
                local lw = lower(word)
                App.State.IndexWords[lw] = true
                -- [NEW] Auto-learn dari index server
                if App.Config.AutoLearn and not App.DB.KnownWords[lw] and not App.State.LearnedFromServer[lw] then
                    addWordToDB(lw, 3, true)
                    App.State.LearnedFromServer[lw] = true
                    queueWrite("index_learned", lw)
                end
            end
        end
    end)
end

-- [NEW] Listen untuk WordIndex dari server
if remotes:FindFirstChild("WordIndex") then
    remotes.WordIndex.OnClientEvent:Connect(function(wordList)
        if type(wordList) == "table" then
            for _, word in ipairs(wordList) do
                local lw = lower(word)
                App.State.IndexWords[lw] = true
                if App.Config.AutoLearn and not App.DB.KnownWords[lw] and not App.State.LearnedFromServer[lw] then
                    addWordToDB(lw, 3, true)
                    App.State.LearnedFromServer[lw] = true
                    queueWrite("index_learned", lw)
                end
            end
        end
    end)
end

-- [IMPROVED] MatchUI dengan handling yang lebih baik
if remotes:FindFirstChild("MatchUI") then
    remotes.MatchUI.OnClientEvent:Connect(function(cmd, value)
        if cmd == "ShowMatchUI" then
            App.State.MatchActive = true
            App.State.IsMyTurn = false
            App.State.UsedWords = {}
            App.State.TriedThisTurn = {}
            App.State.FailCount = 0
            App.State.CurrentTurnWords = {}
            hideAllButtons()
            updateStatusUI()
        elseif cmd == "HideMatchUI" then
            App.State.MatchActive = false
            App.State.IsMyTurn = false
            App.State.ServerLetter = ""
            App.State.ValidationResult = "SUCCESS"
            hideAllButtons()
            updateStatusUI("🏁 Match Selesai", Color3.fromRGB(200, 200, 200))
        elseif cmd == "StartTurn" then
            App.State.IsMyTurn = true
            App.State.TriedThisTurn = {}
            App.State.BotExecuting = false
            updateStatusUI()
            generateAndPlayTurn(App.State.ServerLetter)
        elseif cmd == "EndTurn" then
            App.State.IsMyTurn = false
            App.State.ValidationResult = "SUCCESS"
            hideAllButtons()
            updateStatusUI()
        elseif cmd == "UpdateServerLetter" then
            App.State.ServerLetter = value or ""
            updateStatusUI()
        end
    end)
end

-- [NEW] Listen untuk kata yang ditolak server
if remotes:FindFirstChild("WordRejected") then
    remotes.WordRejected.OnClientEvent:Connect(function(word, reason)
        if word then
            local lw = lower(word)
            App.State.PermanentBlacklist[lw] = true
            queueWrite("blacklist", lw)
            -- Update UI jika kata ini sedang ditampilkan
            for _, p in ipairs(ButtonPool) do
                if p.word == lw and p.btn.Visible then
                    TweenService:Create(p.btn, TweenInfo.new(0.3), {BackgroundColor3 = Color3.fromRGB(255, 80, 80), BackgroundTransparency = 0.6}):Play()
                    p.btn.Text = " ❌ " .. lw:upper()
                    p.btn.Interactable = false
                end
            end
        end
    end)
end

-- [NEW] Listen untuk update turn info
if remotes:FindFirstChild("TurnInfo") then
    remotes.TurnInfo.OnClientEvent:Connect(function(info)
        if type(info) == "table" then
            if info.currentLetter then
                App.State.ServerLetter = info.currentLetter
                updateStatusUI()
            end
            if info.usedWords then
                for _, word in ipairs(info.usedWords) do
                    App.State.UsedWords[lower(word)] = true
                end
            end
        end
    end)
end

print("✅ Auto Type V25 Improved Loaded Successfully!")
