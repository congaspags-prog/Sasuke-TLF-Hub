-- SASUKE TLF HUB | SHARINGAN HORIZONTAL EDITION v1.0
-- The Lost Front | Client Luau (mobile + desktop)
-- Camera Aim / FOV / ESP / Visual / Movement. Sem dependencias HTTP.
-- NAO inclui alteracao de remotes de tiro (Silent Aim).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local environment = (type(getgenv) == "function" and getgenv()) or _G
if environment.SasukeTLF and type(environment.SasukeTLF.Close) == "function" then
    pcall(environment.SasukeTLF.Close)
end

local colors = {
    background = Color3.fromRGB(16, 13, 24),
    panel = Color3.fromRGB(30, 23, 41),
    raised = Color3.fromRGB(43, 32, 56),
    red = Color3.fromRGB(224, 62, 95),
    purple = Color3.fromRGB(169, 89, 246),
    ink = Color3.fromRGB(241, 232, 250),
    muted = Color3.fromRGB(173, 157, 191),
    grey = Color3.fromRGB(82, 73, 98),
    enemy = Color3.fromRGB(251, 86, 103),
    ally = Color3.fromRGB(89, 198, 244)
}

local defaults = {
    aim = false,
    fov = 155,
    smooth = 5,
    lead = 0.04,
    range = 650,
    showFov = true,
    wallCheck = true,
    teamCheck = true,
    stickyAim = true,
    headAim = true,
    esp = false,
    espAllies = false,
    espNames = true,
    espDistance = true,
    espHealth = true,
    speedOn = false,
    speed = 24,
    jumpOn = false,
    jump = 65,
    noFog = false,
    lowFX = true
}
local settings = {}
for key, value in pairs(defaults) do settings[key] = value end
local configFile = "SasukeTLF_v1.json"
local supportsFiles = type(readfile) == "function" and type(writefile) == "function"
if supportsFiles then
    local ok, data = pcall(function()
        return HttpService:JSONDecode(readfile(configFile))
    end)
    if ok and type(data) == "table" then
        for key, default in pairs(defaults) do
            if type(data[key]) == type(default) then
                if type(default) == "number" then
                    if data[key] == data[key] and math.abs(data[key]) < 10000 then
                        settings[key] = data[key]
                    end
                else
                    settings[key] = data[key]
                end
            end
        end
    end
end
-- Comeca com a mira e modificacoes de movimento desligadas, para teste seguro.
settings.aim = false
settings.speedOn = false
settings.jumpOn = false
local function save()
    if not supportsFiles then return end
    pcall(function()
        local data = {}
        for k in pairs(defaults) do data[k] = settings[k] end
        writefile(configFile, HttpService:JSONEncode(data))
    end)
end

local running = true
local minimized = false
local aimPressed = false
local mouseAiming = false
local currentTarget = nil
local targetClock = 0
local espClock = 0
local statsClock = 0
local moveClock = 0
local connections = {}
local espObjects = {}
local redrawn = {}
local originalFog = {End = Lighting.FogEnd, Start = Lighting.FogStart,
                     GlobalShadows = Lighting.GlobalShadows}
local oldSpeed, oldJump, oldJumpMode = nil, nil, nil

