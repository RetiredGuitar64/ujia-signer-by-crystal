require "./checker.cr"
require "./web.cr"
require "./status.cr"
require "./accounts_reader.cr"

accounts_reader = AccountsReader.new
accounts = accounts_reader.read_accounts

if accounts.empty?
  Log.fatal{"无可用账号，程序退出"}
  exit(1)
end

status = Status.new

web = Web.new(status)
web.start

checker = Checker.new(status, accounts)
checker.run
