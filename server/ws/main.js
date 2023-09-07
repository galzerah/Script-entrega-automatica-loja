exports('createWebSocket', (url, headers, listener) => {
  let handle

  const instance = {
    get_state() {
      return handle.readyState
    },
    ping() {
      handle.ping()
    },
    close() {
      handle.close()
    },
    send(data) {
      handle.send(data)
    },
    reconnect() {
      if (handle) {
        handle.close()
      }
      handle = new WebSocket(url, { headers })
      handle.onmessage = ({ data: data2 }) => {
        try {
          const { event, data } = JSON.parse(data2.toString('utf8'))
          listener(event, data)
        } catch (error) {
          console.log("[Gal] [ERROR] Ocorreu um erro: " + error)
        }
      }

      handle.onclose = () => listener('$close', {})
      handle.onopen = () => listener('$open', {})
      handle.onerror = (err) => listener('$error', err.message)
      

    }
  }

  instance.reconnect()


  return instance
})