local function listen(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end
local function create(className, parent, props)
    local object = Instance.new(className)
    for property, value in pairs(props or {}) do object[property] = value end
    object.Parent = parent
    return object
end
local function round(parent, px)
    return create("UICorner", parent, {CornerRadius = UDim.new(0, px or 9)})
end
local function label(parent, text, size, color, props)
    local options = {
        BackgroundTransparency = 1,
        Text = text,
        Font = Enum.Font.GothamMedium,
        TextSize = size or 12,
        TextColor3 = color or colors.ink,
        TextXAlignment = Enum.TextXAlignment.Left
    }
    for k,v in pairs(props or {}) do options[k] = v end
    return create("TextLabel", parent, options)
end
local function validCharacter(p)
    local character = p and p.Character
    if not character then return nil end
    local hum = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then return character, hum, root end
end
local function isFriend(other)
    if other == localPlayer then return true end
    if localPlayer.Team and other.Team then
        return localPlayer.Team == other.Team
    end
    if localPlayer.Neutral == false and other.Neutral == false then
        return localPlayer.TeamColor == other.TeamColor
    end
    return false
end
local function aimPart(character)
    if settings.headAim then
        return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    end
    return character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("HumanoidRootPart")
end
local function canSee(camera, character, worldPoint)
    if not settings.wallCheck then return true end
    local me = localPlayer.Character
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = me and {me} or {}
    params.IgnoreWater = true
    local delta = worldPoint - camera.CFrame.Position
    if delta.Magnitude < 0.05 then return true end
    local hit = workspace:Raycast(camera.CFrame.Position, delta, params)
    return hit == nil or hit.Instance:IsDescendantOf(character)
end

-- Layout horizontal 620x352: encolhe automaticamente quando necessario.
local gui = create("ScreenGui", nil, {
    Name = "SasukeTLF_Sharingan", ResetOnSpawn = false,
    IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})
local attached = pcall(function()
    if type(gethui) == "function" then
        gui.Parent = gethui()
    else
        gui.Parent = CoreGui
    end
end)
if not attached or not gui.Parent then gui.Parent = localPlayer:WaitForChild("PlayerGui") end

local main = create("Frame", gui, {
    Name = "LandscapeHub", Size = UDim2.fromOffset(620, 352),
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
    BackgroundColor3 = colors.background, BorderSizePixel = 0,
    ClipsDescendants = true, Active = true
})
round(main, 15)
create("UIStroke", main, {Color = colors.purple, Thickness = 1.5, Transparency = 0.16})
local scaler = create("UIScale", main, {Scale = 1})
local function updateScale()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local viewport = cam.ViewportSize
    scaler.Scale = math.max(0.42, math.min(1, (viewport.X - 20) / 620,
                                              (viewport.Y - 24) / 352))
end
updateScale()

local header = create("Frame", main, {
    Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = colors.panel,
    BorderSizePixel = 0, Active = true
})
round(header, 14)
create("Frame", header, {Position = UDim2.new(0,0,1,-9),
    Size = UDim2.new(1,0,0,9), BackgroundColor3 = colors.panel, BorderSizePixel=0})
label(header, "◎", 31, colors.red, {
    Size=UDim2.fromOffset(39,42), Position=UDim2.fromOffset(13,3),
    Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Center
})
label(header, "SASUKE  //  THE LOST FRONT", 15, colors.ink, {
    Size=UDim2.fromOffset(330,21), Position=UDim2.fromOffset(56,4),
    Font=Enum.Font.GothamBold
})
label(header, "SHARINGAN EDITION   •   HORIZONTAL V1.0", 10, colors.muted, {
    Size=UDim2.fromOffset(340,18), Position=UDim2.fromOffset(56,25)
})
local function iconButton(text, x)
    local btn = create("TextButton", header, {
        Size=UDim2.fromOffset(31,28), Position=UDim2.fromOffset(x,10),
        Text=text, Font=Enum.Font.GothamBold, TextSize=18,
        TextColor3=colors.ink, BackgroundColor3=colors.grey, BorderSizePixel=0
    })
    round(btn, 7)
    return btn
end
local minBtn = iconButton("−", 540)
local exitBtn = iconButton("×", 578)

local side = create("Frame", main, {
    Position=UDim2.fromOffset(9,56), Size=UDim2.fromOffset(121,286),
    BackgroundColor3=colors.panel, BorderSizePixel=0
})
round(side, 10)
create("UIListLayout", side, {Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder})
local content = create("Frame", main, {
    Position=UDim2.fromOffset(138,56), Size=UDim2.fromOffset(473,286),
    BackgroundColor3=colors.panel, BorderSizePixel=0
})
round(content, 10)
local pageTitle = label(content, "AIM • SHARINGAN", 14, colors.ink, {
    Position=UDim2.fromOffset(12,6), Size=UDim2.fromOffset(452,23),
    Font=Enum.Font.GothamBold
})
local pageInfo = label(content, "Camera assistida, alvos e calibracao", 10, colors.muted, {
    Position=UDim2.fromOffset(12,28), Size=UDim2.fromOffset(452,19)
})
local pages, tabButtons = {}, {}
local order = {"AIM", "ESP", "MOV", "VISUAL", "CONFIG"}
local titles = {
    AIM={"AIM • SHARINGAN", "Prioridade: precisao e controle da camera"},
    ESP={"ESP • INIMIGOS", "Marcadores locais; aliados opcionais"},
    MOV={"MOVIMENTO", "Alteracoes locais; jogo pode restaurar valores"},
    VISUAL={"VISUAL", "Ajustes locais para visibilidade"},
    CONFIG={"CONFIGURACOES", "Economia de recursos e informacoes"}
}
for n, key in ipairs(order) do
    local tab = create("TextButton", side, {
        Name=key, LayoutOrder=n, Size=UDim2.fromOffset(121,44),
        BackgroundColor3=colors.raised, BorderSizePixel=0,
        Text=({AIM="◉   AIM", ESP="◇   ESP", MOV="»   MOVE",
               VISUAL="✦   VISUAL", CONFIG="⚙   CONFIG"})[key],
        TextColor3=colors.ink, TextSize=12, Font=Enum.Font.GothamBold
    })
    round(tab, 8)
    tabButtons[key] = tab
    local scroll = create("ScrollingFrame", content, {
        Name=key, Position=UDim2.fromOffset(10,54),
        Size=UDim2.fromOffset(452,222), BackgroundTransparency=1,
        BorderSizePixel=0, ScrollBarThickness=3,
        ScrollBarImageColor3=colors.purple,
        CanvasSize=UDim2.fromOffset(0,0),
        AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y,
        Visible=false
    })
    create("UIPadding", scroll, {PaddingRight=UDim.new(0,6),
        PaddingBottom=UDim.new(0,6)})
    create("UIListLayout", scroll, {
        SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,6)
    })
    pages[key]=scroll
