local Core = exports.vorp_core:GetCore()
local inventory = exports.vorp_inventory

RegisterServerEvent("vorp_weapons:addcomp", function(weaponid, added)
    local components = json.encode(added)
    if weaponid then
        local Parameters = { id = weaponid, comp = components }
        exports.oxmysql:execute("UPDATE loadout Set comps=@comp WHERE id=@id", Parameters)
    end
end)

RegisterServerEvent("syn_weapons:weaponused", function(data)
    local _source = source
    local id = data.id
    local hash = data.hash
    exports.oxmysql:execute('SELECT comps, used2 FROM loadout WHERE id = @id ', { id = id }, function(result)
        if result[1] then
            local components = json.decode(result[1].comps)
            TriggerClientEvent("vorp_weapons:givecomp", _source, components, id, hash)
        end
    end)
end)

RegisterServerEvent("vorp_weapons:checkmoney", function(sum)
    local _source = source
    local Character = Core.getUser(source).getUsedCharacter
    local currency = Config.General.customizationcurrency == 0 and Character.money or Character.gold

    if currency < sum then
        TriggerClientEvent("vorp_weapons:nomods", _source)
        Core.NotifyRightTip(_source, Config.Language.cantafford, 3000)
        return
    end

    Character.removeCurrency(0, sum)
    Core.NotifyRightTip(_source, Config.Language.craftingwepmods, 5000)
    TriggerClientEvent("vorp_weapons:applymods", _source)
end)


Core.Callback.Register("vorp_weapons:getjob", function(source, cb, args)
    local User = Core.getUser(source)
    local Character = User.getUsedCharacter
    local job = Character.job
    local rank = Character.jobGrade
    return cb({ job, rank })
end)

local function containsammo(table, element)
    for k, v in pairs(table) do
        if k == element then
            return v
        end
    end
    return 0
end

RegisterServerEvent("vorp_weapons:removeallammoserver", function()
    local _source = source
    inventory:removeAllUserAmmo(_source)
end)

CreateThread(function()
    for _, value in pairs(Config.ammo) do
        for _, m in pairs(value) do
            inventory:registerUsableItem(m.item, function(data)
                local _source = data.source
                local ammo = inventory:getUserAmmo(_source)
                local count = containsammo(ammo, m.key)

                if count >= m.maxammo or (m.qt + count) > m.maxammo then
                    return Core.NotifyObjective(_source, "cant use more ammo, max allowed reached", 5000)
                end

                inventory:subItem(_source, m.item, 1)
                inventory:addBullets(_source, m.key, m.qt)
            end)
        end
    end
end)

local function contains(table, element)
    for k, v in pairs(table) do
        if k == element then
            return true
        end
    end
    return false
end

RegisterServerEvent("vorp_weapons:addammo", function(wephash, qt, key, playeritem, item)
    local _source = source
    local Character = Core.getUser(_source).getUsedCharacter
    local identifier = Character.identifier
    local charidentifier = Character.charIdentifier
    local weapid
    local max

    exports.oxmysql:execute('SELECT name,id,ammo FROM loadout WHERE identifier=@identifier AND charidentifier = @charidentifier ', { ['identifier'] = identifier, ['charidentifier'] = charidentifier }, function(result)
        if result[1] then
            for i = 1, #result, 1 do
                if playeritem == 0 then
                    if GetHashKey(result[i].name) == wephash then
                        weapid = result[i].id
                    end
                elseif playeritem ~= 0 then
                    for k, v in pairs(playeritem) do
                        if v == result[i].name then
                            weapid = result[i].id
                        end
                    end
                end
            end
            for k, v in pairs(Config.ammo) do
                for l, m in pairs(v) do
                    if m.key == key then
                        max = m.maxammo
                    end
                end
            end
            if weapid then
                exports.oxmysql:execute('SELECT ammo FROM loadout WHERE id = @id ', { ['id'] = weapid }, function(result)
                    if result[1] then
                        local ammo = json.decode(result[1].ammo)
                        if contains(ammo, key) then
                            if (ammo[key] + qt) > max then
                                qt = max - ammo[key]
                                ammo[key] = max
                            else
                                ammo[key] = ammo[key] + qt
                            end
                        else
                            ammo[key] = tonumber(qt)
                        end
                        if qt > 0 then
                            inventory:addBullets(_source, key, qt)
                            exports.oxmysql:execute("UPDATE loadout Set ammo=@ammo WHERE id=@id", { id = weapid, ammo = json.encode(ammo) })
                        else
                            inventory:addItem(_source, item, 1)
                        end
                    end
                end)
            else
                inventory:addItem(_source, item, 1)
            end
        end
    end)
end)

