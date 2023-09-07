local cfg = {}
--Frameworks disponiveis: VRPEX, CREATIVEV3, CREATIVEV4, CREATIVEV5, CREATIVE_NETWORK

cfg.token_servidor = "" --Token do seu servidor, pode pegar em https://nyexgaming.com.br/app/store > Servidores
cfg.token_loja = "" --Token da sua loja, pode pegar em https://nyexgaming.com.br/app/settings
cfg.webhook = "" --Webhook das logs de entrega da loja
cfg.commando_vip = "vip" --Comando que ira aparecer quando ira expirar tal produto

cfg.vehicle_table = "vrp_user_vehicles" --Nome da tabela da database que armazena os carros que tem na garagem dos players
cfg.homes = "vrp_homes_permissions" --Nome da tabela da database que armazena as permissões da casa dos players


cfg.aviso = {
    notify = {
        show = true, --Caso queira que apareca a notify para todos do servidor deixe true == ativo, caso deixe false == desativado
        title = "LOJINHA",
        message = ":nome :sobrenome comprou :produtos",

    },
} --Configuracoes de notify

cfg.debug_mode = false
return cfg