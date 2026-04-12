require "http/client"
require "log"

# 剩余时间字段匹配的正则
REMAINING_TIME_RE = /"remainingTime"\s*:\s*(\d+)/
# 查看签到是否成功
SUCCESS_RE = /"success"\s*:\s*(true|false)/

class Student
  # 确定类型
  @name : String
  @token : String
  @post_url : String

  # 使得外部可以访问name
  getter name

  def initialize(account : {name: String, token: String}) # 期望传入单个学生的NamedTuple
    # 初始化单个学生的名字，token,
    @name = account[:name]
    @token = account[:token]
    cookie = "SESSION=#{@token}"

    # 默认post包的url为空, 由后面拿到签到信息后再由post方法填充
    @post_url = ""
    @sign_in_headers = HTTP::Headers {
      "accept"         => "application/json, text/plain, */*",
      "x-access-token" => @token,
      "content-length" => "0",
      "cookie"         => cookie,
      "user-agent"     => "okhttp/4.12.0",
      "host"           => "www.eduplus.net",
      "connection"     => "Keep-Alive",
    }
  end

  # 签到post
  def post(courseSignInId : String, codeStringUrl : (String | Nil)) # 签到码的url有可能为nil, 所以为(String | Nil)
    # 在开始签到后，马上拼接url
    @post_url = "https://www.eduplus.net/api/course/clock_in/study?signInId=#{courseSignInId}#{codeStringUrl}"
    # 发出签到请求，并拿回响应
    response = HTTP::Client.post(@post_url, headers: @sign_in_headers)

    # 探测签到状态
    if match = SUCCESS_RE.match(response.body)
      if match[1] == "true"
        # 签到成功
        Log.info{"用户 #{@name} 签到成功！！！"}
      else
        Log.info{"#{@name} 签到失败！！请手动签到，未获取到签到码"} if codeStringUrl.nil?
        Log.info{"#{@name} 签到失败！！请手动签到，签到码#{codeStringUrl.split('=')[1]}"} if !codeStringUrl.nil?
      end
    else
      Log.warn{"无法探测到 #{@name} 签到状态"}
    end
  end

  # 获取剩余秒数，
  def get_remaining_seconds(courseSignInId : String, codeStringUrl : String) : Int32 # 普通签到不需要获取秒数，需要获取秒数就肯定是密码签到，所以密码不能nil, 然后返回一个int32的秒数
    response = HTTP::Client.get("https://www.eduplus.net/api/course/clock_in/#{courseSignInId}/student", @sign_in_headers)

    # 匹配剩余时间字段
    if match = REMAINING_TIME_RE.match(response.body)
      # 返回剩余秒数
      return match[1].to_i
    else
      Log.warn{"密码签到: #{codeStringUrl.split('=')[1]} 无法获取剩余时间,请手动签到"}
      # 无法获取，就返回剩余时间为0
      return 0
    end
  end
end