end
local currentPage = "AIM"
local function openPage(name)
    currentPage = name
    for key, panel in pairs(pages) do
        panel.Visible = key == name
        tabButtons[key].BackgroundColor3 = key == name and colors.red or colors.raised
    end
    pageTitle.Text = titles[name][1]
    pageInfo.Text = titles[name][2]
end
for key, tab in pairs(tabButtons) do
    listen(tab.MouseButton1Click, function() openPage(key) end)
end

local function row(parent, height)
    local r = create("Frame", parent, {
        Size=UDim2.new(1,-7,0,height or 42), BackgroundColor3=colors.raised,
        BorderSizePixel=0
    })
    round(r, 8)
    return r
end
local function toggle(page, title, subtitle, key, onChange)
    local r=row(pages[page],48)
    label(r,title,12,colors.ink,{Position=UDim2.fromOffset(10,4),Size=UDim2.fromOffset(298,21)})
    label(r,subtitle,9,colors.muted,{Position=UDim2.fromOffset(10,25),Size=UDim2.fromOffset(320,15)})
    local btn=create("TextButton",r,{
        Position=UDim2.new(1,-80,0,9), Size=UDim2.fromOffset(69,30),
        BorderSizePixel=0, TextColor3=colors.ink,
        TextSize=11, Font=Enum.Font.GothamBold
    })
    round(btn,7)
    local function refresh()
        btn.Text=settings[key] and "ON" or "OFF"
        btn.BackgroundColor3=settings[key] and colors.red or colors.grey
    end
    table.insert(redrawn,refresh)
    listen(btn.MouseButton1Click,function()
        settings[key] = not settings[key]
        for _,render in ipairs(redrawn) do render() end
        if onChange then pcall(onChange,settings[key]) end
        save()
    end)
    refresh()
    return refresh
