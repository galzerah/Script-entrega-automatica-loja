const preset = {
    "compras": {
        "color": "#D90045",
        "image": "buyer.svg",
        "background": "linear-gradient(90deg, rgba(217, 0, 69, 0.1) 0%, rgba(217, 0, 69, 0) 97.94%)",
        "lightBackground": "radial-gradient(50% 50% at 50% 50%, rgba(255, 184, 29, 0.4) 0%, rgba(217, 0, 69, 0.4) 0.01%, rgba(217, 0, 69, 0.0375) 85.42%, rgba(217, 0, 69, 0) 100%)"
    },
};

$(() => {
    window.addEventListener('message', async (event) => {
        const item = event.data || event.detail;
        //const item = { Action: "Nyex", Css: "compras", Message: 'EPAA! Ian Gallagher comprou 1x Teza 2x Agua 1x Vip OURO' || '', Title: 'LOJINHA', Timer: 100000 }
        switch (item.Action) {
            case 'Nyex':
                var Html = `
                    <div class="announce" >
                        <div class="notify_style" style="background:${preset[item.Css].background}">
                        <div class="notify_bar">
                                <div class="notify_fill"
                                    style="animation-duration:${(item?.Timer || 3000) / 1000 + 's'};background:${preset[item.Css].color}">
                                </div>
                            </div>
                            <div class="notify_light" style="background:${preset[item.Css].lightBackground}">
                            </div>
                            <div class="notify_content"
                                style="flex-direction:${(!item.Title ? 'row' : 'column')};gap: ${!item?.Title && '0.5vw'}">
                                <div class="notify_title">
                                    ${item.Title ? `<h1 style="color:${preset[item.Css].color}">
                                        ${item.Title}
                                    </h1>` : ''}
                                    <img src='./assets/images/${preset[item.Css].image}')" />
                                </div>
                                <p class="notify_text">${item?.Message}</p>
                            </div>
                            
                        </div>
                    </div > `;
                $("#announces").animate({ scrollTop: $("#announces").prop("scrollHeight") }, 100, "swing");
                $(Html).appendTo("#announces").animate({ right: "0", opacity: 1 }, { duration: 500 }).delay(item.Timer).animate({ right: "-10vw", opacity: 0 }, {
                    duration: 500, complete: function () {
                        this.remove()

                    }
                });
                break;
            case 'SHOW_SCHEDULES':
                let itens = ""
            for (let i = 0; i < item.scheduler_data.length; i++) {
                const element = item.scheduler_data[i];
                
                itens += `
                <div class="nyexitem">
                        <div>
                            <p style="padding:0; margin:0">
                            ${element.display}
                            </p>
                            <p style="padding:0; margin:0; font-weight: 900;">
                            ${element.value}
                            </p>
                        </div>
                        
                        <div>
                            <p style="padding:0; margin:0">
                            EXPIRA EM
                            </p>
                            <p style="padding:0; margin:0; font-weight: 900;">
                            ${element.execute_at}
                            </p>
                        </div>
                    </div>`
            }

                var Html = `
                <div class="nyexcontainer">
                    
                    ${itens}
                </div>
                    `
            
                    
                    $("#nyexcontainer").animate({ scrollTop: $("#nyexcontainer").prop("scrollHeight") }, 100, "swing");
                    $(Html).appendTo("#nyexcontainer").animate({ right: "0", opacity: 1 }, { duration: 500 }).delay(10000).animate({ right: "-10vw", opacity: 0 }, {
                        duration: 500, complete: function () {
                        this.remove()

                    }
                });
            break;
        }
       
    })
})
