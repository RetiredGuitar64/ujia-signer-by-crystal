require "http/server"
require "log"

# 启动IP,默认本机
BIND_ADDRESS = "0.0.0.0"
# 启动端口
BIND_PORT = 18888

class Web
  # web 会从@status里的@message去读取信息并显示
  def initialize(@status : Status)
  end

  # 启动方法
  def start
    # 开一个server
    web = HTTP::Server.new do |context|
      # 默认回应html
      context.response.content_type = "text/html; charset=utf-8"
      # 渲染html
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

    # 绑定的地址
    address = web.bind_tcp(BIND_ADDRESS, BIND_PORT)

    # 开一个新的fiber来启动web, 防止主循环和web互相block住
    spawn do
      web.listen
    end
    Log.info{"Web 已启动 #{BIND_ADDRESS}:#{BIND_PORT}"}

  end
end
