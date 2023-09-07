fx_version 'bodacious'
game 'gta5'
lua54 "yes"
author "galzito"

shared_scripts {
    'shared/*'
}

server_scripts {
	'@vrp/lib/utils.lua',
	'server/ws/**',
	'server/main.lua',
}

client_scripts {
	'client/main.lua'
}

ui_page "web-side/index.html"

files {	
	"web-side/*",
	"web-side/**/*"
}