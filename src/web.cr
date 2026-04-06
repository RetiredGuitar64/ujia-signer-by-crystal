require "http/server"
require "log"

BIND_ADDRESS = "0.0.0.0"
BIND_PORT = 28888

class Web
  def initialize(@channel : Channel(String))
  end

  def start
    web = HTTP::Server.new do |context|
      context.response.content_type = "text/plain"
      p "000"
      context.response.print(
        if message = @channel.receive
          message
        else
          "没有签到"
        end
      )
      p "111"
    end
    address = web.bind_tcp(BIND_ADDRESS, BIND_PORT)
    p "222"
    web.listen
    p "333"
  end
end
