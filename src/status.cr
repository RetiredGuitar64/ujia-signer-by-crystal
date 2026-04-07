require "mutex"

class Status

  # 发给web的消息
  @message : String

  def initialize
    @status = Mutex.new
    @message = "Error: \nInit message\n签到状态发送出错\n尽快修复！！！" # 初始化的消息
  end

  # web显示靠这个方法
  def web_show
    @status.synchronize do
      @message
    end
  end

  # 直接显示
  def display(message : String)
    @status.synchronize do
      @message = message
    end
  end

  def display_normal_status
    @status.synchronize do
      @message = "状态正常\n无签到"
    end
  end

  def display_404_status
    @status.synchronize do
      @message = "Error:\n状态码非200! \n有可能token以失效!\n请尽快更换token!!!"
    end
  end

  def display_signin_code(code : String)
    @status.synchronize do
      @message = "密码签到:\n #{code}"
    end
  end
end