end
local function stepper(page, title, subtitle, key, minimum, maximum, step, formatter, changed)
    local r=row(pages[page],59)
    label(r,title,12,colors.ink,{Position=UDim2.fromOffset(10,4),Size=UDim2.fromOffset(298,21)})
    label(r,subtitle,9,colors.muted,{Position=UDim2.fromOffset(10,26),Size=UDim2.fromOffset(298,15)})
    local value=label(r,"",13,colors.purple,{
        Position=UDim2.new(1,-147,0,15),Size=UDim2.fromOffset(60,32),
        TextXAlignment=Enum.TextXAlignment.Center, Font=Enum.Font.GothamBold
    })
    local function small(text,x)
        local b=create("TextButton",r,{
            Size=UDim2.fromOffset(31,30),Position=UDim2.new(1,x,0,14),
            Text=text,TextSize=18,TextColor3=colors.ink,
            BackgroundColor3=colors.grey,Font=Enum.Font.GothamBold,
            BorderSizePixel=0
        })
        round(b,6)
        return b
    end
    local minus=small("−",-83)
    local plus=small("+",-46)
    local function refresh()
        value.Text=formatter and formatter(settings[key]) or tostring(settings[key])
    end
    table.insert(redrawn,refresh)
    for _, pair in ipairs({{minus,-1},{plus,1}}) do
        listen(pair[1].MouseButton1Click,function()
            settings[key]=math.clamp(settings[key]+pair[2]*step,minimum,maximum)
            if type(settings[key])=="number" then
                settings[key]=math.floor(settings[key]*100+0.5)/100
            end
            refresh()
            if changed then pcall(changed,settings[key]) end
            save()
        end)
    end
    refresh()
end
local function action(page,title,subtitle,buttonText,callback)
    local r=row(pages[page],48)
    label(r,title,12,colors.ink,{Position=UDim2.fromOffset(10,4),Size=UDim2.fromOffset(297,20)})
    label(r,subtitle,9,colors.muted,{Position=UDim2.fromOffset(10,25),Size=UDim2.fromOffset(325,14)})
    local b=create("TextButton",r,{
        Position=UDim2.new(1,-103,0,9),Size=UDim2.fromOffset(92,29),
        BackgroundColor3=colors.red,TextColor3=colors.ink,
        Text=buttonText,Font=Enum.Font.GothamBold,TextSize=11,BorderSizePixel=0
    })
    round(b,7)
    listen(b.MouseButton1Click,callback)
    return b
end
local function info(page,title,sub)
    local r=row(pages[page],46)
    label(r,title,12,colors.ink,{Position=UDim2.fromOffset(10,3),Size=UDim2.fromOffset(430,19)})
    label(r,sub,10,colors.muted,{Position=UDim2.fromOffset(10,24),Size=UDim2.fromOffset(428,16)})
    return r
end

-- Overlay: circulo central e marcador flutuante de mira.
local fovCircle=create("Frame",gui,{
    Name="FOV",AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(310,310),
    BackgroundTransparency=1,Visible=false
})
create("UICorner",fovCircle,{CornerRadius=UDim.new(1,0)})
create("UIStroke",fovCircle,{Color=colors.purple,Thickness=1.6,Transparency=0.18})
local aimButton=create("TextButton",gui,{
    Name="AIM_Toggle",Size=UDim2.fromOffset(113,49),
    Position=UDim2.new(1,-128,0.72,0),
    BackgroundColor3=colors.grey,BorderSizePixel=0,
    Text="◎ MIRA OFF",TextColor3=colors.ink,
    TextSize=12,Font=Enum.Font.GothamBold,Visible=false
})
round(aimButton,13)
create("UIStroke",aimButton,{Color=colors.red,Thickness=1.5})
local function aimDisplay()
    if not settings.aim then aimPressed=false end
    aimButton.Visible = settings.aim
    aimButton.Text = aimPressed and "◎ MIRA ON" or "◎ MIRA OFF"
    aimButton.BackgroundColor3 = aimPressed and colors.red or colors.grey
    fovCircle.Visible = settings.aim and settings.showFov
    fovCircle.Size=UDim2.fromOffset(settings.fov*2,settings.fov*2)
