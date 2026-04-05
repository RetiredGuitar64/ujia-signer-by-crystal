require "./accounts.cr"
require "http/client"
require "json"
require "log"

SLEEP_GAP_IN_LOOP = 2
# 签到id正则
COURSE_SIGN_IN_ID_RE = /"courseSignInId"\s*:\s*"([0-9a-f]{32})"/

class Checker
  getter name, token

  def initialize(@name : String = ACCOUNTS[0][0], @token : String = ACCOUNTS[0][1])
  end

  def run
    url = "https://www.eduplus.net/api/course/courses/v1/study?types=Theory,Train"
    cookie = "SESSION=#{@token}"

    headers = HTTP::Headers{
      "accept"         => "application/json, text/plain, */*",
      "x-access-token" => @token,
      "cookie"         => cookie,
      "user-agent"     => "okhttp/4.12.0",
      "host"           => "www.eduplus.net",
      "connection"     => "Keep-Alive",
    }

    Log.info{"轮询已开始..."}
    loop do
      response = HTTP::Client.get(url, headers)

      if response.status_code == 200
        if courseSignInId = detect_courseSignInId(response)
          Log.info{"探测到签到: #{courseSignInId}"}
        end
      else
        Log.error{"状态码: #{response.status_code}, \"#{@name}\" 的token \"#{@token}\" 可能已失效"}
      end

      sleep SLEEP_GAP_IN_LOOP
    end
  end

  # 探测是否有签到，这个方法会很频繁运行, 需要性能
  def detect_courseSignInId(response : HTTP::Client::Response) : String?  # 提前指定类型
    if match = COURSE_SIGN_IN_ID_RE.match(response.body)
      # 匹配到并返回签到id
      return match[1]
    end
    nil
  end
end
