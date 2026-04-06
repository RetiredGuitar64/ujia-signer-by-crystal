require "http/client"
require "log"

require "./accounts.cr"
require "./sign_in.cr"

# check循环的间隔
SLEEP_GAP_IN_LOOP = 2
# 签到id字段正则
COURSE_SIGN_IN_ID_RE = /"courseSignInId"\s*:\s*"([0-9a-f]{32})"/
# 签到码字段正则
CODE_DISTANCE_RE = /"codeDistance"\s*:\s*"(\d{3,4})"/

class Checker
  getter name, token

  def initialize(@name : String = ACCOUNTS[0][:name], @token : String = ACCOUNTS[0][:token])
  end

  # 主检查入口
  def run
    cookie = "SESSION=#{@token}"

    id_check_url = "https://www.eduplus.net/api/course/courses/v1/study?types=Theory,Train"
    check_headers = HTTP::Headers{
      "accept"         => "application/json, text/plain, */*",
      "x-access-token" => @token,
      "cookie"         => cookie,
      "user-agent"     => "okhttp/4.12.0",
      "host"           => "www.eduplus.net",
      "connection"     => "Keep-Alive",
    }

    # 创建signer签到器
    signer = Signer.new

    # 主循环
    Log.info{"轮询已开始..."}
    loop do
      # 拿到响应
      response = HTTP::Client.get(id_check_url, check_headers)

      if response.status_code == 200
        if courseSignInId : (String | Nil) = detect_courseSignInId(response) # 尝试抓取签到id
          Log.info{"探测到签到: #{courseSignInId}"}
          # 开始获取签到码
          code_check_url = "https://www.eduplus.net/api/course/clock_in/#{courseSignInId}/student" # codecheck的url
          # 响应
          response_of_code_check = HTTP::Client.get(code_check_url, check_headers)

          # 扫描签到码, 4位就是正常码，3位就是200, 即普通签到，
          codeDistance : String = detect_codeDistance(response_of_code_check)
          Log.info{"签到码: #{codeDistance}"}

          # 进入签到流程, 传入签到id和签到码,4位数字为密码签到，或200,为普通签到
          signer.run(courseSignInId, codeDistance)

        end
      else
        # 状态码不为200, 说明有问题
        Log.error{"状态码: #{response.status_code}, \"#{@name}\" 的token \"#{@token}\" 可能已失效"}
      end

      # 间隔几秒
      sleep SLEEP_GAP_IN_LOOP.seconds
    end
  end

  # 探测是否有签到，这个方法会很频繁运行, 需要性能
  def detect_courseSignInId(response : HTTP::Client::Response) : String?  # 提前指定类型
    if match = COURSE_SIGN_IN_ID_RE.match(response.body)
      # 匹配到并返回签到id
      return match[1]
    end
    nil # 未匹配到签到id字段，就返回nil
  end

  # 检测签到码的方法
  def detect_codeDistance(response : HTTP::Client::Response) : String
    if match = CODE_DISTANCE_RE.match(response.body)  # 匹配签到码字段
      return match[1]
    else
      Log.warn{"未匹配到签到码字段，未知错误，将默认以普通签到进行"}
      return "200"
    end
  end
end