local function contain(table, element)
    for k, v in pairs(table) do
        if v == element then
            return false
        end
    end
    return true
end

function SendWebhookMessage(webhook, message)
    if webhook ~= nil and webhook ~= "" and webhook ~= 0 then
        PerformHttpRequest(webhook, function()
            end,
            'POST',
            json.encode({ content = message }),
            {
                ['Content-Type'] = 'application/json' }
        )
    end
end

RegisterServerEvent("vorp_weapons:buyweapon", function(weapon, weaponData, v, shop)
    local _source = source
    local pedCoords = GetEntityCoords(GetPlayerPed(_source))
    local shopCoords = vector3(v.Pos.x, v.Pos.y, v.Pos.z)
    local distance = #(pedCoords - shopCoords)
    if distance > 3 then
        return print("Player: " .. GetPlayerName(_source) .. " tried to buy a weapon when he was not in the shop. possible cheat! current ped coords: " .. pedCoords .. " shop: " .. shop)
    end
    local Character = Core.getUser(_source).getUsedCharacter
    local playername = Character.firstname .. ' ' .. Character.lastname
    local money = Character.money
    local itemlabel = weapon
    local itemprice = weaponData.price
    local itemtobuy = weaponData.hashname

    if itemprice <= 0 then
        return print("trying to buy a weapon with price 0 possible exploit Player: " .. GetPlayerName(_source) .. " current coords " .. pedCoords .. " shop: " .. shop)
    end

    local canCarry = inventory:canCarryWeapons(_source, 1, nil, itemtobuy:upper())
    if not canCarry then
        Core.NotifyRightTip(_source, Config.Language.cantcarrywep, 3000)
        return
    end

    if money >= itemprice then
        Character.removeCurrency(0, itemprice)
        local message = Config.Language.vorp_weapons .. playername .. Config.Language.bought .. itemtobuy
        local adminwebhook = "" -- add here webhook
        SendWebhookMessage(adminwebhook, message)
        local ammo = { ["nothing"] = 0 }
        local components = { ["nothing"] = 0 }
        inventory:createWeapon(_source, itemtobuy:upper(), ammo, components)
        Core.NotifyRightTip(_source, Config.Language.youboughta .. itemlabel .. Config.Language.fors .. itemprice .. Config.Language.dollar, 3000)
    else
        Core.NotifyRightTip(_source, Config.Language.nomoney, 3000)
    end
end)

RegisterServerEvent("vorp_weapons:buyammo", function(d, j, v, count, shop)
    local _source = source
    local pedCoords = GetEntityCoords(GetPlayerPed(_source))
    local shopCoords = vector3(v.Pos.x, v.Pos.y, v.Pos.z)
    local distance = #(pedCoords - shopCoords)
    if distance > 3 then
        return print("Player: " .. GetPlayerName(_source) .. " tried to buy ammo when he was not in the shop. possible cheat! current ped coords: " .. pedCoords .. " shop: " .. shop)
    end

    local itemlabel = j
    local itemprice = d.price
    local itemtobuy = d.item
    local Character = Core.getUser(_source).getUsedCharacter
    local playername = Character.firstname .. ' ' .. Character.lastname
    local money = Character.money
    count = count or 1
    local total = itemprice * count

    local canCarry = inventory:canCarryItem(source, itemtobuy, count)
    if not canCarry then
        return Core.NotifyRightTip(_source, Config.Language.cantcarryitem, 3000)
    end

    if total <= 0 then
        return print("trying to buy an item with price 0 possible exploit Player: " .. GetPlayerName(_source) .. " current coords " .. pedCoords .. " shop: " .. shop)
    end

    if total < money then
        Character.removeCurrency(0, total)
        local message = Config.Language.vorp_weapons .. playername .. Config.Language.bought .. itemlabel
        local adminwebhook = "" -- add here webhook
        SendWebhookMessage(adminwebhook, message)
        inventory:addItem(_source, itemtobuy, count)
        Core.NotifyRightTip(_source, Config.Language.youboughta .. itemlabel .. Config.Language.fors .. total .. Config.Language.dollar, 3000)
    else
        Core.NotifyRightTip(_source, Config.Language.nomoney, 3000)
    end
end)

