local Proxy = module("vrp","lib/Proxy")
vRP = Proxy.getInterface("vRP")
local config = module(GetCurrentResourceName(),"config")
tablesNames = {}
fieldsNames = {}
columnNames = {}
db = {}
SQL = {}
scheduler = {}
local nameOfTableScheduler = "gal_scheduler"
local mainUrlAPI = "https://localhost/v1/ps"
local UrlWS = "ws://localhost"
local headers = {
    ["Content-Type"] = "application/json",
    ["store-id-authorization"] = "Bearer "..config.token_loja,
    ["server-id-authorization"] = "Bearer "..config.token_servidor,
}
-----------------------------------------------------------------------------------------------------------------------------------------
--[ SCRIPT ]-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------------

local armazemDeDados = {}
local tentativa = 1
function startScript()
    Citizen.CreateThread(function()
        PerformHttpRequest(mainUrlAPI.."/info", function (errorCode, data, resultHeaders)
            if errorCode == 404 then
                sendErrorMessage("Não foi possível obter a rota de conexão.")
                return 
            elseif errorCode == 401 then
                sendErrorMessage("Nao foi possivel validar o token de acesso. Verifique se está correto ou acesse gal.com.br/app para obtê-lo.")
                return
            elseif errorCode >= 500 then
                sendErrorMessage("O sistema está instável no momento, aguarde a normalização")
                reconnectAPI()
                return
            elseif errorCode ~= 200 then
                sendErrorMessage(string.format("Ocorreu um erro ao conectar com a API. Cód. %d",errorCode)) 
                reconnectAPI()
                return
            end
                      
            --VERIFICA CASO EXISTE ALGUMA CONFIG PRO NOME DA DB DOS VEICULOS
            if config.vehicle_table == "" or config.vehicle_table == nil then
                sendErrorMessage("POR FAVOR CONFIGURE O NOME DA TABELA DOS VEICULOS DA DATABASE NA CONFIG.LUA")
                return
            end
    
            --VERIFICA CASO EXISTE ALGUMA CONFIG PRO NOME DA DB DOS HOMES
            if config.homes == "" or config.homes == nil then
                sendErrorMessage("POR FAVOR CONFIGURE O NOME DA TABELA DAS CASAS DA DATABASE NA CONFIG.LUA")
                return
            end

            data = json.decode(data)

            sendMessage("Plano:^6 "..data.loja.plano.nome.."^0 - ^6"..data.loja.message_expira.." ^0")
            db.inic() --Inicia DB
            db.mapTables() --Faz um mapeamento por todas as tabelas da database
            loadDatabaseServer() --Carrega a Database do servidor
            loadCommands() --Carrega os comandos
            setFramework() --Seta a framework da base
            verifyTableSheduler() --Verifica se tem a tabela scheduler da gal
            startWS() --Inicia o servidor websocket
            work() --Começa a verificar se existe algum comando pendente para ser executado
            

            --print(Commands["ADD_GROUP"]({ user_id = 1, value = 'Gold' }))
            --print(Commands["REMOVE_GROUP"]({ user_id = 1, value = 'Gold'}))
            --print(Commands["ADD_MONEY"]({ user_id = 1, value = 10 }))
            --print(Commands["REMOVE_MONEY"]({ user_id = 1, value = 10 }))
            --print(Commands["ADD_VEHICLE"]({ user_id = 1, value = 'panto' }))
            --print(Commands["REMOVE_VEHICLE"]({ user_id = 1, value = 'panto' }))
            --print(Commands["ADD_HOME"]({ user_id = 2, value = 'LX01' }))
            --print(Commands["REMOVE_HOME"]({ user_id = 1, value = 'LX01' }))
            --print(Commands["ADD_ITEM"]({ user_id = 1, value = 'agua', amount = 10 }))
            --print(Commands["ADD_BAN"]({ user_id = 1 }))
            --print(Commands["REMOVE_BAN"]({ user_id = 1}))
            --print(Commands["SYSTEM_NOTIFY"]({ user_id = 1, invoice_id = 156}))
            --print(Commands["SQL_CODE"]({ user_id = 1, value = 'UPDATE vrp_users SET whitelisted = 1 WHERE id = {user_id}'}))
          end, "GET", "", headers)
    end)
end

function loadDatabaseServer()
    local db = GetConvar("mysql_connection_string", "")
    local infoDB = {}
    if(config.debug_mode) then
        sendDebugMessage(db)
    end
    if string.find(db, "mysql://", 1, true) ~= nil then
        -- Extrai o elemento "root"
        local root = string.match(db, "://([^@]+)@")
        infoDB['uid'] = root
        
        -- Extrai o elemento "127.0.0.1"
        local ip = string.match(db, "@([^/]+)")
        ip = string.sub(ip, 1) -- remove o "@" do início
        infoDB['server'] = ip
        
        -- Extrai o elemento "creativev5"
        local db2 = string.match(db, ip.."/([^%?]+)")
        db2 = string.sub(db2, 1) -- remove a "/" do início
        infoDB['database'] = db2
    else
        for key, value in db:gmatch("([^=]+)=([^;]*)") do
            key = key:gsub("host(name)?|ip|server|data%s?source|addr(ess)?", "host"):gsub("user%s?(id|name)?|uid", "user"):gsub("pwd|pass", "password"):gsub("db", "database")
            key = key:gsub(";", "") -- remove o ponto e vírgula da chave, se houver
            infoDB[key] = value
        end
    end
    config.database = {
        ip = infoDB.server,
        user = infoDB.uid,
        password = infoDB.password or '',
        databaseName = infoDB.database
    }
end

