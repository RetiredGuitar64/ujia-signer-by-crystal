require "json"

class JsonHandler

  # 检查token是否可用：即检查data[]是否为空，以及data中的课程是否有courseSignInOpen字段
  def self.token_avaliable?(body : String) : Bool
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
end