end
listen(aimButton.MouseButton1Click,function()
    aimPressed=not aimPressed
    currentTarget=nil
    aimDisplay()
end)

-- AIM: recomendacao para testes iniciais FOV 155 / Smooth 5 / Lead .04
-- Os disparos podem ser determinados por camera de arma diferente e nao seguir a camera do Roblox.
toggle("AIM","AIMBOT DA CAMERA","Ligar assistencia de mira para inimigos","aim",aimDisplay)
toggle("AIM","FOV VISIVEL","Circulo indicando area de aquisicao","showFov",aimDisplay)
toggle("AIM","VERIFICAR PAREDES","Nao selecionar inimigos atras de obstaculos","wallCheck")
toggle("AIM","IGNORAR ALIADOS","Priorizar somente adversarios","teamCheck")
toggle("AIM","ALVO FIXO","Evita trocas bruscas durante a mira","stickyAim")
toggle("AIM","MIRAR NA CABECA","OFF: mira no tronco","headAim")
stepper("AIM","TAMANHO DO FOV","Raio em pixels da tela", "fov",60,330,15,function(v) return tostring(v) end,aimDisplay)
stepper("AIM","SUAVIDADE","Menor = mais rapido; maior = mais suave","smooth",1,12,1)
stepper("AIM","ANTECIPACAO","Compensa parte do movimento do alvo","lead",0,0.18,0.02,function(v)
    return string.format("%.2f",v)
end)
stepper("AIM","DISTANCIA MAXIMA","Limite de procura de inimigos","range",100,1500,100)
action("AIM","PERFIL: PRECISAO","FOV menor e mira mais rapida","PRECISO",function()
    settings.fov=110;settings.smooth=3;settings.lead=0.04
    settings.wallCheck=true;settings.teamCheck=true
    settings.headAim=true;settings.stickyAim=true
    for _,render in ipairs(redrawn) do render() end
    aimDisplay()
    save()
end)
action("AIM","PERFIL: COMBATE","FOV amplo para confrontos proximos","AGRESSIVO",function()
    settings.fov=225;settings.smooth=2;settings.lead=0.08
    settings.wallCheck=true;settings.teamCheck=true
    settings.headAim=false;settings.stickyAim=true
    for _,render in ipairs(redrawn) do render() end
    aimDisplay()
    save()
end)
info("AIM","BOTAO 'MIRA' NA TELA","Toque para travar; no PC mantenha o botao direito pressionado")

-- ESP
toggle("ESP","ESP JOGADORES","Highlight atraves de estruturas do mapa","esp")
toggle("ESP","MOSTRAR ALIADOS","Se desligado, mostra somente inimigos","espAllies")
toggle("ESP","NOME DOS JOGADORES","Etiqueta no alto da cabeca","espNames")
toggle("ESP","DISTANCIA","Distancia ate cada jogador em studs","espDistance")
toggle("ESP","VIDA","Mostra vida atual na etiqueta","espHealth")
info("ESP","IDENTIFICACAO POR TIME","Vermelho: inimigos | Azul: aliados")

-- Movimento
toggle("MOV","VELOCIDADE EXTRA","Altera a velocidade local do personagem","speedOn")
stepper("MOV","WALK SPEED","Velocidade desejada (16 a 38)","speed",16,38,2)
toggle("MOV","PULO EXTRA","Modifica somente o pulo do avatar","jumpOn")
stepper("MOV","ALTURA DO PULO","Potencia do pulo (50 a 95)","jump",50,95,5)
info("MOV","MOVIMENTO NAO GARANTIDO","O servidor pode limitar ou redefinir velocidade e pulo")