function verifyTableSheduler()
    local result, value = pcall(function()
        local has_table = db.hasTable(nameOfTableScheduler)
        
        if not has_table then
            local query2 = "CREATE TABLE "..nameOfTableScheduler.." ( id bigint(20) NOT NULL AUTO_INCREMENT, user_id varchar(255) NOT NULL, command varchar(255) NOT NULL, value varchar(255) NOT NULL, amount bigint(20) DEFAULT NULL, execute_at datetime NOT NULL DEFAULT current_timestamp(), PRIMARY KEY (id) )"
            db.query("gal_addTableSheduler", query2)
            if(config.debug_mode) then
                sendDebugMessage("Criando tabela sheduler database...")
            end
        end
    end)
        
    if not result then
        error(value)
    end
end

function prettyCommandName(e)
    if e == "REMOVE_GROUP" then
      return "Remocao do grupo"
    elseif e == "REMOVE_HOME" then
      return "Remocao da propriedade"
    elseif e == "REMOVE_VEHICLE" then
      return "Remocao do veículo"
    end
end

function commandDisplay(e)
    if e == "REMOVE_GROUP" then
        return "GRUPO"
    elseif e == "REMOVE_HOME" then
        return "CASA"
    elseif e == "REMOVE_VEHICLE" then
        return "VEICULO"
    end
end

function formatDate(e, t)
    t = t or false
    local i = os.date("*t", e/1000)
    local dateString = string.format("%02d/%02d/%04d", i.day, i.month, i.year)
    local timeString = string.format("%02d:%02d", i.hour, i.min)
    local separator = t and "às" or "as"
    return dateString .. " " .. separator .. " " .. timeString .. "h"
end

function loadCommands()
    local money = money()
    local group = group()
    local home = home()
    local vehicle = vehicle()
    local ban = ban()
    local item = item()
    

    Commands = {
        ADD_BAN = function(args)
            return ban.add(tonumber(args.user_id))
        end,
    
        REMOVE_BAN = function(args)
            return ban.rem(tonumber(args.user_id))
        end,
    
        ADD_GROUP = function(args)
            return group.add(tonumber(args.user_id), args.value)
        end,
    
        REMOVE_GROUP = function(args)
            return group.rem(tonumber(args.user_id), args.value)
        end,
    
        ADD_MONEY = function(args)
            return money.add(tonumber(args.user_id), tonumber(args.value))
        end,
    
        REMOVE_MONEY = function(args)
            return money.rem(tonumber(args.user_id), tonumber(args.value))
        end,
    
        ADD_VEHICLE = function(args)
            return vehicle.add(tonumber(args.user_id), args.value)
        end,
    
        REMOVE_VEHICLE = function(args)
            return vehicle.rem(tonumber(args.user_id), args.value)
        end,
    
        ADD_HOME = function(args)
            return home.add(tonumber(args.user_id), args.value)
        end,
    
        REMOVE_HOME = function(args)
            return home.rem(tonumber(args.user_id), args.value)
        end,
    
        ADD_ITEM = function(args)
            return item.add(tonumber(args.user_id), args.value, tonumber(args.amount or 0))
        end,
    
        --[[ JS_CODE = function(args)
                local code = args.value:gsub("{user_id}", tostring(tonumber(args.user_id)))
            return load(code)()
        end,]]
    
        SQL_CODE = function(args)
            
            return db.query("gal_SQL_CODE", args.value:gsub("{user_id}", tostring(tonumber(args.user_id)))), "OK"
        end, 
    
        SYSTEM_NOTIFY = function(args)
            return userNotify(tonumber(args.user_id), tonumber(args.invoice_id))
        end,
    }

    RegisterCommand(config.commando_vip or 'vip',function(source,args,rawCommand) 
        if source == 0 then
            local e = tonumber(args[1])
            if not e then
              return sendErrorMessage("Informe o id do usuario para verificar os agendamentos.")
            end
            
            local i = scheduler.findAll(e)
            
            if not next(i) then
              return sendMessage("Nenhum agendamento encontrado.")
            end
            
            print("")
            
            sendMessage("Agendamentos do usuario #"..e)
            
            for _, v in ipairs(i) do
                if not (v.command == "SYSTEM_NOTIFY" or v.command == "ADD_ITEM") then
                    local t = formatDate(v.execute_at)
                sendMessage("^6["..v.id.."] =>^0 "..prettyCommandName(v.command).." "..v.value:upper().." em ^6"..t.."^0")
              end
            end
            
            print("")
        else
            local function getFilteredSchedules(e)
                local userId = getUserId(e)
                if not userId then
                  return
                end
                
                local schedules = scheduler.findAll(userId)
                local filteredSchedules = {}
                for _, schedule in ipairs(schedules) do
                  if schedule.command ~= "SYSTEM_NOTIFY" and schedule.command ~= "ADD_ITEM" then
                    local formattedDate = formatDate(schedule.execute_at, true)
                    local display = commandDisplay(schedule.command)
                    local newSchedule = {
                      id = schedule.id,
                      command = schedule.command,
                      value = schedule.value,
                      execute_at = formattedDate,
                      display = display
                    }
                    table.insert(filteredSchedules, newSchedule)
                  end
                end
                return filteredSchedules
              end
              
              
                local filteredSchedules = getFilteredSchedules(source)
                if filteredSchedules then
                    local data = {Action = 'SHOW_SCHEDULES', scheduler_data = filteredSchedules} -- Dados que serão enviados para a interface do usuário
                    TriggerClientEvent("gal_show_schedules", source, data)
                end
        end
    end)

    if(config.debug_mode) then
        sendDebugMessage("Todos comandos carregados")
    end
    --print("Comandos carregados")
end



function reconnectAPI()
    tentativa = tentativa + 1
    if tentativa >= 5 then
        sendErrorMessage('Cinco erros consecutivos Tentando novamente em 60 segundos...')
        Wait(60e3)
        tentativa = 0
    end
    sendErrorMessage("Tentando reconectar a API em 5 segundos")
    Citizen.Wait(5000)
    startScript()
end

