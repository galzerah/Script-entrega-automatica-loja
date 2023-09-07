-----------------------------------------------------------------------------------------------------------------------------------------
-- NOTIFY
-----------------------------------------------------------------------------------------------------------------------------------------
RegisterNetEvent("Gal")
AddEventHandler("Gal",function(css, Message, title)
        SendNUIMessage({ Action = "Gal", Css = css, Message = Message or '', Title = title, Timer = 5000 })
end)

RegisterNetEvent("gal_show_schedules")
AddEventHandler("gal_show_schedules", function(data)
  SendNUIMessage(data) -- Envia a mensagem recebida do servidor para a interface do usuário
  SetNuiFocus(false) -- Define o foco na interface do usuário para receber entrada do usuário
end)