local atmosphereOrig={}
local function applyGraphics()
    if not running then return end
    if settings.noFog then
        Lighting.FogStart=100000
        Lighting.FogEnd=100000
        for _, item in ipairs(Lighting:GetChildren()) do
            if item:IsA("Atmosphere") then
                if not atmosphereOrig[item] then
                    atmosphereOrig[item]={Density=item.Density,Haze=item.Haze}
                end
                item.Density=0
                item.Haze=0
            end
        end
    else
        Lighting.FogStart=originalFog.Start
        Lighting.FogEnd=originalFog.End
        for atm,old in pairs(atmosphereOrig) do
            if atm and atm.Parent then
                pcall(function() atm.Density=old.Density;atm.Haze=old.Haze end)
            end
        end
    end
    Lighting.GlobalShadows = not settings.lowFX and originalFog.GlobalShadows or false
end
-- Visual
toggle("VISUAL","SEM NEBLINA","Reduz o nevoeiro no seu cliente","noFog",applyGraphics)
toggle("VISUAL","GRAFICOS LEVES","Desativa sombras locais","lowFX",applyGraphics)
info("VISUAL","AJUSTE LOCAL","Alteracoes visuais nao afetam outros jogadores")

-- Config
toggle("CONFIG","MODO LEVE","Menos atualizacoes de busca e ESP","lowFX",applyGraphics)
local settingInfo=info("CONFIG","CONFIGURACOES SALVAS",supportsFiles and
    "Salvamento automatico disponivel no executor" or
    "Salvamento de arquivo indisponivel no executor")
info("CONFIG","COMPATIBILIDADE","Mira de camera: o FPS pode usar sistema proprio")
info("CONFIG","RISCO DE BAN","O jogo pode punir scripts nao autorizados")

openPage("AIM")
aimDisplay()
applyGraphics()

-- Draggable apenas pelo cabecalho (toque e mouse).
local dragStarted, dragPosition, dragOrigin, dragInput = false,nil,nil,nil
listen(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragStarted=true
        dragPosition=input.Position
        dragOrigin=main.Position
        dragInput=input
    end
end)
listen(UserInputService.InputChanged,function(input)
    if not dragStarted or not dragPosition or not dragOrigin then return end
    if input==dragInput or (dragInput and dragInput.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseMovement) then
        local offset=(input.Position-dragPosition)/scaler.Scale
        main.Position=UDim2.new(dragOrigin.X.Scale,dragOrigin.X.Offset+offset.X,
                                dragOrigin.Y.Scale,dragOrigin.Y.Offset+offset.Y)
    end
end)
listen(UserInputService.InputEnded,function(input)
    if input==dragInput then dragStarted=false;dragInput=nil end
end)
listen(UserInputService.InputBegan,function(input,processed)
    if not processed and input.UserInputType==Enum.UserInputType.MouseButton2 then
        mouseAiming=true
    end
end)
listen(UserInputService.InputEnded,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton2 then
        mouseAiming=false
    end
end)
listen(minBtn.MouseButton1Click,function()
    minimized=not minimized
    main.Size=UDim2.fromOffset(620,minimized and 48 or 352)
    side.Visible=not minimized
    content.Visible=not minimized
    minBtn.Text=minimized and "+" or "−"
end)

local function deleteEsp(p)
    local ob=espObjects[p]
    if ob then
        pcall(function() ob.high:Destroy() end)
        pcall(function() ob.tag:Destroy() end)
        espObjects[p]=nil
    end
