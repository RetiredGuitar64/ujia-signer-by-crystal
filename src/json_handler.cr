require "json"

class JsonHandler

  # 检查token是否可用：即检查data[]是否为空，以及data中的课程是否有courseSignInOpen字段
  def self.token_available?(body : String) : Bool
    json = JSON.parse(body)

    # 课程数组
    course_data = json["data"].as_a

    # 若为空，直接false,即token不可用
    return false if course_data.empty?

    # 挨着检查, 每个课程里是否有 courseSignInOpen 字段,没有直接false
    course_data.each do |course|
      return false if course["courseSignInOpen"]?.nil?
    end

    # 全通过才会true
    return true
  end

  # 抓取签到id,
  def self.catch_courseSignInId(body : String) : (String | Nil)
    json = JSON.parse(body)
    course_data = json["data"].as_a

    # 挨着找，有没有签到id字段，没有就下一个，有就直接返回（也就是一次只能签到一门课）
    course_data.each do |course|
      if sign_in_id = course["courseSignInId"]?
        return sign_in_id.as_s
      end
    end

    # 全空返回nil, 即没有签到
    return nil
  end

  # 抓取签到码
  def self.catch_codeDistance(body : String) : String
    json = JSON.parse(body)

    # 保险一点，防止这个data也没了
    if data = json["data"]?
      if codeDistance = data["codeDistance"]?
        return codeDistance.as_s
      end
    end

    Log.warn{"未匹配到签到码字段，未知错误，将默认以普通签到进行"}
    return "200"
  end

  # 抓取签到剩余秒数
  def self.catch_remaining_seconds(body : String) : Int32
    json = JSON.parse(body)

    # 保险一点，防止这个data也没了
    if data = json["data"]?
      if remainingTime = data["remainingTime"]?
        return remainingTime.as_i
      end
    end

    # 无法获取签到时间，就返回0, 即立即签到
    return 0
  end

  # 抓取签到是否成功
  def self.catch_sign_successful?(body : String) : Bool
    json = JSON.parse(body)

    # 探测success是否为true
    if success = json["success"]?
      return success.as_bool
    else
      # 未探测到的话，直接按照未签到成功处理，返回false
      return false
    end
  end

  # 抓取公钥
  def self.catch_public_key(body : String) : (String | Nil)
    json = JSON.parse(body)

    if data = json["data"]?
      if public_key = data["encryptionKey"]?
        return public_key.as_s
      else
        return nil
      end
    else
      return nil
    end
  end
end
