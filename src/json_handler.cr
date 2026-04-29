require "json"

class JsonHandler
  def self.token_avaliable?(body : String) : Bool
    json = JSON.parse(body)
    course_data = json["data"].as_a
    course_data.each do |course|
      return false if course["courseSignInOpen"]?.nil?
    end

    return true
  end
end
