require "./checker.cr"
require "./web.cr"

channel = Channel(String).new
web = Web.new(channel)
web.start


# checker = Checker.new
# checker.run
