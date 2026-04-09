require "log"

class AccountsReader
  # accounts实例变量，用来存储账号，改为数组里装namedtuple
  @accounts : Array({name: String, token: String})

  # getter 使得外部可读
  getter accounts : Array({name: String, token: String})

  def initialize
    @accounts = [] of {name: String, token: String}
  end

  # 读取账号方法
  def read_accounts(path : String = "./accounts.txt") : Array({name: String, token: String}) # 默认文件为同目录下的 accounts.txt
    # 清理账号残留（若有
    @accounts.clear

    begin
      # 逐行加载
      File.each_line(path) do |line|

        # 删除空格
        line = line.strip

        # 忽略空行
        next if line.empty?

        # 跳过 '#' 开头的账号
        if line.starts_with?("#")
          Log.info{"--------------------"}
          Log.info{"!! 跳过账号 !! #{line}"}
          next
        end

        # 分开名字和token
        parts = line.split("|", 2)

        # 跳过错误行
        if parts.size != 2
          Log.warn{"!! 跳过格式错误行 !! #{line}"}
          next
        end

        # 分开赋值并删除左右空格
        name = parts[0].strip
        token = parts[1].strip

        # 跳过空name/token的行
        if name.empty? || token.empty?
          Log.warn{"!! 跳过 name/token 为空的行 !! #{line}"}
          next
        end

        # 警告token长度不为48的行，但是依旧加入账号列表
        if token.size != 48
          Log.info{"--------------------"}
          Log.warn{"!! 警告！账号 #{name} 的token: #{token} 不符合48位长度！token可能缺失 !!"}
          Log.info{"--------------------"}
        end

        # 加载账号
        Log.info{"加载账号 #{name}, token: #{token}"}
        @accounts << {name: name, token: token}
      end
    rescue ex
      Log.error{"读取账号文件失败: #{ex.message}"}
    end

    # 挨个打印账号信息
    Log.info{"--------------------"}
    Log.info{"账号加载完成:"}
    @accounts.each do |account|
      Log.info{"昵称: #{account[:name]}, token: #{account[:token]}"}
    end
    Log.info{"--------------------"}
    Log.info{"请确认账号是否缺失"}
    Log.info{"--------------------"}

    # read方法返回@accounts实例变量
    @accounts
  end
end