end
local function showEsp(p)
    local character, hum, root=validCharacter(p)
    if not character or (isFriend(p) and not settings.espAllies) then
        deleteEsp(p)
        return
    end
    local ob=espObjects[p]
    if ob and ob.character~=character then
        deleteEsp(p)
        ob=nil
    end
    if not ob then
        local high=create("Highlight",character,{
            Name="SasukeTLF_ESP",Adornee=character,
            DepthMode=Enum.HighlightDepthMode.AlwaysOnTop,
            FillTransparency=0.78,OutlineTransparency=0.05
        })
        local head=character:FindFirstChild("Head") or root
        local tag=create("BillboardGui",head,{
            Name="SasukeTLF_Tag",Adornee=head,
            Size=UDim2.fromOffset(180,44),StudsOffset=Vector3.new(0,3,0),
            AlwaysOnTop=true,MaxDistance=1200
        })
        local text=label(tag,"",12,colors.ink,{
            Size=UDim2.fromScale(1,1),BackgroundTransparency=0.28,
            BackgroundColor3=colors.background,
            TextXAlignment=Enum.TextXAlignment.Center,
            TextYAlignment=Enum.TextYAlignment.Center,
            Font=Enum.Font.GothamBold
        })
        round(text,8)
        ob={character=character,high=high,tag=tag,text=text}
        espObjects[p]=ob
    end
    local friend=isFriend(p)
    local c=friend and colors.ally or colors.enemy
    ob.high.FillColor=c
    ob.high.OutlineColor=c
    ob.text.TextColor3=c
    local me=localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart")
    local distance=me and math.floor((root.Position-me.Position).Magnitude) or 0
    local pieces={}
    if settings.espNames then table.insert(pieces,p.DisplayName) end
    if settings.espDistance then table.insert(pieces,tostring(distance).." studs") end
    if settings.espHealth then table.insert(pieces,tostring(math.ceil(hum.Health)).." HP") end
    ob.tag.Enabled=#pieces>0
    ob.text.Text=table.concat(pieces," | ")
end

-- Target lock; somente camera local e calculo de tela.
local function targetData(camera, other)
    if other==localPlayer or (settings.teamCheck and isFriend(other)) then return nil end
    local char,hum,root=validCharacter(other)
    if not char then return nil end
    local part=aimPart(char)
    if not part or not part:IsA("BasePart") then return nil end
    local world=part.Position + root.AssemblyLinearVelocity * settings.lead
    local range=(world-camera.CFrame.Position).Magnitude
    if range>settings.range or range<1 then return nil end
    local screen,visible=camera:WorldToViewportPoint(world)
    if not visible or screen.Z<=0 then return nil end
    local center=camera.ViewportSize*0.5
    local pixels=(Vector2.new(screen.X,screen.Y)-center).Magnitude
    if pixels>settings.fov then return nil end
    if not canSee(camera,char,world) then return nil end
    return {player=other,point=world,pixels=pixels}
end
local function selectTarget(camera)
    if settings.stickyAim and currentTarget then
        local d=targetData(camera,currentTarget)
        if d then return d end
    end
    local best=nil
    for _,other in ipairs(Players:GetPlayers()) do
        local data=targetData(camera,other)
        if data and (not best or data.pixels<best.pixels) then best=data end
    end
    return best
end

local renderKey="SasukeTLF_Aim_"..tostring(localPlayer.UserId)
local function aimTick(dt)
    if not running then return end
    local camera=workspace.CurrentCamera
    if not camera then return end
    if settings.aim and (aimPressed or mouseAiming) then
        targetClock=targetClock+math.min(dt,0.1)
        local scanDelay=settings.lowFX and 0.14 or 0.075
        if targetClock>=scanDelay or not currentTarget then
            targetClock=0
            local chosen=selectTarget(camera)
            currentTarget=chosen and chosen.player or nil
        end
        if currentTarget then
            local d=targetData(camera,currentTarget)
            if d then
                local camPos=camera.CFrame.Position
                local desire=CFrame.lookAt(camPos,d.point)
                local blend=math.clamp(1-math.exp(-dt*(28/settings.smooth)),0.015,0.86)
                camera.CFrame=camera.CFrame:Lerp(desire,blend)
            else
                currentTarget=nil
            end
        end
    else
        currentTarget=nil
    end