RegisterServerEvent("vorp_weapons:itemscheck", function(item, materials, craftcost)
    local _source = source
    local checkingtable = {}
    local accepted
    local Character = Core.getUser(_source).getUsedCharacter
    local charmoney = Character.money
    local playername = Character.firstname .. ' ' .. Character.lastname

    for k, v in pairs(materials) do
        local count = inventory:getItemCount(_source, nil, v.name)
        if count - v.amount >= 0 then
            accepted = "true"
        else
            accepted = "false"
        end
        table.insert(checkingtable, accepted)
    end

    local function subItems()
        for k, v in pairs(materials) do
            inventory:subItem(_source, v.name, v.amount)
        end
    end

    local function canCarryItems()
        local canCarry = inventory:canCarryItem(_source, item, 1)
        if not canCarry then
            return false
        end
        return true
    end

    if not canCarryItems() then
        TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
        return Core.NotifyRightTip(_source, Config.Language.cantcarryitem, 3000)
    end

    if not contain(checkingtable, "false") then
        TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
        Core.NotifyRightTip(_source, Config.Language.nomaterial, 3000)
        return
    end

    if Config.craftingcost then
        if charmoney >= craftcost then
            Character.removeCurrency(0, craftcost)
        else
            TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
            Core.NotifyRightTip(_source, Config.Language.nomoneycraft, 3000)
            return
        end
    end

    TriggerClientEvent("vorp_weapons:itemcheckpassed", _source)
    inventory:addItem(_source, item, 1)
    Core.NotifyRightTip(_source, Config.Language.crafting, 3000)
    local message = Config.Language.vorp_weapons .. playername .. Config.Language.crafted .. item
    local adminwebhook = "" -- add here admin webhook
    SendWebhookMessage(adminwebhook, message)
    subItems()
end)

RegisterServerEvent("vorp_weapons:itemscheck2", function(label, item, materials, craftcost)
    local _source = source
    local checkingtable = {}
    local accepted
    local Character = Core.getUser(_source).getUsedCharacter
    local charmoney = Character.money
    local playername = Character.firstname .. ' ' .. Character.lastname

    for k, v in pairs(materials) do
        Wait(100)
        local count = inventory:getItemCount(_source, nil, v.name)
        if count - v.amount >= 0 then
            accepted = "true"
        else
            accepted = "false"
        end
        table.insert(checkingtable, accepted)
    end

    if not contain(checkingtable, "false") then
        TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
        Core.NotifyRightTip(_source, Config.Language.nomaterial, 3000)
        return
    end

    local function subItem()
        for k, v in pairs(materials) do
            inventory:subItem(_source, v.name, v.amount)
        end
    end

    local function CanCarryWep()
        local canCarry = inventory:canCarryWeapons(_source, 1, nil, item:upper())
        if not canCarry then
            return false
        end
        return true
    end

    if not CanCarryWep() then
        TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
        Core.NotifyRightTip(_source, Config.Language.cantcarrywep, 3000)
        return
    end

    if Config.General.craftingcost then
        if charmoney >= craftcost then
            Character.removeCurrency(0, craftcost)
        else
            TriggerClientEvent("vorp_weapons:itemcheckfailed", _source)
            Core.NotifyRightTip(_source, Config.Language.nomoneycraft, 5000)
            return
        end
    end

    local ammo = { ["nothing"] = 0 }
    local components = { ["nothing"] = 0 }
    TriggerClientEvent("vorp_weapons:itemcheckpassed2", _source)
    inventory:createWeapon(_source, item, ammo, components)
    Core.NotifyRightTip(_source, Config.Language.crafting, 5000)
    local message = Config.Language.vorp_weapons .. playername .. Config.Language.crafted .. label
    local adminwebhook = "" -- add here webhook
    SendWebhookMessage(adminwebhook, message)
    subItem()
end)