function startWS()
    CreateThread(function()
        local ws, connected, seq = nil, false, 0
    
        function listener(event, payload)
            if(config.debug_mode) then
                sendDebugMessage(string.format('Recebeu evento %s com %s', event, json.encode(payload)))
            end
            if event == 'gal::connect' then
                if payload.connected == false then
                    --print(_('connection.error', payload))
                    sendErrorMessage(payload.message)
                    ws.close()
                else
                    --print(_('connection.ok'))
                    sendMessage(payload.message)
                    connected = true
                    seq = 0
                end
            elseif event == '$error' then
                seq = seq + 1
                if seq >= 5 then
                    --print(_('connection.outage'))
                    sendErrorMessage('Cinco erros consecutivos, rtc outage? Tentando novamente em 60 segundos...')
                    Wait(60e3)
                    seq = 0
                else
                    sendErrorMessage("Ocorreu um erro ao conectar a WS, tentando novamente em 5 segundos")
                    Wait(5e3)
                end
                ws.reconnect()
            elseif event == '$close' and connected then
                connected = false
                seq = seq + 1
                if seq >= 5 then
                    --print(_('connection.outage'))
                    sendErrorMessage('Cinco erros consecutivos, rtc outage? Tentando novamente em 60 segundos...')
                    Wait(60e3)
                    seq = 0
                else
                    sendErrorMessage("Conexão com WS foi fechada, tentando novamente em 5 segundos")
                    Wait(5e3)
                end
                ws.reconnect()
            elseif event =='$open' then
                ws.send(json.encode({ event = 'gal::fivem::buscar::commands' })) --Envia event pra verificar se tem algum comando pendente
            elseif event == 'gal::fivem::execute::commands' then
                addOrder(payload)
            end
        end
    
        while wait_before_intelisense do
            Wait(100)
        end
        sendMessage("Conectando a WS...")
        ws = exports[GetCurrentResourceName()]:createWebSocket(UrlWS, headers, listener)
    
        while true do
            Wait(60e3)
            if connected then
                ws.ping()
            end
        end
    end)
end

function addOrder(e) --Quando receber o pedido, ira acionar este funciton
    table.insert(armazemDeDados, e)
end

