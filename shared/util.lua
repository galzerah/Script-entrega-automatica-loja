function sendMessage(e)
    print(string.format("^6[Gal] =>^0 %s", e))
end

function sendErrorMessage(e)
    print(string.format("^1[Gal] [ERROR] =>^0 %s", e))
end
  
function sendDeliveredMessage(e)
    print(string.format("^6[Gal] [ENTREGA] =>^0 %s", e))
end

function sendDebugMessage(e)
    print(string.format("^3[Gal] [DEBUG] =>^0 %s", e))
end