end
local bindOK=pcall(function()
    RunService:BindToRenderStep(renderKey,Enum.RenderPriority.Camera.Value+2,aimTick)
end)
if not bindOK then listen(RunService.RenderStepped,aimTick) end

local bottom=label(gui,"",11,colors.ink,{
    Position=UDim2.new(0,12,1,-24),Size=UDim2.fromOffset(430,20),
    BackgroundColor3=colors.background, BackgroundTransparency=0.45
})
listen(RunService.Heartbeat,function(dt)
    if not running then return end
    espClock=espClock+dt
    moveClock=moveClock+dt
    statsClock=statsClock+dt
    if espClock>=(settings.lowFX and 0.65 or 0.35) then
        espClock=0
        if settings.esp then
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=localPlayer then
                    local ok=pcall(showEsp,p)
                    if not ok then deleteEsp(p) end
                end
            end
        else
            for p in pairs(espObjects) do deleteEsp(p) end
        end
    end
    if moveClock>=0.45 then
        moveClock=0
        local _,hum=validCharacter(localPlayer)
        if hum then
            if settings.speedOn then
                if oldSpeed==nil then oldSpeed=hum.WalkSpeed end
                pcall(function()hum.WalkSpeed=settings.speed end)
            elseif oldSpeed~=nil then
                pcall(function()hum.WalkSpeed=oldSpeed end)
                oldSpeed=nil
            end
            if settings.jumpOn then
                if oldJump==nil then
                    oldJump=hum.JumpPower
                    oldJumpMode=hum.UseJumpPower
                end
                pcall(function()
                    hum.UseJumpPower=true
                    hum.JumpPower=settings.jump
                end)
            elseif oldJump~=nil then
                pcall(function()
                    hum.UseJumpPower=oldJumpMode
                    hum.JumpPower=oldJump
                end)
                oldJump,oldJumpMode=nil,nil
            end
        else
            oldSpeed,oldJump,oldJumpMode=nil,nil,nil
        end
    end
    if statsClock>=0.75 then
        statsClock=0
        updateScale()
        local txt=settings.aim and "AIM ARMADO" or "AIM OFF"
        if settings.aim and (aimPressed or mouseAiming) then
            txt="MIRA ATIVA"..(currentTarget and (" • "..currentTarget.DisplayName) or " • BUSCANDO")
        end
        bottom.Text="◎ "..txt.."  |  ESP "..(settings.esp and "ON" or "OFF")
        aimDisplay()
    end
end)
listen(Players.PlayerRemoving,deleteEsp)

local function close()
    if not running then return end
    running=false
    pcall(function()RunService:UnbindFromRenderStep(renderKey)end)
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    for p in pairs(espObjects) do deleteEsp(p) end
    pcall(function()
        Lighting.FogEnd=originalFog.End
        Lighting.FogStart=originalFog.Start
        Lighting.GlobalShadows=originalFog.GlobalShadows
        for atmosphere,old in pairs(atmosphereOrig) do
            if atmosphere and atmosphere.Parent then
                atmosphere.Density=old.Density
                atmosphere.Haze=old.Haze
            end
        end
    end)
    local _,hum=validCharacter(localPlayer)
    if hum then
        pcall(function()
            if oldSpeed~=nil then hum.WalkSpeed=oldSpeed end
            if oldJump~=nil then
                hum.JumpPower=oldJump
                hum.UseJumpPower=oldJumpMode
            end
        end)
    end
    gui:Destroy()
    if environment.SasukeTLF and environment.SasukeTLF.Close==close then
        environment.SasukeTLF=nil
    end
end
listen(exitBtn.MouseButton1Click,close)
environment.SasukeTLF={Close=close,Version="1.0"}