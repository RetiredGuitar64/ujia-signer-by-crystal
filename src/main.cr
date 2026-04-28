require "option_parser"

require "./checker.cr"
require "./web.cr"
require "./status.cr"
require "./accounts_reader.cr"
require "./auth_saver.cr"

# 默认认证模式为关
auth_mode : Bool = false

OptionParser.parse do |parser|
  parser.banner = "Usage: ujiacrystal [arguments]"
  parser.on("-u", "--get-token", "Get your account's token"){ auth_mode = true }
  parser.on("-h", "--help", "Show this help"){ puts parser; exit }
end

# -u 认证并获取token
if auth_mode
  puts "开始密码认证"
  sleep 1.seconds

  auth = AuthSaver.new
  puts "请输入手机号: "
  phone : String = gets || ""

  if phone.size != 11
    puts "手机号位数不正确！"
    exit(1)
  end

  puts "请输入密码："
  password : String = gets || ""

  print "\e[2J\e[H"
  STDOUT.flush

  puts "开始认证..."
  token = auth.auth_with_password(phone, password)
  sleep 1.seconds
  Log.info{ "认证完毕：请自行将token加入账号文件" }

  exit
end

# 启动主程序
#
# 读取账号
accounts_reader = AccountsReader.new
accounts = accounts_reader.read_accounts

# 空的话，直接退出
if accounts.empty?
  Log.fatal{"无可用账号，程序退出"}
  exit(1)
end

# 初始化web状态变量
status = Status.new

# 传入status,启动web
web = Web.new(status)
web.start

# 传入status和账号数组，启动轮询
checker = Checker.new(status, accounts)
checker.run