function work() --Quando tiver algum pedido no armazemDeDados ira acionar executarPedido
 Citizen.CreateThread(function()
    while true do
        if(#armazemDeDados > 0) then
            local primeiroData = armazemDeDados[1]
            executarPedido(primeiroData)
            table.remove(armazemDeDados, 1)
        else 
            Wait(1000)
        end
    end
 end)
end


function executarPedido(pedido) --Quando a function work mandar executar algum pedido, irei realizar tudo necessario
    local success, error = pcall(function()
    local t = Commands[pedido.comando](pedido)
        if(config.debug_mode) then
            sendDebugMessage("Comando #"..pedido.id_comando.." executado com sucesso para o id #"..pedido.user_id..":", t)
        end
        if(pedido.temporario) then
            local oppositeCommand = function(e)
                if e == "ADD_GROUP" then
                  return "REMOVE_GROUP"
                elseif e == "ADD_VEHICLE" then
                  return "REMOVE_VEHICLE"
                elseif e == "ADD_HOME" then
                  return "REMOVE_HOME"
                end
              end

              local opposite = oppositeCommand(pedido.comando)
              if opposite then
                local commands = scheduler.findByCommand(pedido.user_id, opposite)
                local i = nil
                for _, v in ipairs(commands) do
                  if v.value == pedido.value then
                    i = v
                    break
                  end
                end
                if i then
                    local seconds = i.execute_at / 1000 -- convert milliseconds to seconds
                    local t = os.date("%Y-%m-%d %H:%M:%S", seconds + (pedido.dias_duracao * 86400))
                    scheduler.update(i.id, { execute_at = t })
                else
                  scheduler.create(pedido.user_id, opposite, pedido.value, nil, pedido.dias_duracao)
                end
              else 
                print(string.format("Erro ao encontrar o comando oposto para %s.", pedido.comando))
              end
        end
    end)

    if not success then
        sendErrorMessage("Ocorreu um erro ao executar o comando "..pedido.comando.." #"..pedido.id_comando)
    end
end

------------------------------------

function vRP.addGroup(id, name) 
    local framework = config.framework
    if framework == "CREATIVE3" then
        db.query("gal_addGroupCreativeV3", "INSERT INTO vrp_permissions(user_id, permiss) VALUES("..id..", "..name..")")
        vRP.insertPermission(getUserSource(id), name)
    elseif framework == "CREATIVE4" or framework == "CREATIVE5" then
        vRP.setPermission(id, name)
    elseif framework == "CREATIVE_NETWORK" then
        vRP.SetPermission(id, name)
    else
        vRP.addUserGroup(id, name)
    end
end

function vRP.remGroup(id, name) 
    if config.framework == "CREATIVE3" then
        return db.query("gal_remGroupCreativeV3","DELETE FROM vrp_permissions WHERE user_id = "..id.." AND permiss = "..name..""), h.removePermission(getUserSource(id), name)
      elseif config.framework == "CREATIVE4" or config.framework == "CREATIVE5" then
        return vRP.remPermission(id, name)
      elseif config.framework == "CREATIVE_NETWORK" then
        return vRP.RemovePermission(id, name)
      else
        return vRP.removeUserGroup(id, name)
      end
end

function vRP.addMoneyBank(id, qty) 
    local framework = config.framework
    if framework == "CREATIVE3" or framework == "CREATIVE4" then
        return vRP.addBank(id, qty)
    elseif framework == "CREATIVE5" then
        return vRP.addBank(id, qty, "Private")
    elseif framework == "CREATIVE_NETWORK" then
        return vRP.GiveBank(id, qty)
    else
        return vRP.giveBankMoney(id, qty)
    end
end

function vRP.remMoneyBank(id, qty) 
    local framework = config.framework

    if framework == "CREATIVE3" or framework == "CREATIVE4" then
    vRP.delBank(id, qty)
    elseif framework == "CREATIVE5" then
    vRP.delBank(id, qty, "Private")
    elseif framework == "CREATIVE_NETWORK" then
    vRP.RemoveBank(id, qty, "Private")
    else
    vRP.setBankMoney(id, vRP.getBankMoney(id) - qty)
    end
end

function vRP.addCar(e, t) -- Feito e testado sem estar na city
    local i =  db.findFirstTable("vrp_vehicles", "summerz_vehicles", "vehicles", "vrp_user_vehicles", "vrp_user_veiculos", config.vehicle_table)
    if not i then error("Nenhuma tabela de veículo compatível.") end
    if config.debug_mode then sendDebugMessage("Selected vehicle table: " .. i) end
    local n = db.findFirstColumn(i, "user_id", "Passport")
    local s = db.findFirstColumn(i, "vehicle", "veiculo", "model")
    if not n then error("Nenhum campo de user_id compatível.") end
    if not s then error("Nenhum campo de veículo compatível.") end
    local c = db.findFirstColumn(i, "plate", "placa")
    local u = db.findFirstColumn(i, "tax", "ipva")
    local l = db.query("gal_addCar", string.format("SELECT * FROM "..i.." WHERE "..n.." = "..e.." AND "..s.." = '"..t.."'"))[1]
    if l then return "OK (Already owned)" end
    local p = { [n] = e, [s] = t }
    if c then p[c] = generatePlate('NNLLLNNN') end
    if u then
        local e = os.date("*t")
        e.day = e.day + 30
        p[u] = os.time(e)
    end
    if i == "vehicles" then
        p.doors = "{}"
        p.tyres = "{}"
        p.windows = "{}"
    end
    db.insert(i, p)
    return "OK"
end

function vRP.remCar(e, t) --Feito e testado sem estar na city
    local i = db.findFirstTable("vrp_vehicles", "summerz_vehicles", "vehicles", "vrp_user_vehicles", "vrp_user_veiculos", config.vehicle_table)
    if config.debug_mode then sendDebugMessage("Selected vehicle table: " .. i) end
    if not i then
        error("Nenhuma tabela de veículo compatível.")
    end
    local n = db.findFirstColumn(i, "user_id", "Passport")
    if config.debug_mode then sendDebugMessage("Selected user_id column: " ..n) end
    local s = db.findFirstColumn(i, "vehicle", "veiculo", "model")
    if config.debug_mode then sendDebugMessage("Selected veiculo column: " .. s) end
    if not n then
        error("Nenhum campo de user_id compatível.")
    end
    if not s then
        error("Nenhum campo de vehicle compatível.")
    end
    db.query("gal_remCar", string.format("DELETE FROM "..i.." WHERE "..n.." = "..e.." AND "..s.." = '"..t.."'"))
    return "OK"
end

function vRP.addHouse(id, home) 
    if db.hasTable("vrp_homes_permissions") then
        local i = db.query("gal_selectHouse","SELECT * FROM vrp_homes_permissions WHERE home = '"..home.."'")
        if #i >= 1 then
            if not i[1].user_id == id then
                error("A casa #"..home.." já possui um proprietário.")
            end
        return "OK (Already owned)"
        end
        local n = { user_id = id, home = home, owner = 1 }
        local s = db.findFirstColumn("vrp_homes_permissions", "tax", "taxa")
        if s then
            n[s] = os.time()
          end
          db.insert("vrp_homes_permissions", n)
          return "OK"
    end
    if db.hasTable("vrp_user_homes") then --Nao testado
        local n = db.query("gal_selectHouseV2","SELECT * FROM vrp_user_homes WHERE user_id = "..id.." AND home = '"..home.."'")[1]
        if n then
          return "OK (Already owned)"
        end
      
        local s = db.query("gal_selectNumberHouse", "SELECT number FROM vrp_user_homes WHERE home = '"..home.."' ORDER BY number DESC LIMIT 1")
        local r = (s[1] and s[1].number or 0) + 1
        db.insert("vrp_user_homes", { user_id = id, home = home, number = r })
        return "OK"
    end
    if db.hasTable("vrp_homes") then --Nao testado
        local i = db.query("SELECT * FROM vrp_homes WHERE owner = 1 AND home = '"..home.."'")
        if #i > 0 then
          if i[1].user_id ~= id then
            error("A casa #" .. t .. " já possui um proprietário.")
          end
          return "OK (Already owned)"
        end
      
        local n = db.findFirstColumn("vrp_homes", "home", "name")
        local s = db.findFirstColumn("vrp_homes", "tax", "ipva")
        if not n then
          error("Nenhuma coluna de nome da casa foi encontrada. Entre em contato com o suporte.")
        end
      
        local o = { [n] = t, user_id = e, owner = 1 }
        if s then
          o[s] = os.time()
        end
      
        db.insert("vrp_homes", o)
        return "OK"
    end
    local i, s, c, u, l, p, h, d --Nao testado
        local n = db.findFirstTable("propertys", "summerz_propertys")
        if n then
        i = db.findFirstColumn(n, "user_id", "Passport")
        s = db.findFirstColumn(n, "name", "Name")
        c = db.findFirstColumn(n, "tax", "Tax")
        u = db.findFirstColumn(n, "vault", "Vault")
        l = db.findFirstColumn(n, "fridge", "Fridge")
        if not i or not s then
            error(string.format("Não foi possível encontrar as colunas de user_id / name"))
        end
        local res = db.query("gal_selectHouseV3",string.format("SELECT * FROM "..n.." WHERE "..s.." = '"..home.."' AND "..i.." = "..id..""))
        p = res[1]
        if p then
            return "OK (Already owned)"
        end
        res = db.query("gal_selectHouse",string.format("SELECT * FROM "..n.." WHERE "..s.." = '"..home.."'"))
        h = res[1]
        if h then
            error(string.format("A casa #"..home.." já possui um proprietário."))
        end
        d = {[i]=id, [s]=home}
        if c then
            d[c] = os.time() + 2592e3
        end
        if u then
            d[u] = 100
        end
        if l then
            d[l] = 10
        end
        if db.hasColumn(n, "owner") then
            d.owner = 1
        end
        if db.hasColumn(n, "Serial") then
            d.Serial = generatePlate("LNLNLNLNLN")
            local res = db.pluck("SELECT Serial FROM propertys", "Serial")
            while table.concat(res):find(d.Serial) do
                d.Serial = o.stringFromPattern("LNLNLNLNLN")
              end
        end
        db.insert(n, d)
        return "OK"
        else
        error("Nenhuma tabela de propriedades compatível. Entre em contato com o suporte para adicionarmos juntos.")
    end
end

function vRP.remHouse(id, home) 
    local i = db.findFirstTable("vrp_homes_permissions", "vrp_user_homes", "summerz_propertys", "propertys", config.home)
    if not i then error("Nenhuma tabela de casas compatível. Entre em contato com o suporte para adicionarmos juntos.") end
    local s = db.findFirstColumn(i, "home", "name", "Name")
    if not s then error("Ocorreu um erro ao buscar pelas colunas das propriedades.") end
    db.query("gal_remHouse",string.format("DELETE FROM "..i.." WHERE "..s.." = '"..home.."'"))
    return "OK"
end

function vRP.addItemInventory(id, item, qty) --Feito, nao testado
    local framework = config.framework
    if framework == "CREATIVE5" then
    return coroutine.wrap(vRP.generateItem)(id, item, qty, false)
    elseif framework == "CREATIVE_NETWORK" then
    return coroutine.wrap(vRP.GenerateItem)(id, item, qty, false)
    else
    return coroutine.wrap(vRP.giveInventoryItem)(id, item, qty, false)
    end
end

function vRP.addBan(id) --Feito, nao testado
    local framework = config.framework
    if framework == "CREATIVE3" then
        db.query("gal_addBan","UPDATE vrp_infos SET banned = 1 WHERE steam=(SELECT steam FROM vrp_users WHERE id = "..id..")")
    elseif framework == "CREATIVE4" or framework == "CREATIVE5" or framework == "CREATIVE_NETWORK" then
        local i = db.findFirstTable("banneds", "summerz_banneds")
        local n = db.findFirstTable("characters", "summerz_characters")
    if not i then
        error("Nenhuma tabela de banimentos compatível.")
    end

    local s = db.findFirstColumn(i, "steam", "license")
    if not s then
        error("Nenhuma coluna de licença/steam compatível")
    end
    local a = db.query("gal_addBanCreative45enetwork","SELECT "..s.." FROM "..n.." WHERE id = "..id.."")[1]
    local r = {}
    r[s] = a.steam
    if db.hasColumn(i, "days") then
        r.days = 9999
    end
    if db.hasColumn(i, "time") then
       -- local e = os.date("%Y-%m-%d")
        local e = os.time() + 9999
        r.time = os.date("%Y-%m-%d", r.time)
    end
    db.insert(i, r)
    else
    if db.hasColumn("vrp_users", "banned") then
        db.query("gal_ban","UPDATE vrp_users SET banned = 1 WHERE id = "..id.."")
    end
    end
end

function vRP.remBan(id) --Feito, nao testado
    local framework = config.framework
    if framework == "CREATIVE3" then
        db.query("gal_addBan","UPDATE vrp_infos SET banned = 0 WHERE steam=(SELECT steam FROM vrp_users WHERE id = "..id..")")
    elseif framework == "CREATIVE4" or framework == "CREATIVE5" or framework == "CREATIVE_NETWORK" then
        local i = db.findFirstTable("banneds", "summerz_banneds")
        local n = db.findFirstTable("characters", "summerz_characters")
    if not i then
        error("Nenhuma tabela de banimentos compatível.")
    end

    local s = db.findFirstColumn(i, "steam", "license")
    if not s then
        error("Nenhuma coluna de licença/steam compatível")
    end
    local a = db.query("gal_addBanCreative45enetwork","SELECT "..s.." FROM "..n.." WHERE id = "..id.."")[1]
    local r = {}
    r[s] = a.steam
    if db.hasColumn(i, "days") then
        r.days = 9999
    end
    if db.hasColumn(i, "time") then
        local e = os.time() + 9999
        r.time = os.date("%Y-%m-%d", r.time)
    end
        db.query("gal_ban","DELETE FROM "..i.." WHERE steam = '"..a.steam.."'")
    else
    if db.hasColumn("vrp_users", "banned") then
        db.query("gal_ban","UPDATE vrp_users SET banned = 0 WHERE id = "..id.."")
    end
    end
end

-------------- [ DB ] --------------

function db.inic()

    SQL.drivers = {
    {'oxmysql', function(promise, sql, params)
        promise:resolve(exports.oxmysql:query_async(sql, params))
    end},
    {'ghmattimysql', function(promise, sql, params)
        exports.ghmattimysql:execute(sql, params, function(result)
            promise:resolve(result)
        end)
    end},
    {'GHMattiMySQL', function(promise, sql, params)
        exports.GHMattiMySQL:QueryResultAsync(sql, params, function(result)
            promise:resolve(result)
        end)
    end},
    {'mysql-async', function(promise, sql, params)
        exports['mysql-async']:mysql_fetch_all(sql, params, function(result)
            promise:resolve(result)
        end)
    end}
    }

    for i, driver in ipairs(SQL.drivers) do
        if GetResourceState(driver[1]) == 'started' then
            SQL.driver = driver[2]
            sendMessage('Usando driver: '..driver[1])
            break
        end
    end
end

function SQL.silent(sql, params)
    if SQL.driver then
        local p = promise.new()
        SQL.driver(p, sql, params or {})
        return Citizen.Await(p) or error('Unexpected sql result from '..script)
    end
    error('Missing compatible SQL driver')
end


function db.query(nome, query)
    if( not nome or not query) then return end
    local a = SQL.silent(query, {})
    return a
end

function db.insert(e, t)
    local keys = {}
    local values = {}
    for key, value in pairs(t) do
      table.insert(keys, key)
      table.insert(values, "'"..value.."'")
    end
    
    local keysString = table.concat(keys, ",")
    local valuesString = table.concat(values, ",")
    local query2 = string.format("INSERT INTO "..e.." ("..keysString..") VALUES ("..valuesString..")")
    return db.query("gal_insert", query2)
end

function db.update(e, t, i)
    local n = {}
    for key in pairs(t) do
        table.insert(n, key .. " = '"..t.execute_at.."'")
    end

    local s = {}
    for key in pairs(i) do
        table.insert(s, key .. " = "..i.id)
    end

    local a = "UPDATE " .. e .. " SET " .. table.concat(n, ", ")
    if #s > 0 then
        a = a .. " WHERE " .. table.concat(s, " AND ")
    end

    local values = {}
    for _, value in pairs(t) do
        table.insert(values, value)
    end
    for _, value in pairs(i) do
        table.insert(values, value)
    end

    return db.query("gal_DBUPDATE", a)
end

function db.pluck(e, t)
    local result = db.query("gal_hascolumns", e)
    local mapped_result = {}
    for _, row in ipairs(result) do
      table.insert(mapped_result, row[t])
    end
    return mapped_result
end

function db.mapTables() 
   return table.insert(tablesNames, db.query('gal_showtables', 'SHOW TABLES'))
end

function db.hasTable(nomeTabela)
    for index, data in ipairs(tablesNames[1]) do
        for key, value in pairs(data) do
            if value == nomeTabela then
                return true
            end
        end
    end
    return false
end

function db.hasColumn(e, t) 
    local e = string.lower(e)
    if not columnNames[e] then
      columnNames[e] = db.pluck("SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = '"..config.database.databaseName.."' AND TABLE_NAME = '"..e.."'", "COLUMN_NAME")
    end
    for i, v in ipairs(columnNames[e]) do
        if v == t then
          return true
        end
      end
      return false
end

function db.findFirstTable(...)
    for i, v in ipairs({...}) do
        if db.hasTable(v) then
          return v
        end
      end
      return nil
end

function db.findFirstColumn(e, ...)
    for _, i in ipairs({...}) do
        if db.hasColumn(e, i) then
          return i
        end
      end
end

function db.getDataTable(e)
    local t = db.findFirstTable("summerz_playerdata", "vrp_user_data", "playerdata")
    if not t then
        error("Nenhuma tabela de datatable compatível foi encontrada.")
    end

    local i = db.findFirstColumn(t, "user_id", "Passport")
    local n = db.query("gal_getDatabase","SELECT dvalue FROM "..t.." WHERE "..i.."="..e.." AND dkey IN ('vRP:datatable', 'Datatable')")
    
    if not n[1] then
        error(string.format("A datatable do jogador #%d não foi encontrada.", e))
    end

    local parsed_data = json.decode(n[1].dvalue)
    if parsed_data == nil then
        error(string.format("Ocorreu um erro ao obter a datatable do jogador #%d. Verifique a formatação dos dados.", e))
    end
    return parsed_data
end

function db.setDataTable(e, t) -- e = ID, t = puxa getDataTable
    local i = db.findFirstTable("summerz_playerdata", "vrp_user_data", "playerdata")
    if not i then
    error("Nenhuma tabela de datatable compatível foi encontrada.")
    end
    local n = db.findFirstColumn(i, "user_id", "Passport")

    return db.query("gal_setDataTable", "UPDATE " .. i .. " SET dvalue = '" .. tostring(json.encode(t)) .. "' WHERE " .. n .. "=" .. e .. " AND dkey IN ('vRP:datatable', 'Datatable')")
end

function db.updateDataTable(e, t)
    local i = db.getDataTable(e)
    if not i then
      error(string.format("Ocorreu um erro ao atualizar o dvalue do jogador #%d.", e))
    end
  
    t(i)
    db.setDataTable(e, i)
end

-------------- [ VRP ] --------------

function getUserSource(e)
    local framework = config.framework
    if framework == "CREATIVE4" or framework == "CREATIVE5" then
      return vRP.userSource(e)
    elseif framework == "CREATIVE_NETWORK" then
      return vRP.Source(e)
    else
      return vRP.getUserSource(e)
    end
end

function getUserIdentity(e)
    local framework = config.framework

    if framework == "CREATIVE4" or framework == "CREATIVE5" then
        return vRP.userIdentity(e)
    elseif framework == "CREATIVE_NETWORK" then
        return vRP.Identity(e)
    else
        return vRP.getUserIdentity(e)
    end
end

function getUserId(e)
    if config.framework == "CREATIVE_NETWORK" then
      return vRP.Passport(e)
    else
      return vRP.getUserId(e)
    end
  end

function isOnline(e)
    local t = getUserSource(e)
    if not t then return false end
    if math.floor(t) == t then
        return true
    end
end

function userNotify(id, invoice_id) --TERMINAR
    local user = getUserSource(tonumber(id))
    if user then
        --Caso esteja online executa isto
        PerformHttpRequest("https://api.galgaming.com.br/v1/ps/transacoes/"..invoice_id, function (errorCode, data, resultHeaders)
            if errorCode == 404 then
                error("Nao foi possivel encontrar a transação "..invoice_id)
                return
            end
            data = json.decode(data)--String pra JSON
            local produtosComprados = ""
            local produtosCompradosSemNegrito = ""
            if data.status ~= 1 then return end
            for produto= 1, #data.produtos do
                produtosComprados = produtosComprados.."<strong>"..data.produtos[produto].quantidade.."x " ..data.produtos[produto].nome.."</strong> "
                produtosCompradosSemNegrito = produtosCompradosSemNegrito.." "..data.produtos[produto].quantidade.."x " ..data.produtos[produto].nome.." "
            end
            local nomeJogador = getUserIdentity(id)
            local o = nomeJogador and (nomeJogador.nome or nomeJogador.firstname or nomeJogador.name) or "Indivíduo" --Primeiro nome
            local c = nomeJogador and (nomeJogador.sobrenome or nomeJogador.surname or nomeJogador.name2 or nomeJogador.name) or "Indigente" --sobrenome
            
            sendDeliveredMessage("Nova entrega de "..produtosCompradosSemNegrito.." para "..o.." #"..id..".")
            
            if config.aviso.notify.show == true then
                if not config.aviso.notify.message then
                    config.aviso.notify.message = ':nome :sobrenome comprou :produtos'
                end
                local placeholder = config.aviso.notify.message:gsub(":nome", o) 
                placeholder = placeholder:gsub(":sobrenome", c)
                placeholder = placeholder:gsub(":produtos", produtosComprados)
                TriggerClientEvent("Gal",-1,"compras", placeholder, config.aviso.notify.title)
            end
        end, "GET", "", headers) 
    else
        --Caso esteja offline executa isto
        scheduler.create(id, "SYSTEM_NOTIFY", invoice_id)
        return "SCHEDULED";
    end
end

function setFramework()
    local framework = "VRP"
    if db.hasTable("warehouse") or (db.hasTable("summerz_bank") and db.hasColumn("summerz_bank", "dvalue")) then
        framework = "CREATIVE_NETWORK"
    elseif db.hasTable("summerz_bank") and db.hasTable("summerz_fidentity") then
        framework = "CREATIVE5"
    elseif db.hasTable("summerz_accounts") then
        framework = "CREATIVE4"
    elseif db.hasTable("vrp_infos") and db.hasTable("vrp_permissions") then
        framework = "CREATIVE3"
    end
        config.framework = framework
        sendMessage(string.format("Injetando framework ^6%s^0", config.framework))

    return "OK"
end

-------------- [ RANDOM ] --------------

function generatePlate(pattern)
    local letters = {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M"}
    local numbers = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9}
  
    local function stringFromPattern(pattern)
      return pattern:gsub("L", function()
        return letters[math.random(#letters)]
      end):gsub("N", function()
        return numbers[math.random(#numbers)]
      end)
    end
  
    return stringFromPattern(pattern)

end

function verificarAgendamento(e)
    local t, err = scheduler.findAllWaiting(e)
    if err then
    error(string.format("Erro ao buscar os agendamentos de #%s.", e), 2)
    end
    if #t > 0 then
        for _, i in ipairs(t) do
          local t, n, s, a = i.id, i.command, i.value, i.amount
          local i = {user_id = e, command = n, amount = a}
          if n == "SYSTEM_NOTIFY" then
            i.invoice_id = s
          else
            i.value = s
          end
          Commands[n](i)
          scheduler.destroy(t)
        end
      end
end

-------------- [ COMANDOS ] --------------

function money()
    local tables = {
        { table = "vrp_users", user = "id", bank = "bank" },
        { table = "summerz_characters", user = "id", bank = "bank" },
        { table = "summerz_bank", user = "user_id", bank = "value" },
        { table = "summerz_bank", user = "Passport", bank = "dvalue" },
        { table = "characters", user = "id", bank = "bank" },
        { table = "vrp_user_identities", user = "user_id", bank = "banco" },
        { table = "vrp_user_infos", user = "user_id", bank = "bank" },
        { table = "vrp_characters", user = "user_id", bank = "bank" },
        { table = "bank", user = "Passport", bank = "dvalue" },
        { table = "vrp_user_moneys", user = "user_id", bank = "bank" },
    }
    local myObject = {
        add = function(id, qty)
            if isOnline(id) then
                vRP.addMoneyBank(id, qty)
                return "OK (Online)"
            else
                local i = 0
                    for _, n in pairs(tables) do
                    if (db.hasColumn(n.table, n.bank) and db.hasColumn(n.table, n.user)) then
                        db.query("gal_moneyUpdate", string.format("UPDATE "..n.table.." SET "..n.bank.."="..n.bank.." + "..qty.." WHERE "..n.user.." = "..id))
                        i = i + 1
                    end
                    end
                    if (i > 0) then
                    return "OK (Offline)"
                    else
                    error("Nenhum esquema de money compatível. Entre em contato com o suporte para adicionarmos juntos.")
                    end
            end
        end,
        rem = function(id, qty)
            if isOnline(id) then
                vRP.remMoneyBank(id, qty)
                return "OK (Online)"
            else
                local i = 0
                    for _, n in pairs(tables) do
                    if (db.hasColumn(n.table, n.bank) and db.hasColumn(n.table, n.user)) then
                        db.query("gal_moneyUpdate", string.format("UPDATE "..n.table.." SET "..n.bank.."="..n.bank.." - "..qty.." WHERE "..n.user.." = "..id))
                        i = i + 1
                    end
                    end
                    if (i > 0) then
                    return "OK (Offline)"
                    else
                    error("Nenhum esquema de money compatível. Entre em contato com o suporte para adicionarmos juntos.")
                    end
            end
        end
      }
      return myObject
end

function group()
    local myObject = {
        add = function(id, nome)
            local status = ""
            if isOnline(id) then
              status = vRP.addGroup(id, nome)
              status = "OK (Online)"
            elseif db.hasTable("vrp_permissions") then
              status = db.insert("vrp_permissions", { user_id = id, permiss = nome })
              status = "OK (Offline)"
            elseif config.framework == "CREATIVE4" then
              status = vRP.setPermission(id, nome)
              status = "OK (Offline)"
            elseif config.framework == "CREATIVE_NETWORK" then
              status = vRP.SetPermission(id, nome)
              status = "OK (Offline)"
            else
              status = db.updateDataTable(id, function(id)
                local i = "perm"
                if not db.hasTable("summerz_playerdata") then i = "groups" end
                if type(id[i]) == "table" then
                  id[i][nome] = true
                end
              end)
              status = "OK (Offline)"
            end
            
            return status
        end,
        rem = function(id, nome)
            if isOnline(id) then
                vRP.remGroup(id, nome)
                return "OK (Online)"
              elseif db.hasTable("vrp_permissions") then
                db.query("gal_removePermission","DELETE FROM vrp_permissions WHERE user_id = "..id.." AND permiss = '"..nome.."'")
                return "OK (Offline)"
              elseif config.framework == "CREATIVE4" then
                vRP.remPermission(id, nome)
                return "OK (Offline)"
              elseif config.framework == "CREATIVE_NETWORK" then
                vRP.RemovePermission(id, nome)
                return "OK (Offline)"
              else
                db.updateDataTable(id, function(table)
                    local i = "perm"
                    if not db.hasTable("summerz_playerdata") then i = "groups" end
                  if table[i] and table[i][nome] then
                    table[i][nome] = nil
                  end
                end)
                return "OK (Offline)"
              end
        end
      }
      return myObject
end

function home()
    local myObject = {
        add = function(id, home)
           return vRP.addHouse(id, home)
        end,
        rem = function(id, home)
            return vRP.remHouse(id, home)
        end
      }
      return myObject
end

function item()
    local myObject = {
        add = function(id, nomeDoItem, quantidade)
            local n = getUserSource(id)
                if config.debug_mode then
                    local t = getUserIdentity(id)
                    sendDebugMessage("Source:", n)
                    sendDebugMessage("Identity:", t)
                end
                if n then
                    vRP.addItemInventory(id, nomeDoItem, quantidade)
                    return "OK"
                else
                    scheduler.create(id, "ADD_ITEM", nomeDoItem, quantidade)
                    return "SCHEDULED"
            end
        end,
      }
      return myObject
end

function vehicle()
    local myObject = {
        add = function(id, nomeDoCarro)
           vRP.addCar(id, nomeDoCarro)
        end,
        rem = function(id, nomeDoCarro)
            vRP.remCar(id, nomeDoCarro)
        end
      }
      return myObject
end

function ban()
    local myObject = {
        add = function(id)
            local t = getUserSource(id)
            vRP.addBan(id)
            if t then
                vRP.kick(t, "Você foi expulso da cidade.")
            end
            return "OK"
        end,
        rem = function(id)
            vRP.remBan(id)
            return "Ok"
        end
      }
      return myObject
end

-------------- [ SCHEDULER ] --------------

function toSQLDate(tempo)
    local agora = os.time()

    local dataFutura = agora + tempo * 24 * 60 * 60

    local dataSQL = os.date("%Y-%m-%d %H:%M:%S", dataFutura)

    return dataSQL
end

function scheduler.create(e, t, i, s, o)
    local execute_at
    if o then
        execute_at = toSQLDate(o)
    else
        execute_at = os.date("%Y-%m-%d %H:%M:%S", os.time())
    end

    local n = {
        user_id = e,
        command = t,
        value = i,
        execute_at = execute_at
    }
    if s then n.amount = s end
    return db.insert(nameOfTableScheduler, n)
end

function scheduler.update(e, t) 
    return db.update(nameOfTableScheduler, t, {id = e})
end

function scheduler.findAll(user_id)
    return db.query("gal_findAll","SELECT * FROM "..nameOfTableScheduler.." WHERE user_id = "..user_id)
end

function scheduler.findAllWaiting(user_id)
    return db.query("gal_findAllWaiting","SELECT * FROM "..nameOfTableScheduler.." WHERE user_id = "..user_id.." AND execute_at < '"..toSQLDate(0).."'")
end

function scheduler.findByCommand(user_id, command)
    return db.query("gal_findByCommand","SELECT * FROM "..nameOfTableScheduler.." WHERE user_id = "..user_id.." AND command = '"..command.."'")
end

function scheduler.destroy(id)
    db.query("gal_destroy","DELETE FROM "..nameOfTableScheduler.." WHERE id = "..id)
    return "OK"
end

-----

Citizen.CreateThread(function()
local e = "^6\n     _   _  __     __  ______  __   __   _____              __  __   _____   _   _    _____ \n    | \\ | | \\ \\   / / |  ____| \\ \\ / /  / ____|     /\\     |  \\/  | |_   _| | \\ | |  / ____|\n    |  \\| |  \\ \\_/ /  | |__     \\ V /  | |  __     /  \\    | \\  / |   | |   |  \\| | | |  __ \n    | . ` |   \\   /   |  __|     > <   | | |_ |   / /\\ \\   | |\\/| |   | |   | . ` | | | |_ |\n    | |\\  |    | |    | |____   / . \\  | |__| |  / ____ \\  | |  | |  _| |_  | |\\  | | |__| |\n    |_| \\_|    |_|    |______| /_/ \\_\\  \\_____| /_/    \\_\\ |_|  |_| |_____| |_| \\_|  \\_____|\n\n                                                                                           \n                                                                                            \n   \n                      www.galgaming.com.br - v1.0.0 BETA\n                      Monetize o seu servidor de FiveM!\n ^0"
print(tostring(e))

startScript()

    AddEventHandler("vRP:playerSpawn", function(e) 
        --Verificar agendamento, pra ver se tem alguma coisa pra ser executada no ID "e"
        verificarAgendamento(e)
    end)
    AddEventHandler("playerConnect", function(e) 
        --Verificar agendamento, pra ver se tem alguma coisa pra ser executada no ID "e"
        verificarAgendamento(e)
    end)
    AddEventHandler("CharacterSpawn", function(e, t) 
        --Verificar agendamento, pra ver se tem alguma coisa pra ser executada no ID "t"
        verificarAgendamento(e)
    end)
    AddEventHandler("Connect", function(e) 
        --Verificar agendamento, pra ver se tem alguma coisa pra ser executada no ID "e"
        verificarAgendamento(e)
    end)
end)