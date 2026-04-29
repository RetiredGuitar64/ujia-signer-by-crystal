require "json"

class JsonHandler
  def self.token_avaliable?(body : String) : Bool
    json = JSON.parse(body)
    course_data = json["data"].as_a
    return false if course_data.empty?

    course_data.each do |course|
      return false if course["courseSignInOpen"]?.nil?
    end

    return true
  end

  def self.catch_courseSignInId(body : String) : (String | Nil)
    json = JSON.parse(body)
    course_data = json["data"].as_a

    course_data.each do |course|
      if sign_in_id = course["courseSignInId"]?
        return sign_in_id.as_s
      end
    end

    return nil
  end
end
