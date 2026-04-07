require "http/server"
require "log"

BIND_ADDRESS = "0.0.0.0"
BIND_PORT = 18888

class Web
  def initialize(@status : Status)
  end

  def start
    web = HTTP::Server.new do |context|
      context.response.content_type = "text/html; charset=utf-8"
      context.response.print <<-HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta http-equiv="refresh" content="2">
        <title>U+签到状态</title>
      </head>
      <body>
        <pre style="font-size: 32px;">#{@status.web_show}</pre>
      </body>
      </html>
      HTML
    end

    address = web.bind_tcp(BIND_ADDRESS, BIND_PORT)

    spawn do
      web.listen
    end
    Log.info{"Web 已启动 #{BIND_ADDRESS}:#{BIND_PORT}"}

  end
end
