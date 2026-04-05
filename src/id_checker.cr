require "./accounts.cr"
require "http/client"
require "json"
require "log"

SLEEP_GAP_IN_LOOP = 2
# 签到id正则
COURSE_SIGN_IN_ID_RE = /"courseSignInId"\s*:\s*"([0-9a-f]{32})"/
CODE_DISTANCE_RE = /"codeDistance"\s*:\s*"(\d{3,4})"/

class Checker
  getter name, token

  def initialize(@name : String = ACCOUNTS[0][0], @token : String = ACCOUNTS[0][1])
  end

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

    Log.info{"轮询已开始..."}
    loop do
      response = HTTP::Client.get(id_check_url, check_headers)

      if response.status_code == 200
        if courseSignInId = detect_courseSignInId(response)
          Log.info{"探测到签到: #{courseSignInId}"}
          # 开始获取签到码
          code_check_url = "https://www.eduplus.net/api/course/clock_in/#{courseSignInId}/student" # codecheck的url
          response_of_code_check = HTTP::Client.get(code_check_url, check_headers)
          codeDistance = detect_codeDistance(response_of_code_check)

          # 进入签到流程
          puts codeDistance

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

  def detect_codeDistance(response : HTTP::Client::Response) : String
    if match = CODE_DISTANCE_RE.match(response.body)
      return match[1]
    else
      Log.warn{"未匹配到签到码字段，未知错误，将默认以普通签到进行"}
      return "200"
    end
  end
end
