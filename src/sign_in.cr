require "http/client"
require "json"
require "log"
require "./create_student.cr"
require "./accounts.cr"

SIGN_IN_BELOW_HOW_MANY_SECONDS = 20

class Signer
  def initialize()
    # 提前初始化学生列表, 提高开始签到后的速度
    @students = [] of Student  # 每一个学生对象都存在这个数组里

    # 初始化学生列表
    ACCOUNTS.each do |account|
      student = Student.new(account)
      @students << student
    end
  end

  def run(courseSignInId : String, codeDistance : String)
    # 判断为普通签到还是密码签到
    if codeDistance == "200"
      # 普通签到，"200", 则签到url为空
      codeStringUrl = nil
    else
      # 如果为密码签到，拼接url和密码
      codeStringUrl = "&codeDistance=" + codeDistance
    end

    # 进行签到post
    @students.each do |student|
      student.post(courseSignInId, codeStringUrl)
    end

  end
end
