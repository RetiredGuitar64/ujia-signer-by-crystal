require "log"
require "http/client"

# 匹配公钥
ENCRYPTION_KEY_RE = /"encryptionKey"\s*:\s*"([^"]+)"/

# 匹配token
ACCESS_TOKEN_RE = /"accessToken"\s*:\s*"([A-Za-z0-9\-]{48})"/

class AuthSaver
  def initialize
  end

  # 使用的时候，直接用这个
  def auth_with_password(phone : String, password : String) : String
    # 获取公钥
    public_key = get_public_key_with_password_login()

    # 加密
    cryptogram = encode(public_key, phone, password)

    # 获取token
    token = get_token_with_password_login(public_key, cryptogram)

    # 检查token可用性
    return "!! token 不可用!! : #{token}" if checkup_if_token_is_avaliable(token) == false

    return token
  end

  # 验证码登录，未实现
  def auth_with_captcha(phone : String) : String
  end

  def get_public_key_with_password_login() : String
    post_url = "https://uc.eduplus.net/spi/login/checkup"
    post_headers = HTTP::Headers{
    "accept"          => "application/json, text/plain, */*",
    "content-type"    => "application/json",
    "user-agent"      => "okhttp/4.12.0",
    "host"            => "uc.eduplus.net",
    "connection"      => "Keep-Alive",
    }
    post_body = %({"mode":"Password","loginAndRegister":true})

    # 拿响应
    response = HTTP::Client.post(post_url, headers: post_headers, body: post_body)
    # 匹配公钥字段
    if match = ENCRYPTION_KEY_RE.match(response.body)
      Log.info{"申请到公钥: #{match[1]}"}
      return match[1]
    else
      Log.warn{"未匹配到服务端下发公钥, 状态码: #{response.status_code}, 响应体: #{response.body}"}
      Log.error{"公钥获取失败，请手动处理"}
      return "!! 公钥为空 !!"
    end
  end

  def encode(public_key : String, phone : String, password : String) : String
    Log.info{"开始加密..."}
    begin
      # 开临时文件，
      temp_script = File.tempfile("ujia_encode_script_tempfile.mjs")
      # 将加密脚本放入
      temp_script << puts_script
      # 确保文件落盘
      temp_script.flush

      # 申请内存，记录输出
      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new

      # 开一个新的进程运行node, 加密流程
      status = Process.run(
        "node",
        args: [temp_script.path, "--public-key", public_key, "--identifier", phone, "--password", password, "--only-cryptogram"],
        output: stdout_io,
        error: stderr_io,
      )

      # 加密失败，报错
      unless status.success?
        Log.error{"!! 加密失败 !! exitCode = #{status.exit_code}, stderr = #{stderr_io.to_s}"}
      end

      # 密文，去除空格
      cryptogram = stdout_io.to_s.strip
      Log.info{"加密完成：cryptogram: #{cryptogram}"}

      return cryptogram
    ensure
      # 确保临时文件删除
      if temp_script
        path = temp_script.path
        temp_script.close
        File.delete(path) if File.exists?(path)
      else
        Log.error{"!! 未知错误：临时脚本为nil !!"}
      end
    end
  end

  def get_token_with_password_login(public_key : String, cryptogram : String) : String
    post_url = "https://uc.eduplus.net/spi/login/submit"
    post_headers = HTTP::Headers{
      "accept"       => "application/json, text/plain, */*",
      "content-type" => "application/json",
      "host"         => "uc.eduplus.net",
      "connection"   => "Keep-Alive",
      "user-agent"   => "okhttp/4.12.0",
    }
    post_body = %({"mode":"Password","encryptionKey":"#{public_key}","cryptogram":"#{cryptogram}"})

    # 拿响应
    response = HTTP::Client.post(post_url, headers: post_headers, body: post_body)

    # 匹配token字段
    if match = ACCESS_TOKEN_RE.match(response.body)
      Log.info{"获得token: #{match[1]}"}
      return match[1]
    else
      Log.error{"未匹配到token字段, 响应体: #{response.body}"}
      return "!! token为空 !!"
    end
  end

  def checkup_if_token_is_avaliable(token : String) : Bool
    Log.info{"检查token可用性"}

    cookie = "SESSION=#{token}"

    id_check_url = "https://www.eduplus.net/api/course/courses/v1/study?types=Theory,Train"
    check_headers = HTTP::Headers{
      "accept"         => "application/json, text/plain, */*",
      "x-access-token" => token,
      "cookie"         => cookie,
      "user-agent"     => "okhttp/4.12.0",
      "host"           => "www.eduplus.net",
      "connection"     => "Keep-Alive",
    }

    # 拿到响应
    response = HTTP::Client.get(id_check_url, check_headers)

    # 状态码判断
    if response.status_code == 200
      Log.info{"检查完毕：token可用"}
      return true
    else
      Log.error{"!! token不可用 !! #{token} 响应体: #{response.body}"}
      return false
    end
  end

  # 脚本内容，放在最后位置，后面没有别的方法了
  def puts_script
    <<-HEREDOC
    import { readFile } from "node:fs/promises";
    import { resolve } from "node:path";
    import { webcrypto } from "node:crypto";
    import { createInterface } from "node:readline/promises";
    import { stdin as input, stdout as output, argv } from "node:process";
    import { fileURLToPath } from "node:url";

    const __filename = fileURLToPath(import.meta.url);
    const EMBEDDED_VENDOR_MODULE_BASE64 = [
      "dmFyIEV0PSIwMTIzNDU2Nzg5YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoiO2Z1bmN0aW9uIEEocil7cmV0dXJuIEV0LmNoYXJBdChyKX1mdW5jdGlvbiBE",
      "dChyLHQpe3JldHVybiByJnR9ZnVuY3Rpb24gWihyLHQpe3JldHVybiByfHR9ZnVuY3Rpb24gYXQocix0KXtyZXR1cm4gcl50fWZ1bmN0aW9uIHV0KHIsdCl7",
      "cmV0dXJuIHImfnR9ZnVuY3Rpb24geHQocil7aWYocj09MClyZXR1cm4tMTt2YXIgdD0wO3JldHVybihyJjY1NTM1KT09MCYmKHI+Pj0xNix0Kz0xNiksKHIm",
      "MjU1KT09MCYmKHI+Pj04LHQrPTgpLChyJjE1KT09MCYmKHI+Pj00LHQrPTQpLChyJjMpPT0wJiYocj4+PTIsdCs9MiksKHImMSk9PTAmJisrdCx0fWZ1bmN0",
      "aW9uIFJ0KHIpe2Zvcih2YXIgdD0wO3IhPTA7KXImPXItMSwrK3Q7cmV0dXJuIHR9dmFyIEM9IkFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaYWJjZGVmZ2hp",
      "amtsbW5vcHFyc3R1dnd4eXowMTIzNDU2Nzg5Ky8iLFR0PSI9IjtmdW5jdGlvbiBXKHIpe3ZhciB0LGUsaT0iIjtmb3IodD0wO3QrMzw9ci5sZW5ndGg7dCs9",
      "MyllPXBhcnNlSW50KHIuc3Vic3RyaW5nKHQsdCszKSwxNiksaSs9Qy5jaGFyQXQoZT4+NikrQy5jaGFyQXQoZSY2Myk7Zm9yKHQrMT09ci5sZW5ndGg/KGU9",
      "cGFyc2VJbnQoci5zdWJzdHJpbmcodCx0KzEpLDE2KSxpKz1DLmNoYXJBdChlPDwyKSk6dCsyPT1yLmxlbmd0aCYmKGU9cGFyc2VJbnQoci5zdWJzdHJpbmco",
      "dCx0KzIpLDE2KSxpKz1DLmNoYXJBdChlPj4yKStDLmNoYXJBdCgoZSYzKTw8NCkpOyhpLmxlbmd0aCYzKT4wOylpKz1UdDtyZXR1cm4gaX1mdW5jdGlvbiBs",
      "dChyKXt2YXIgdD0iIixlLGk9MCxuPTA7Zm9yKGU9MDtlPHIubGVuZ3RoJiZyLmNoYXJBdChlKSE9VHQ7KytlKXt2YXIgcz1DLmluZGV4T2Yoci5jaGFyQXQo",
      "ZSkpO3M8MHx8KGk9PTA/KHQrPUEocz4+Miksbj1zJjMsaT0xKTppPT0xPyh0Kz1BKG48PDJ8cz4+NCksbj1zJjE1LGk9Mik6aT09Mj8odCs9QShuKSx0Kz1B",
      "KHM+PjIpLG49cyYzLGk9Myk6KHQrPUEobjw8MnxzPj40KSx0Kz1BKHMmMTUpLGk9MCkpfXJldHVybiBpPT0xJiYodCs9QShuPDwyKSksdH12YXIgSCxCdD17",
      "ZGVjb2RlOmZ1bmN0aW9uKHIpe3ZhciB0O2lmKEg9PT12b2lkIDApe3ZhciBlPSIwMTIzNDU2Nzg5QUJDREVGIixpPSIgXGZcblxyCcKgXHUyMDI4XHUyMDI5",
      "Ijtmb3IoSD17fSx0PTA7dDwxNjsrK3QpSFtlLmNoYXJBdCh0KV09dDtmb3IoZT1lLnRvTG93ZXJDYXNlKCksdD0xMDt0PDE2OysrdClIW2UuY2hhckF0KHQp",
      "XT10O2Zvcih0PTA7dDxpLmxlbmd0aDsrK3QpSFtpLmNoYXJBdCh0KV09LTF9dmFyIG49W10scz0wLGg9MDtmb3IodD0wO3Q8ci5sZW5ndGg7Kyt0KXt2YXIg",
      "bz1yLmNoYXJBdCh0KTtpZihvPT0iPSIpYnJlYWs7aWYobz1IW29dLG8hPS0xKXtpZihvPT09dm9pZCAwKXRocm93IG5ldyBFcnJvcigiSWxsZWdhbCBjaGFy",
      "YWN0ZXIgYXQgb2Zmc2V0ICIrdCk7c3w9bywrK2g+PTI/KG5bbi5sZW5ndGhdPXMscz0wLGg9MCk6czw8PTR9fWlmKGgpdGhyb3cgbmV3IEVycm9yKCJIZXgg",
      "ZW5jb2RpbmcgaW5jb21wbGV0ZTogNCBiaXRzIG1pc3NpbmciKTtyZXR1cm4gbn19LFAsc3Q9e2RlY29kZTpmdW5jdGlvbihyKXt2YXIgdDtpZihQPT09dm9p",
      "ZCAwKXt2YXIgZT0iQUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejAxMjM0NTY3ODkrLyIsaT0iPSBcZlxuXHIJ",
      "wqBcdTIwMjhcdTIwMjkiO2ZvcihQPU9iamVjdC5jcmVhdGUobnVsbCksdD0wO3Q8NjQ7Kyt0KVBbZS5jaGFyQXQodCldPXQ7Zm9yKFBbIi0iXT02MixQLl89",
      "NjMsdD0wO3Q8aS5sZW5ndGg7Kyt0KVBbaS5jaGFyQXQodCldPS0xfXZhciBuPVtdLHM9MCxoPTA7Zm9yKHQ9MDt0PHIubGVuZ3RoOysrdCl7dmFyIG89ci5j",
      "aGFyQXQodCk7aWYobz09Ij0iKWJyZWFrO2lmKG89UFtvXSxvIT0tMSl7aWYobz09PXZvaWQgMCl0aHJvdyBuZXcgRXJyb3IoIklsbGVnYWwgY2hhcmFjdGVy",
      "IGF0IG9mZnNldCAiK3QpO3N8PW8sKytoPj00PyhuW24ubGVuZ3RoXT1zPj4xNixuW24ubGVuZ3RoXT1zPj44JjI1NSxuW24ubGVuZ3RoXT1zJjI1NSxzPTAs",
      "aD0wKTpzPDw9Nn19c3dpdGNoKGgpe2Nhc2UgMTp0aHJvdyBuZXcgRXJyb3IoIkJhc2U2NCBlbmNvZGluZyBpbmNvbXBsZXRlOiBhdCBsZWFzdCAyIGJpdHMg",
      "bWlzc2luZyIpO2Nhc2UgMjpuW24ubGVuZ3RoXT1zPj4xMDticmVhaztjYXNlIDM6bltuLmxlbmd0aF09cz4+MTYsbltuLmxlbmd0aF09cz4+OCYyNTU7YnJl",
      "YWt9cmV0dXJuIG59LHJlOi8tLS0tLUJFR0lOIFteLV0rLS0tLS0oW0EtWmEtejAtOStcLz1cc10rKS0tLS0tRU5EIFteLV0rLS0tLS18YmVnaW4tYmFzZTY0",
      "W15cbl0rXG4oW0EtWmEtejAtOStcLz1cc10rKT09PT0vLHVuYXJtb3I6ZnVuY3Rpb24ocil7dmFyIHQ9c3QucmUuZXhlYyhyKTtpZih0KWlmKHRbMV0pcj10",
      "WzFdO2Vsc2UgaWYodFsyXSlyPXRbMl07ZWxzZSB0aHJvdyBuZXcgRXJyb3IoIlJlZ0V4cCBvdXQgb2Ygc3luYyIpO3JldHVybiBzdC5kZWNvZGUocil9fSxf",
      "PTFlMTMsaj1mdW5jdGlvbigpe2Z1bmN0aW9uIHIodCl7dGhpcy5idWY9Wyt0fHwwXX1yZXR1cm4gci5wcm90b3R5cGUubXVsQWRkPWZ1bmN0aW9uKHQsZSl7",
      "dmFyIGk9dGhpcy5idWYsbj1pLmxlbmd0aCxzLGg7Zm9yKHM9MDtzPG47KytzKWg9aVtzXSp0K2UsaDxfP2U9MDooZT0wfGgvXyxoLT1lKl8pLGlbc109aDtl",
      "PjAmJihpW3NdPWUpfSxyLnByb3RvdHlwZS5zdWI9ZnVuY3Rpb24odCl7dmFyIGU9dGhpcy5idWYsaT1lLmxlbmd0aCxuLHM7Zm9yKG49MDtuPGk7KytuKXM9",
      "ZVtuXS10LHM8MD8ocys9Xyx0PTEpOnQ9MCxlW25dPXM7Zm9yKDtlW2UubGVuZ3RoLTFdPT09MDspZS5wb3AoKX0sci5wcm90b3R5cGUudG9TdHJpbmc9ZnVu",
      "Y3Rpb24odCl7aWYoKHR8fDEwKSE9MTApdGhyb3cgbmV3IEVycm9yKCJvbmx5IGJhc2UgMTAgaXMgc3VwcG9ydGVkIik7Zm9yKHZhciBlPXRoaXMuYnVmLGk9",
      "ZVtlLmxlbmd0aC0xXS50b1N0cmluZygpLG49ZS5sZW5ndGgtMjtuPj0wOy0tbilpKz0oXytlW25dKS50b1N0cmluZygpLnN1YnN0cmluZygxKTtyZXR1cm4g",
      "aX0sci5wcm90b3R5cGUudmFsdWVPZj1mdW5jdGlvbigpe2Zvcih2YXIgdD10aGlzLmJ1ZixlPTAsaT10Lmxlbmd0aC0xO2k+PTA7LS1pKWU9ZSpfK3RbaV07",
      "cmV0dXJuIGV9LHIucHJvdG90eXBlLnNpbXBsaWZ5PWZ1bmN0aW9uKCl7dmFyIHQ9dGhpcy5idWY7cmV0dXJuIHQubGVuZ3RoPT0xP3RbMF06dGhpc30scn0o",
      "KSxtdD0i4oCmIixBdD0vXihcZFxkKSgwWzEtOV18MVswLTJdKSgwWzEtOV18WzEyXVxkfDNbMDFdKShbMDFdXGR8MlswLTNdKSg/OihbMC01XVxkKSg/Oihb",
      "MC01XVxkKSg/OlsuLF0oXGR7MSwzfSkpPyk/KT8oWnxbLStdKD86WzBdXGR8MVswLTJdKShbMC01XVxkKT8pPyQvLE90PS9eKFxkXGRcZFxkKSgwWzEtOV18",
      "MVswLTJdKSgwWzEtOV18WzEyXVxkfDNbMDFdKShbMDFdXGR8MlswLTNdKSg/OihbMC01XVxkKSg/OihbMC01XVxkKSg/OlsuLF0oXGR7MSwzfSkpPyk/KT8o",
      "WnxbLStdKD86WzBdXGR8MVswLTJdKShbMC01XVxkKT8pPyQvO2Z1bmN0aW9uIEYocix0KXtyZXR1cm4gci5sZW5ndGg+dCYmKHI9ci5zdWJzdHJpbmcoMCx0",
      "KSttdCkscn12YXIgaXQ9ZnVuY3Rpb24oKXtmdW5jdGlvbiByKHQsZSl7dGhpcy5oZXhEaWdpdHM9IjAxMjM0NTY3ODlBQkNERUYiLHQgaW5zdGFuY2VvZiBy",
      "Pyh0aGlzLmVuYz10LmVuYyx0aGlzLnBvcz10LnBvcyk6KHRoaXMuZW5jPXQsdGhpcy5wb3M9ZSl9cmV0dXJuIHIucHJvdG90eXBlLmdldD1mdW5jdGlvbih0",
      "KXtpZih0PT09dm9pZCAwJiYodD10aGlzLnBvcysrKSx0Pj10aGlzLmVuYy5sZW5ndGgpdGhyb3cgbmV3IEVycm9yKCJSZXF1ZXN0aW5nIGJ5dGUgb2Zmc2V0",
      "ICIuY29uY2F0KHQsIiBvbiBhIHN0cmVhbSBvZiBsZW5ndGggIikuY29uY2F0KHRoaXMuZW5jLmxlbmd0aCkpO3JldHVybiB0eXBlb2YgdGhpcy5lbmM9PSJz",
      "dHJpbmciP3RoaXMuZW5jLmNoYXJDb2RlQXQodCk6dGhpcy5lbmNbdF19LHIucHJvdG90eXBlLmhleEJ5dGU9ZnVuY3Rpb24odCl7cmV0dXJuIHRoaXMuaGV4",
      "RGlnaXRzLmNoYXJBdCh0Pj40JjE1KSt0aGlzLmhleERpZ2l0cy5jaGFyQXQodCYxNSl9LHIucHJvdG90eXBlLmhleER1bXA9ZnVuY3Rpb24odCxlLGkpe2Zv",
      "cih2YXIgbj0iIixzPXQ7czxlOysrcylpZihuKz10aGlzLmhleEJ5dGUodGhpcy5nZXQocykpLGkhPT0hMClzd2l0Y2gocyYxNSl7Y2FzZSA3Om4rPSIgICI7",
      "YnJlYWs7Y2FzZSAxNTpuKz0iXG4iO2JyZWFrO2RlZmF1bHQ6bis9IiAifXJldHVybiBufSxyLnByb3RvdHlwZS5pc0FTQ0lJPWZ1bmN0aW9uKHQsZSl7Zm9y",
      "KHZhciBpPXQ7aTxlOysraSl7dmFyIG49dGhpcy5nZXQoaSk7aWYobjwzMnx8bj4xNzYpcmV0dXJuITF9cmV0dXJuITB9LHIucHJvdG90eXBlLnBhcnNlU3Ry",
      "aW5nSVNPPWZ1bmN0aW9uKHQsZSl7Zm9yKHZhciBpPSIiLG49dDtuPGU7KytuKWkrPVN0cmluZy5mcm9tQ2hhckNvZGUodGhpcy5nZXQobikpO3JldHVybiBp",
      "fSxyLnByb3RvdHlwZS5wYXJzZVN0cmluZ1VURj1mdW5jdGlvbih0LGUpe2Zvcih2YXIgaT0iIixuPXQ7bjxlOyl7dmFyIHM9dGhpcy5nZXQobisrKTtzPDEy",
      "OD9pKz1TdHJpbmcuZnJvbUNoYXJDb2RlKHMpOnM+MTkxJiZzPDIyND9pKz1TdHJpbmcuZnJvbUNoYXJDb2RlKChzJjMxKTw8Nnx0aGlzLmdldChuKyspJjYz",
      "KTppKz1TdHJpbmcuZnJvbUNoYXJDb2RlKChzJjE1KTw8MTJ8KHRoaXMuZ2V0KG4rKykmNjMpPDw2fHRoaXMuZ2V0KG4rKykmNjMpfXJldHVybiBpfSxyLnBy",
      "b3RvdHlwZS5wYXJzZVN0cmluZ0JNUD1mdW5jdGlvbih0LGUpe2Zvcih2YXIgaT0iIixuLHMsaD10O2g8ZTspbj10aGlzLmdldChoKyspLHM9dGhpcy5nZXQo",
      "aCsrKSxpKz1TdHJpbmcuZnJvbUNoYXJDb2RlKG48PDh8cyk7cmV0dXJuIGl9LHIucHJvdG90eXBlLnBhcnNlVGltZT1mdW5jdGlvbih0LGUsaSl7dmFyIG49",
      "dGhpcy5wYXJzZVN0cmluZ0lTTyh0LGUpLHM9KGk/QXQ6T3QpLmV4ZWMobik7cmV0dXJuIHM/KGkmJihzWzFdPStzWzFdLHNbMV0rPStzWzFdPDcwPzJlMzox",
      "OTAwKSxuPXNbMV0rIi0iK3NbMl0rIi0iK3NbM10rIiAiK3NbNF0sc1s1XSYmKG4rPSI6IitzWzVdLHNbNl0mJihuKz0iOiIrc1s2XSxzWzddJiYobis9Ii4i",
      "K3NbN10pKSksc1s4XSYmKG4rPSIgVVRDIixzWzhdIT0iWiImJihuKz1zWzhdLHNbOV0mJihuKz0iOiIrc1s5XSkpKSxuKToiVW5yZWNvZ25pemVkIHRpbWU6",
      "ICIrbn0sci5wcm90b3R5cGUucGFyc2VJbnRlZ2VyPWZ1bmN0aW9uKHQsZSl7Zm9yKHZhciBpPXRoaXMuZ2V0KHQpLG49aT4xMjcscz1uPzI1NTowLGgsbz0i",
      "IjtpPT1zJiYrK3Q8ZTspaT10aGlzLmdldCh0KTtpZihoPWUtdCxoPT09MClyZXR1cm4gbj8tMTowO2lmKGg+NCl7Zm9yKG89aSxoPDw9MzsoKCtvXnMpJjEy",
      "OCk9PTA7KW89K288PDEsLS1oO289IigiK2grIiBiaXQpXG4ifW4mJihpPWktMjU2KTtmb3IodmFyIGY9bmV3IGooaSksdT10KzE7dTxlOysrdSlmLm11bEFk",
      "ZCgyNTYsdGhpcy5nZXQodSkpO3JldHVybiBvK2YudG9TdHJpbmcoKX0sci5wcm90b3R5cGUucGFyc2VCaXRTdHJpbmc9ZnVuY3Rpb24odCxlLGkpe2Zvcih2",
      "YXIgbj10aGlzLmdldCh0KSxzPShlLXQtMTw8MyktbixoPSIoIitzKyIgYml0KVxuIixvPSIiLGY9dCsxO2Y8ZTsrK2Ype2Zvcih2YXIgdT10aGlzLmdldChm",
      "KSxsPWY9PWUtMT9uOjAsZz03O2c+PWw7LS1nKW8rPXU+PmcmMT8iMSI6IjAiO2lmKG8ubGVuZ3RoPmkpcmV0dXJuIGgrRihvLGkpfXJldHVybiBoK299LHIu",
      "cHJvdG90eXBlLnBhcnNlT2N0ZXRTdHJpbmc9ZnVuY3Rpb24odCxlLGkpe2lmKHRoaXMuaXNBU0NJSSh0LGUpKXJldHVybiBGKHRoaXMucGFyc2VTdHJpbmdJ",
      "U08odCxlKSxpKTt2YXIgbj1lLXQscz0iKCIrbisiIGJ5dGUpXG4iO2kvPTIsbj5pJiYoZT10K2kpO2Zvcih2YXIgaD10O2g8ZTsrK2gpcys9dGhpcy5oZXhC",
      "eXRlKHRoaXMuZ2V0KGgpKTtyZXR1cm4gbj5pJiYocys9bXQpLHN9LHIucHJvdG90eXBlLnBhcnNlT0lEPWZ1bmN0aW9uKHQsZSxpKXtmb3IodmFyIG49IiIs",
      "cz1uZXcgaixoPTAsbz10O288ZTsrK28pe3ZhciBmPXRoaXMuZ2V0KG8pO2lmKHMubXVsQWRkKDEyOCxmJjEyNyksaCs9NywhKGYmMTI4KSl7aWYobj09PSIi",
      "KWlmKHM9cy5zaW1wbGlmeSgpLHMgaW5zdGFuY2VvZiBqKXMuc3ViKDgwKSxuPSIyLiIrcy50b1N0cmluZygpO2Vsc2V7dmFyIHU9czw4MD9zPDQwPzA6MToy",
      "O249dSsiLiIrKHMtdSo0MCl9ZWxzZSBuKz0iLiIrcy50b1N0cmluZygpO2lmKG4ubGVuZ3RoPmkpcmV0dXJuIEYobixpKTtzPW5ldyBqLGg9MH19cmV0dXJu",
      "IGg+MCYmKG4rPSIuaW5jb21wbGV0ZSIpLG59LHJ9KCksVnQ9ZnVuY3Rpb24oKXtmdW5jdGlvbiByKHQsZSxpLG4scyl7aWYoIShuIGluc3RhbmNlb2YgY3Qp",
      "KXRocm93IG5ldyBFcnJvcigiSW52YWxpZCB0YWcgdmFsdWUuIik7dGhpcy5zdHJlYW09dCx0aGlzLmhlYWRlcj1lLHRoaXMubGVuZ3RoPWksdGhpcy50YWc9",
      "bix0aGlzLnN1Yj1zfXJldHVybiByLnByb3RvdHlwZS50eXBlTmFtZT1mdW5jdGlvbigpe3N3aXRjaCh0aGlzLnRhZy50YWdDbGFzcyl7Y2FzZSAwOnN3aXRj",
      "aCh0aGlzLnRhZy50YWdOdW1iZXIpe2Nhc2UgMDpyZXR1cm4iRU9DIjtjYXNlIDE6cmV0dXJuIkJPT0xFQU4iO2Nhc2UgMjpyZXR1cm4iSU5URUdFUiI7Y2Fz",
      "ZSAzOnJldHVybiJCSVRfU1RSSU5HIjtjYXNlIDQ6cmV0dXJuIk9DVEVUX1NUUklORyI7Y2FzZSA1OnJldHVybiJOVUxMIjtjYXNlIDY6cmV0dXJuIk9CSkVD",
      "VF9JREVOVElGSUVSIjtjYXNlIDc6cmV0dXJuIk9iamVjdERlc2NyaXB0b3IiO2Nhc2UgODpyZXR1cm4iRVhURVJOQUwiO2Nhc2UgOTpyZXR1cm4iUkVBTCI7",
      "Y2FzZSAxMDpyZXR1cm4iRU5VTUVSQVRFRCI7Y2FzZSAxMTpyZXR1cm4iRU1CRURERURfUERWIjtjYXNlIDEyOnJldHVybiJVVEY4U3RyaW5nIjtjYXNlIDE2",
      "OnJldHVybiJTRVFVRU5DRSI7Y2FzZSAxNzpyZXR1cm4iU0VUIjtjYXNlIDE4OnJldHVybiJOdW1lcmljU3RyaW5nIjtjYXNlIDE5OnJldHVybiJQcmludGFi",
      "bGVTdHJpbmciO2Nhc2UgMjA6cmV0dXJuIlRlbGV0ZXhTdHJpbmciO2Nhc2UgMjE6cmV0dXJuIlZpZGVvdGV4U3RyaW5nIjtjYXNlIDIyOnJldHVybiJJQTVT",
      "dHJpbmciO2Nhc2UgMjM6cmV0dXJuIlVUQ1RpbWUiO2Nhc2UgMjQ6cmV0dXJuIkdlbmVyYWxpemVkVGltZSI7Y2FzZSAyNTpyZXR1cm4iR3JhcGhpY1N0cmlu",
      "ZyI7Y2FzZSAyNjpyZXR1cm4iVmlzaWJsZVN0cmluZyI7Y2FzZSAyNzpyZXR1cm4iR2VuZXJhbFN0cmluZyI7Y2FzZSAyODpyZXR1cm4iVW5pdmVyc2FsU3Ry",
      "aW5nIjtjYXNlIDMwOnJldHVybiJCTVBTdHJpbmcifXJldHVybiJVbml2ZXJzYWxfIit0aGlzLnRhZy50YWdOdW1iZXIudG9TdHJpbmcoKTtjYXNlIDE6cmV0",
      "dXJuIkFwcGxpY2F0aW9uXyIrdGhpcy50YWcudGFnTnVtYmVyLnRvU3RyaW5nKCk7Y2FzZSAyOnJldHVybiJbIit0aGlzLnRhZy50YWdOdW1iZXIudG9TdHJp",
      "bmcoKSsiXSI7Y2FzZSAzOnJldHVybiJQcml2YXRlXyIrdGhpcy50YWcudGFnTnVtYmVyLnRvU3RyaW5nKCl9fSxyLnByb3RvdHlwZS5jb250ZW50PWZ1bmN0",
      "aW9uKHQpe2lmKHRoaXMudGFnPT09dm9pZCAwKXJldHVybiBudWxsO3Q9PT12b2lkIDAmJih0PTEvMCk7dmFyIGU9dGhpcy5wb3NDb250ZW50KCksaT1NYXRo",
      "LmFicyh0aGlzLmxlbmd0aCk7aWYoIXRoaXMudGFnLmlzVW5pdmVyc2FsKCkpcmV0dXJuIHRoaXMuc3ViIT09bnVsbD8iKCIrdGhpcy5zdWIubGVuZ3RoKyIg",
      "ZWxlbSkiOnRoaXMuc3RyZWFtLnBhcnNlT2N0ZXRTdHJpbmcoZSxlK2ksdCk7c3dpdGNoKHRoaXMudGFnLnRhZ051bWJlcil7Y2FzZSAxOnJldHVybiB0aGlz",
      "LnN0cmVhbS5nZXQoZSk9PT0wPyJmYWxzZSI6InRydWUiO2Nhc2UgMjpyZXR1cm4gdGhpcy5zdHJlYW0ucGFyc2VJbnRlZ2VyKGUsZStpKTtjYXNlIDM6cmV0",
      "dXJuIHRoaXMuc3ViPyIoIit0aGlzLnN1Yi5sZW5ndGgrIiBlbGVtKSI6dGhpcy5zdHJlYW0ucGFyc2VCaXRTdHJpbmcoZSxlK2ksdCk7Y2FzZSA0OnJldHVy",
      "biB0aGlzLnN1Yj8iKCIrdGhpcy5zdWIubGVuZ3RoKyIgZWxlbSkiOnRoaXMuc3RyZWFtLnBhcnNlT2N0ZXRTdHJpbmcoZSxlK2ksdCk7Y2FzZSA2OnJldHVy",
      "biB0aGlzLnN0cmVhbS5wYXJzZU9JRChlLGUraSx0KTtjYXNlIDE2OmNhc2UgMTc6cmV0dXJuIHRoaXMuc3ViIT09bnVsbD8iKCIrdGhpcy5zdWIubGVuZ3Ro",
      "KyIgZWxlbSkiOiIobm8gZWxlbSkiO2Nhc2UgMTI6cmV0dXJuIEYodGhpcy5zdHJlYW0ucGFyc2VTdHJpbmdVVEYoZSxlK2kpLHQpO2Nhc2UgMTg6Y2FzZSAx",
      "OTpjYXNlIDIwOmNhc2UgMjE6Y2FzZSAyMjpjYXNlIDI2OnJldHVybiBGKHRoaXMuc3RyZWFtLnBhcnNlU3RyaW5nSVNPKGUsZStpKSx0KTtjYXNlIDMwOnJl",
      "dHVybiBGKHRoaXMuc3RyZWFtLnBhcnNlU3RyaW5nQk1QKGUsZStpKSx0KTtjYXNlIDIzOmNhc2UgMjQ6cmV0dXJuIHRoaXMuc3RyZWFtLnBhcnNlVGltZShl",
      "LGUraSx0aGlzLnRhZy50YWdOdW1iZXI9PTIzKX1yZXR1cm4gbnVsbH0sci5wcm90b3R5cGUudG9TdHJpbmc9ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy50eXBl",
      "TmFtZSgpKyJAIit0aGlzLnN0cmVhbS5wb3MrIltoZWFkZXI6Iit0aGlzLmhlYWRlcisiLGxlbmd0aDoiK3RoaXMubGVuZ3RoKyIsc3ViOiIrKHRoaXMuc3Vi",
      "PT09bnVsbD8ibnVsbCI6dGhpcy5zdWIubGVuZ3RoKSsiXSJ9LHIucHJvdG90eXBlLnRvUHJldHR5U3RyaW5nPWZ1bmN0aW9uKHQpe3Q9PT12b2lkIDAmJih0",
      "PSIiKTt2YXIgZT10K3RoaXMudHlwZU5hbWUoKSsiIEAiK3RoaXMuc3RyZWFtLnBvcztpZih0aGlzLmxlbmd0aD49MCYmKGUrPSIrIiksZSs9dGhpcy5sZW5n",
      "dGgsdGhpcy50YWcudGFnQ29uc3RydWN0ZWQ/ZSs9IiAoY29uc3RydWN0ZWQpIjp0aGlzLnRhZy5pc1VuaXZlcnNhbCgpJiYodGhpcy50YWcudGFnTnVtYmVy",
      "PT0zfHx0aGlzLnRhZy50YWdOdW1iZXI9PTQpJiZ0aGlzLnN1YiE9PW51bGwmJihlKz0iIChlbmNhcHN1bGF0ZXMpIiksZSs9IlxuIix0aGlzLnN1YiE9PW51",
      "bGwpe3QrPSIgICI7Zm9yKHZhciBpPTAsbj10aGlzLnN1Yi5sZW5ndGg7aTxuOysraSllKz10aGlzLnN1YltpXS50b1ByZXR0eVN0cmluZyh0KX1yZXR1cm4g",
      "ZX0sci5wcm90b3R5cGUucG9zU3RhcnQ9ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy5zdHJlYW0ucG9zfSxyLnByb3RvdHlwZS5wb3NDb250ZW50PWZ1bmN0aW9u",
      "KCl7cmV0dXJuIHRoaXMuc3RyZWFtLnBvcyt0aGlzLmhlYWRlcn0sci5wcm90b3R5cGUucG9zRW5kPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuc3RyZWFtLnBv",
      "cyt0aGlzLmhlYWRlcitNYXRoLmFicyh0aGlzLmxlbmd0aCl9LHIucHJvdG90eXBlLnRvSGV4U3RyaW5nPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuc3RyZWFt",
      "LmhleER1bXAodGhpcy5wb3NTdGFydCgpLHRoaXMucG9zRW5kKCksITApfSxyLmRlY29kZUxlbmd0aD1mdW5jdGlvbih0KXt2YXIgZT10LmdldCgpLGk9ZSYx",
      "Mjc7aWYoaT09ZSlyZXR1cm4gaTtpZihpPjYpdGhyb3cgbmV3IEVycm9yKCJMZW5ndGggb3ZlciA0OCBiaXRzIG5vdCBzdXBwb3J0ZWQgYXQgcG9zaXRpb24g",
      "IisodC5wb3MtMSkpO2lmKGk9PT0wKXJldHVybiBudWxsO2U9MDtmb3IodmFyIG49MDtuPGk7KytuKWU9ZSoyNTYrdC5nZXQoKTtyZXR1cm4gZX0sci5wcm90",
      "b3R5cGUuZ2V0SGV4U3RyaW5nVmFsdWU9ZnVuY3Rpb24oKXt2YXIgdD10aGlzLnRvSGV4U3RyaW5nKCksZT10aGlzLmhlYWRlcioyLGk9dGhpcy5sZW5ndGgq",
      "MjtyZXR1cm4gdC5zdWJzdHIoZSxpKX0sci5kZWNvZGU9ZnVuY3Rpb24odCl7dmFyIGU7dCBpbnN0YW5jZW9mIGl0P2U9dDplPW5ldyBpdCh0LDApO3ZhciBp",
      "PW5ldyBpdChlKSxuPW5ldyBjdChlKSxzPXIuZGVjb2RlTGVuZ3RoKGUpLGg9ZS5wb3Msbz1oLWkucG9zLGY9bnVsbCx1PWZ1bmN0aW9uKCl7dmFyIGc9W107",
      "aWYocyE9PW51bGwpe2Zvcih2YXIgZD1oK3M7ZS5wb3M8ZDspZ1tnLmxlbmd0aF09ci5kZWNvZGUoZSk7aWYoZS5wb3MhPWQpdGhyb3cgbmV3IEVycm9yKCJD",
      "b250ZW50IHNpemUgaXMgbm90IGNvcnJlY3QgZm9yIGNvbnRhaW5lciBzdGFydGluZyBhdCBvZmZzZXQgIitoKX1lbHNlIHRyeXtmb3IoOzspe3ZhciB5PXIu",
      "ZGVjb2RlKGUpO2lmKHkudGFnLmlzRU9DKCkpYnJlYWs7Z1tnLmxlbmd0aF09eX1zPWgtZS5wb3N9Y2F0Y2goVCl7dGhyb3cgbmV3IEVycm9yKCJFeGNlcHRp",
      "b24gd2hpbGUgZGVjb2RpbmcgdW5kZWZpbmVkIGxlbmd0aCBjb250ZW50OiAiK1QpfXJldHVybiBnfTtpZihuLnRhZ0NvbnN0cnVjdGVkKWY9dSgpO2Vsc2Ug",
      "aWYobi5pc1VuaXZlcnNhbCgpJiYobi50YWdOdW1iZXI9PTN8fG4udGFnTnVtYmVyPT00KSl0cnl7aWYobi50YWdOdW1iZXI9PTMmJmUuZ2V0KCkhPTApdGhy",
      "b3cgbmV3IEVycm9yKCJCSVQgU1RSSU5HcyB3aXRoIHVudXNlZCBiaXRzIGNhbm5vdCBlbmNhcHN1bGF0ZS4iKTtmPXUoKTtmb3IodmFyIGw9MDtsPGYubGVu",
      "Z3RoOysrbClpZihmW2xdLnRhZy5pc0VPQygpKXRocm93IG5ldyBFcnJvcigiRU9DIGlzIG5vdCBzdXBwb3NlZCB0byBiZSBhY3R1YWwgY29udGVudC4iKX1j",
      "YXRjaChnKXtmPW51bGx9aWYoZj09PW51bGwpe2lmKHM9PT1udWxsKXRocm93IG5ldyBFcnJvcigiV2UgY2FuJ3Qgc2tpcCBvdmVyIGFuIGludmFsaWQgdGFn",
      "IHdpdGggdW5kZWZpbmVkIGxlbmd0aCBhdCBvZmZzZXQgIitoKTtlLnBvcz1oK01hdGguYWJzKHMpfXJldHVybiBuZXcgcihpLG8scyxuLGYpfSxyfSgpLGN0",
      "PWZ1bmN0aW9uKCl7ZnVuY3Rpb24gcih0KXt2YXIgZT10LmdldCgpO2lmKHRoaXMudGFnQ2xhc3M9ZT4+Nix0aGlzLnRhZ0NvbnN0cnVjdGVkPShlJjMyKSE9",
      "PTAsdGhpcy50YWdOdW1iZXI9ZSYzMSx0aGlzLnRhZ051bWJlcj09MzEpe3ZhciBpPW5ldyBqO2RvIGU9dC5nZXQoKSxpLm11bEFkZCgxMjgsZSYxMjcpO3do",
      "aWxlKGUmMTI4KTt0aGlzLnRhZ051bWJlcj1pLnNpbXBsaWZ5KCl9fXJldHVybiByLnByb3RvdHlwZS5pc1VuaXZlcnNhbD1mdW5jdGlvbigpe3JldHVybiB0",
      "aGlzLnRhZ0NsYXNzPT09MH0sci5wcm90b3R5cGUuaXNFT0M9ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy50YWdDbGFzcz09PTAmJnRoaXMudGFnTnVtYmVyPT09",
      "MH0scn0oKSxJLEl0PTB4ZGVhZGJlZWZjYWZlLHB0PShJdCYxNjc3NzIxNSk9PTE1NzE1MDcwLHc9WzIsMyw1LDcsMTEsMTMsMTcsMTksMjMsMjksMzEsMzcs",
      "NDEsNDMsNDcsNTMsNTksNjEsNjcsNzEsNzMsNzksODMsODksOTcsMTAxLDEwMywxMDcsMTA5LDExMywxMjcsMTMxLDEzNywxMzksMTQ5LDE1MSwxNTcsMTYz",
      "LDE2NywxNzMsMTc5LDE4MSwxOTEsMTkzLDE5NywxOTksMjExLDIyMywyMjcsMjI5LDIzMywyMzksMjQxLDI1MSwyNTcsMjYzLDI2OSwyNzEsMjc3LDI4MSwy",
      "ODMsMjkzLDMwNywzMTEsMzEzLDMxNywzMzEsMzM3LDM0NywzNDksMzUzLDM1OSwzNjcsMzczLDM3OSwzODMsMzg5LDM5Nyw0MDEsNDA5LDQxOSw0MjEsNDMx",
      "LDQzMyw0MzksNDQzLDQ0OSw0NTcsNDYxLDQ2Myw0NjcsNDc5LDQ4Nyw0OTEsNDk5LDUwMyw1MDksNTIxLDUyMyw1NDEsNTQ3LDU1Nyw1NjMsNTY5LDU3MSw1",
      "NzcsNTg3LDU5Myw1OTksNjAxLDYwNyw2MTMsNjE3LDYxOSw2MzEsNjQxLDY0Myw2NDcsNjUzLDY1OSw2NjEsNjczLDY3Nyw2ODMsNjkxLDcwMSw3MDksNzE5",
      "LDcyNyw3MzMsNzM5LDc0Myw3NTEsNzU3LDc2MSw3NjksNzczLDc4Nyw3OTcsODA5LDgxMSw4MjEsODIzLDgyNyw4MjksODM5LDg1Myw4NTcsODU5LDg2Myw4",
      "NzcsODgxLDg4Myw4ODcsOTA3LDkxMSw5MTksOTI5LDkzNyw5NDEsOTQ3LDk1Myw5NjcsOTcxLDk3Nyw5ODMsOTkxLDk5N10sTnQ9KDE8PDI2KS93W3cubGVu",
      "Z3RoLTFdLGM9ZnVuY3Rpb24oKXtmdW5jdGlvbiByKHQsZSxpKXt0IT1udWxsJiYodHlwZW9mIHQ9PSJudW1iZXIiP3RoaXMuZnJvbU51bWJlcih0LGUsaSk6",
      "ZT09bnVsbCYmdHlwZW9mIHQhPSJzdHJpbmciP3RoaXMuZnJvbVN0cmluZyh0LDI1Nik6dGhpcy5mcm9tU3RyaW5nKHQsZSkpfXJldHVybiByLnByb3RvdHlw",
      "ZS50b1N0cmluZz1mdW5jdGlvbih0KXtpZih0aGlzLnM8MClyZXR1cm4iLSIrdGhpcy5uZWdhdGUoKS50b1N0cmluZyh0KTt2YXIgZTtpZih0PT0xNillPTQ7",
      "ZWxzZSBpZih0PT04KWU9MztlbHNlIGlmKHQ9PTIpZT0xO2Vsc2UgaWYodD09MzIpZT01O2Vsc2UgaWYodD09NCllPTI7ZWxzZSByZXR1cm4gdGhpcy50b1Jh",
      "ZGl4KHQpO3ZhciBpPSgxPDxlKS0xLG4scz0hMSxoPSIiLG89dGhpcy50LGY9dGhpcy5EQi1vKnRoaXMuREIlZTtpZihvLS0gPjApZm9yKGY8dGhpcy5EQiYm",
      "KG49dGhpc1tvXT4+Zik+MCYmKHM9ITAsaD1BKG4pKTtvPj0wOylmPGU/KG49KHRoaXNbb10mKDE8PGYpLTEpPDxlLWYsbnw9dGhpc1stLW9dPj4oZis9dGhp",
      "cy5EQi1lKSk6KG49dGhpc1tvXT4+KGYtPWUpJmksZjw9MCYmKGYrPXRoaXMuREIsLS1vKSksbj4wJiYocz0hMCkscyYmKGgrPUEobikpO3JldHVybiBzP2g6",
      "IjAifSxyLnByb3RvdHlwZS5uZWdhdGU9ZnVuY3Rpb24oKXt2YXIgdD1wKCk7cmV0dXJuIHIuWkVSTy5zdWJUbyh0aGlzLHQpLHR9LHIucHJvdG90eXBlLmFi",
      "cz1mdW5jdGlvbigpe3JldHVybiB0aGlzLnM8MD90aGlzLm5lZ2F0ZSgpOnRoaXN9LHIucHJvdG90eXBlLmNvbXBhcmVUbz1mdW5jdGlvbih0KXt2YXIgZT10",
      "aGlzLnMtdC5zO2lmKGUhPTApcmV0dXJuIGU7dmFyIGk9dGhpcy50O2lmKGU9aS10LnQsZSE9MClyZXR1cm4gdGhpcy5zPDA/LWU6ZTtmb3IoOy0taT49MDsp",
      "aWYoKGU9dGhpc1tpXS10W2ldKSE9MClyZXR1cm4gZTtyZXR1cm4gMH0sci5wcm90b3R5cGUuYml0TGVuZ3RoPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMudDw9",
      "MD8wOnRoaXMuREIqKHRoaXMudC0xKStHKHRoaXNbdGhpcy50LTFdXnRoaXMucyZ0aGlzLkRNKX0sci5wcm90b3R5cGUubW9kPWZ1bmN0aW9uKHQpe3ZhciBl",
      "PXAoKTtyZXR1cm4gdGhpcy5hYnMoKS5kaXZSZW1Ubyh0LG51bGwsZSksdGhpcy5zPDAmJmUuY29tcGFyZVRvKHIuWkVSTyk+MCYmdC5zdWJUbyhlLGUpLGV9",
      "LHIucHJvdG90eXBlLm1vZFBvd0ludD1mdW5jdGlvbih0LGUpe3ZhciBpO3JldHVybiB0PDI1Nnx8ZS5pc0V2ZW4oKT9pPW5ldyBndChlKTppPW5ldyB2dChl",
      "KSx0aGlzLmV4cCh0LGkpfSxyLnByb3RvdHlwZS5jbG9uZT1mdW5jdGlvbigpe3ZhciB0PXAoKTtyZXR1cm4gdGhpcy5jb3B5VG8odCksdH0sci5wcm90b3R5",
      "cGUuaW50VmFsdWU9ZnVuY3Rpb24oKXtpZih0aGlzLnM8MCl7aWYodGhpcy50PT0xKXJldHVybiB0aGlzWzBdLXRoaXMuRFY7aWYodGhpcy50PT0wKXJldHVy",
      "bi0xfWVsc2V7aWYodGhpcy50PT0xKXJldHVybiB0aGlzWzBdO2lmKHRoaXMudD09MClyZXR1cm4gMH1yZXR1cm4odGhpc1sxXSYoMTw8MzItdGhpcy5EQikt",
      "MSk8PHRoaXMuREJ8dGhpc1swXX0sci5wcm90b3R5cGUuYnl0ZVZhbHVlPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMudD09MD90aGlzLnM6dGhpc1swXTw8MjQ+",
      "PjI0fSxyLnByb3RvdHlwZS5zaG9ydFZhbHVlPWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMudD09MD90aGlzLnM6dGhpc1swXTw8MTY+PjE2fSxyLnByb3RvdHlw",
      "ZS5zaWdudW09ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy5zPDA/LTE6dGhpcy50PD0wfHx0aGlzLnQ9PTEmJnRoaXNbMF08PTA/MDoxfSxyLnByb3RvdHlwZS50",
      "b0J5dGVBcnJheT1mdW5jdGlvbigpe3ZhciB0PXRoaXMudCxlPVtdO2VbMF09dGhpcy5zO3ZhciBpPXRoaXMuREItdCp0aGlzLkRCJTgsbixzPTA7aWYodC0t",
      "ID4wKWZvcihpPHRoaXMuREImJihuPXRoaXNbdF0+PmkpIT0odGhpcy5zJnRoaXMuRE0pPj5pJiYoZVtzKytdPW58dGhpcy5zPDx0aGlzLkRCLWkpO3Q+PTA7",
      "KWk8OD8obj0odGhpc1t0XSYoMTw8aSktMSk8PDgtaSxufD10aGlzWy0tdF0+PihpKz10aGlzLkRCLTgpKToobj10aGlzW3RdPj4oaS09OCkmMjU1LGk8PTAm",
      "JihpKz10aGlzLkRCLC0tdCkpLChuJjEyOCkhPTAmJihufD0tMjU2KSxzPT0wJiYodGhpcy5zJjEyOCkhPShuJjEyOCkmJisrcywocz4wfHxuIT10aGlzLnMp",
      "JiYoZVtzKytdPW4pO3JldHVybiBlfSxyLnByb3RvdHlwZS5lcXVhbHM9ZnVuY3Rpb24odCl7cmV0dXJuIHRoaXMuY29tcGFyZVRvKHQpPT0wfSxyLnByb3Rv",
      "dHlwZS5taW49ZnVuY3Rpb24odCl7cmV0dXJuIHRoaXMuY29tcGFyZVRvKHQpPDA/dGhpczp0fSxyLnByb3RvdHlwZS5tYXg9ZnVuY3Rpb24odCl7cmV0dXJu",
      "IHRoaXMuY29tcGFyZVRvKHQpPjA/dGhpczp0fSxyLnByb3RvdHlwZS5hbmQ9ZnVuY3Rpb24odCl7dmFyIGU9cCgpO3JldHVybiB0aGlzLmJpdHdpc2VUbyh0",
      "LER0LGUpLGV9LHIucHJvdG90eXBlLm9yPWZ1bmN0aW9uKHQpe3ZhciBlPXAoKTtyZXR1cm4gdGhpcy5iaXR3aXNlVG8odCxaLGUpLGV9LHIucHJvdG90eXBl",
      "Lnhvcj1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHRoaXMuYml0d2lzZVRvKHQsYXQsZSksZX0sci5wcm90b3R5cGUuYW5kTm90PWZ1bmN0aW9uKHQp",
      "e3ZhciBlPXAoKTtyZXR1cm4gdGhpcy5iaXR3aXNlVG8odCx1dCxlKSxlfSxyLnByb3RvdHlwZS5ub3Q9ZnVuY3Rpb24oKXtmb3IodmFyIHQ9cCgpLGU9MDtl",
      "PHRoaXMudDsrK2UpdFtlXT10aGlzLkRNJn50aGlzW2VdO3JldHVybiB0LnQ9dGhpcy50LHQucz1+dGhpcy5zLHR9LHIucHJvdG90eXBlLnNoaWZ0TGVmdD1m",
      "dW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHQ8MD90aGlzLnJTaGlmdFRvKC10LGUpOnRoaXMubFNoaWZ0VG8odCxlKSxlfSxyLnByb3RvdHlwZS5zaGlm",
      "dFJpZ2h0PWZ1bmN0aW9uKHQpe3ZhciBlPXAoKTtyZXR1cm4gdDwwP3RoaXMubFNoaWZ0VG8oLXQsZSk6dGhpcy5yU2hpZnRUbyh0LGUpLGV9LHIucHJvdG90",
      "eXBlLmdldExvd2VzdFNldEJpdD1mdW5jdGlvbigpe2Zvcih2YXIgdD0wO3Q8dGhpcy50OysrdClpZih0aGlzW3RdIT0wKXJldHVybiB0KnRoaXMuREIreHQo",
      "dGhpc1t0XSk7cmV0dXJuIHRoaXMuczwwP3RoaXMudCp0aGlzLkRCOi0xfSxyLnByb3RvdHlwZS5iaXRDb3VudD1mdW5jdGlvbigpe2Zvcih2YXIgdD0wLGU9",
      "dGhpcy5zJnRoaXMuRE0saT0wO2k8dGhpcy50OysraSl0Kz1SdCh0aGlzW2ldXmUpO3JldHVybiB0fSxyLnByb3RvdHlwZS50ZXN0Qml0PWZ1bmN0aW9uKHQp",
      "e3ZhciBlPU1hdGguZmxvb3IodC90aGlzLkRCKTtyZXR1cm4gZT49dGhpcy50P3RoaXMucyE9MDoodGhpc1tlXSYxPDx0JXRoaXMuREIpIT0wfSxyLnByb3Rv",
      "dHlwZS5zZXRCaXQ9ZnVuY3Rpb24odCl7cmV0dXJuIHRoaXMuY2hhbmdlQml0KHQsWil9LHIucHJvdG90eXBlLmNsZWFyQml0PWZ1bmN0aW9uKHQpe3JldHVy",
      "biB0aGlzLmNoYW5nZUJpdCh0LHV0KX0sci5wcm90b3R5cGUuZmxpcEJpdD1mdW5jdGlvbih0KXtyZXR1cm4gdGhpcy5jaGFuZ2VCaXQodCxhdCl9LHIucHJv",
      "dG90eXBlLmFkZD1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHRoaXMuYWRkVG8odCxlKSxlfSxyLnByb3RvdHlwZS5zdWJ0cmFjdD1mdW5jdGlvbih0",
      "KXt2YXIgZT1wKCk7cmV0dXJuIHRoaXMuc3ViVG8odCxlKSxlfSxyLnByb3RvdHlwZS5tdWx0aXBseT1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHRo",
      "aXMubXVsdGlwbHlUbyh0LGUpLGV9LHIucHJvdG90eXBlLmRpdmlkZT1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHRoaXMuZGl2UmVtVG8odCxlLG51",
      "bGwpLGV9LHIucHJvdG90eXBlLnJlbWFpbmRlcj1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHRoaXMuZGl2UmVtVG8odCxudWxsLGUpLGV9LHIucHJv",
      "dG90eXBlLmRpdmlkZUFuZFJlbWFpbmRlcj1mdW5jdGlvbih0KXt2YXIgZT1wKCksaT1wKCk7cmV0dXJuIHRoaXMuZGl2UmVtVG8odCxlLGkpLFtlLGldfSxy",
      "LnByb3RvdHlwZS5tb2RQb3c9ZnVuY3Rpb24odCxlKXt2YXIgaT10LmJpdExlbmd0aCgpLG4scz1PKDEpLGg7aWYoaTw9MClyZXR1cm4gcztpPDE4P249MTpp",
      "PDQ4P249MzppPDE0ND9uPTQ6aTw3Njg/bj01Om49NixpPDg/aD1uZXcgZ3QoZSk6ZS5pc0V2ZW4oKT9oPW5ldyBNdChlKTpoPW5ldyB2dChlKTt2YXIgbz1b",
      "XSxmPTMsdT1uLTEsbD0oMTw8biktMTtpZihvWzFdPWguY29udmVydCh0aGlzKSxuPjEpe3ZhciBnPXAoKTtmb3IoaC5zcXJUbyhvWzFdLGcpO2Y8PWw7KW9b",
      "Zl09cCgpLGgubXVsVG8oZyxvW2YtMl0sb1tmXSksZis9Mn12YXIgZD10LnQtMSx5LFQ9ITAsYj1wKCksRTtmb3IoaT1HKHRbZF0pLTE7ZD49MDspe2Zvcihp",
      "Pj11P3k9dFtkXT4+aS11Jmw6KHk9KHRbZF0mKDE8PGkrMSktMSk8PHUtaSxkPjAmJih5fD10W2QtMV0+PnRoaXMuREIraS11KSksZj1uOyh5JjEpPT0wOyl5",
      "Pj49MSwtLWY7aWYoKGktPWYpPDAmJihpKz10aGlzLkRCLC0tZCksVClvW3ldLmNvcHlUbyhzKSxUPSExO2Vsc2V7Zm9yKDtmPjE7KWguc3FyVG8ocyxiKSxo",
      "LnNxclRvKGIscyksZi09MjtmPjA/aC5zcXJUbyhzLGIpOihFPXMscz1iLGI9RSksaC5tdWxUbyhiLG9beV0scyl9Zm9yKDtkPj0wJiYodFtkXSYxPDxpKT09",
      "MDspaC5zcXJUbyhzLGIpLEU9cyxzPWIsYj1FLC0taTwwJiYoaT10aGlzLkRCLTEsLS1kKX1yZXR1cm4gaC5yZXZlcnQocyl9LHIucHJvdG90eXBlLm1vZElu",
      "dmVyc2U9ZnVuY3Rpb24odCl7dmFyIGU9dC5pc0V2ZW4oKTtpZih0aGlzLmlzRXZlbigpJiZlfHx0LnNpZ251bSgpPT0wKXJldHVybiByLlpFUk87Zm9yKHZh",
      "ciBpPXQuY2xvbmUoKSxuPXRoaXMuY2xvbmUoKSxzPU8oMSksaD1PKDApLG89TygwKSxmPU8oMSk7aS5zaWdudW0oKSE9MDspe2Zvcig7aS5pc0V2ZW4oKTsp",
      "aS5yU2hpZnRUbygxLGkpLGU/KCghcy5pc0V2ZW4oKXx8IWguaXNFdmVuKCkpJiYocy5hZGRUbyh0aGlzLHMpLGguc3ViVG8odCxoKSkscy5yU2hpZnRUbygx",
      "LHMpKTpoLmlzRXZlbigpfHxoLnN1YlRvKHQsaCksaC5yU2hpZnRUbygxLGgpO2Zvcig7bi5pc0V2ZW4oKTspbi5yU2hpZnRUbygxLG4pLGU/KCghby5pc0V2",
      "ZW4oKXx8IWYuaXNFdmVuKCkpJiYoby5hZGRUbyh0aGlzLG8pLGYuc3ViVG8odCxmKSksby5yU2hpZnRUbygxLG8pKTpmLmlzRXZlbigpfHxmLnN1YlRvKHQs",
      "ZiksZi5yU2hpZnRUbygxLGYpO2kuY29tcGFyZVRvKG4pPj0wPyhpLnN1YlRvKG4saSksZSYmcy5zdWJUbyhvLHMpLGguc3ViVG8oZixoKSk6KG4uc3ViVG8o",
      "aSxuKSxlJiZvLnN1YlRvKHMsbyksZi5zdWJUbyhoLGYpKX1pZihuLmNvbXBhcmVUbyhyLk9ORSkhPTApcmV0dXJuIHIuWkVSTztpZihmLmNvbXBhcmVUbyh0",
      "KT49MClyZXR1cm4gZi5zdWJ0cmFjdCh0KTtpZihmLnNpZ251bSgpPDApZi5hZGRUbyh0LGYpO2Vsc2UgcmV0dXJuIGY7cmV0dXJuIGYuc2lnbnVtKCk8MD9m",
      "LmFkZCh0KTpmfSxyLnByb3RvdHlwZS5wb3c9ZnVuY3Rpb24odCl7cmV0dXJuIHRoaXMuZXhwKHQsbmV3IFB0KX0sci5wcm90b3R5cGUuZ2NkPWZ1bmN0aW9u",
      "KHQpe3ZhciBlPXRoaXMuczwwP3RoaXMubmVnYXRlKCk6dGhpcy5jbG9uZSgpLGk9dC5zPDA/dC5uZWdhdGUoKTp0LmNsb25lKCk7aWYoZS5jb21wYXJlVG8o",
      "aSk8MCl7dmFyIG49ZTtlPWksaT1ufXZhciBzPWUuZ2V0TG93ZXN0U2V0Qml0KCksaD1pLmdldExvd2VzdFNldEJpdCgpO2lmKGg8MClyZXR1cm4gZTtmb3Io",
      "czxoJiYoaD1zKSxoPjAmJihlLnJTaGlmdFRvKGgsZSksaS5yU2hpZnRUbyhoLGkpKTtlLnNpZ251bSgpPjA7KShzPWUuZ2V0TG93ZXN0U2V0Qml0KCkpPjAm",
      "JmUuclNoaWZ0VG8ocyxlKSwocz1pLmdldExvd2VzdFNldEJpdCgpKT4wJiZpLnJTaGlmdFRvKHMsaSksZS5jb21wYXJlVG8oaSk+PTA/KGUuc3ViVG8oaSxl",
      "KSxlLnJTaGlmdFRvKDEsZSkpOihpLnN1YlRvKGUsaSksaS5yU2hpZnRUbygxLGkpKTtyZXR1cm4gaD4wJiZpLmxTaGlmdFRvKGgsaSksaX0sci5wcm90b3R5",
      "cGUuaXNQcm9iYWJsZVByaW1lPWZ1bmN0aW9uKHQpe3ZhciBlLGk9dGhpcy5hYnMoKTtpZihpLnQ9PTEmJmlbMF08PXdbdy5sZW5ndGgtMV0pe2ZvcihlPTA7",
      "ZTx3Lmxlbmd0aDsrK2UpaWYoaVswXT09d1tlXSlyZXR1cm4hMDtyZXR1cm4hMX1pZihpLmlzRXZlbigpKXJldHVybiExO2ZvcihlPTE7ZTx3Lmxlbmd0aDsp",
      "e2Zvcih2YXIgbj13W2VdLHM9ZSsxO3M8dy5sZW5ndGgmJm48TnQ7KW4qPXdbcysrXTtmb3Iobj1pLm1vZEludChuKTtlPHM7KWlmKG4ld1tlKytdPT0wKXJl",
      "dHVybiExfXJldHVybiBpLm1pbGxlclJhYmluKHQpfSxyLnByb3RvdHlwZS5jb3B5VG89ZnVuY3Rpb24odCl7Zm9yKHZhciBlPXRoaXMudC0xO2U+PTA7LS1l",
      "KXRbZV09dGhpc1tlXTt0LnQ9dGhpcy50LHQucz10aGlzLnN9LHIucHJvdG90eXBlLmZyb21JbnQ9ZnVuY3Rpb24odCl7dGhpcy50PTEsdGhpcy5zPXQ8MD8t",
      "MTowLHQ+MD90aGlzWzBdPXQ6dDwtMT90aGlzWzBdPXQrdGhpcy5EVjp0aGlzLnQ9MH0sci5wcm90b3R5cGUuZnJvbVN0cmluZz1mdW5jdGlvbih0LGUpe3Zh",
      "ciBpO2lmKGU9PTE2KWk9NDtlbHNlIGlmKGU9PTgpaT0zO2Vsc2UgaWYoZT09MjU2KWk9ODtlbHNlIGlmKGU9PTIpaT0xO2Vsc2UgaWYoZT09MzIpaT01O2Vs",
      "c2UgaWYoZT09NClpPTI7ZWxzZXt0aGlzLmZyb21SYWRpeCh0LGUpO3JldHVybn10aGlzLnQ9MCx0aGlzLnM9MDtmb3IodmFyIG49dC5sZW5ndGgscz0hMSxo",
      "PTA7LS1uPj0wOyl7dmFyIG89aT09OD8rdFtuXSYyNTU6eXQodCxuKTtpZihvPDApe3QuY2hhckF0KG4pPT0iLSImJihzPSEwKTtjb250aW51ZX1zPSExLGg9",
      "PTA/dGhpc1t0aGlzLnQrK109bzpoK2k+dGhpcy5EQj8odGhpc1t0aGlzLnQtMV18PShvJigxPDx0aGlzLkRCLWgpLTEpPDxoLHRoaXNbdGhpcy50KytdPW8+",
      "PnRoaXMuREItaCk6dGhpc1t0aGlzLnQtMV18PW88PGgsaCs9aSxoPj10aGlzLkRCJiYoaC09dGhpcy5EQil9aT09OCYmKCt0WzBdJjEyOCkhPTAmJih0aGlz",
      "LnM9LTEsaD4wJiYodGhpc1t0aGlzLnQtMV18PSgxPDx0aGlzLkRCLWgpLTE8PGgpKSx0aGlzLmNsYW1wKCkscyYmci5aRVJPLnN1YlRvKHRoaXMsdGhpcyl9",
      "LHIucHJvdG90eXBlLmNsYW1wPWZ1bmN0aW9uKCl7Zm9yKHZhciB0PXRoaXMucyZ0aGlzLkRNO3RoaXMudD4wJiZ0aGlzW3RoaXMudC0xXT09dDspLS10aGlz",
      "LnR9LHIucHJvdG90eXBlLmRsU2hpZnRUbz1mdW5jdGlvbih0LGUpe3ZhciBpO2ZvcihpPXRoaXMudC0xO2k+PTA7LS1pKWVbaSt0XT10aGlzW2ldO2Zvcihp",
      "PXQtMTtpPj0wOy0taSllW2ldPTA7ZS50PXRoaXMudCt0LGUucz10aGlzLnN9LHIucHJvdG90eXBlLmRyU2hpZnRUbz1mdW5jdGlvbih0LGUpe2Zvcih2YXIg",
      "aT10O2k8dGhpcy50OysraSllW2ktdF09dGhpc1tpXTtlLnQ9TWF0aC5tYXgodGhpcy50LXQsMCksZS5zPXRoaXMuc30sci5wcm90b3R5cGUubFNoaWZ0VG89",
      "ZnVuY3Rpb24odCxlKXtmb3IodmFyIGk9dCV0aGlzLkRCLG49dGhpcy5EQi1pLHM9KDE8PG4pLTEsaD1NYXRoLmZsb29yKHQvdGhpcy5EQiksbz10aGlzLnM8",
      "PGkmdGhpcy5ETSxmPXRoaXMudC0xO2Y+PTA7LS1mKWVbZitoKzFdPXRoaXNbZl0+Pm58byxvPSh0aGlzW2ZdJnMpPDxpO2Zvcih2YXIgZj1oLTE7Zj49MDst",
      "LWYpZVtmXT0wO2VbaF09byxlLnQ9dGhpcy50K2grMSxlLnM9dGhpcy5zLGUuY2xhbXAoKX0sci5wcm90b3R5cGUuclNoaWZ0VG89ZnVuY3Rpb24odCxlKXtl",
      "LnM9dGhpcy5zO3ZhciBpPU1hdGguZmxvb3IodC90aGlzLkRCKTtpZihpPj10aGlzLnQpe2UudD0wO3JldHVybn12YXIgbj10JXRoaXMuREIscz10aGlzLkRC",
      "LW4saD0oMTw8biktMTtlWzBdPXRoaXNbaV0+Pm47Zm9yKHZhciBvPWkrMTtvPHRoaXMudDsrK28pZVtvLWktMV18PSh0aGlzW29dJmgpPDxzLGVbby1pXT10",
      "aGlzW29dPj5uO24+MCYmKGVbdGhpcy50LWktMV18PSh0aGlzLnMmaCk8PHMpLGUudD10aGlzLnQtaSxlLmNsYW1wKCl9LHIucHJvdG90eXBlLnN1YlRvPWZ1",
      "bmN0aW9uKHQsZSl7Zm9yKHZhciBpPTAsbj0wLHM9TWF0aC5taW4odC50LHRoaXMudCk7aTxzOyluKz10aGlzW2ldLXRbaV0sZVtpKytdPW4mdGhpcy5ETSxu",
      "Pj49dGhpcy5EQjtpZih0LnQ8dGhpcy50KXtmb3Iobi09dC5zO2k8dGhpcy50OyluKz10aGlzW2ldLGVbaSsrXT1uJnRoaXMuRE0sbj4+PXRoaXMuREI7bis9",
      "dGhpcy5zfWVsc2V7Zm9yKG4rPXRoaXMucztpPHQudDspbi09dFtpXSxlW2krK109biZ0aGlzLkRNLG4+Pj10aGlzLkRCO24tPXQuc31lLnM9bjwwPy0xOjAs",
      "bjwtMT9lW2krK109dGhpcy5EVituOm4+MCYmKGVbaSsrXT1uKSxlLnQ9aSxlLmNsYW1wKCl9LHIucHJvdG90eXBlLm11bHRpcGx5VG89ZnVuY3Rpb24odCxl",
      "KXt2YXIgaT10aGlzLmFicygpLG49dC5hYnMoKSxzPWkudDtmb3IoZS50PXMrbi50Oy0tcz49MDspZVtzXT0wO2ZvcihzPTA7czxuLnQ7KytzKWVbcytpLnRd",
      "PWkuYW0oMCxuW3NdLGUscywwLGkudCk7ZS5zPTAsZS5jbGFtcCgpLHRoaXMucyE9dC5zJiZyLlpFUk8uc3ViVG8oZSxlKX0sci5wcm90b3R5cGUuc3F1YXJl",
      "VG89ZnVuY3Rpb24odCl7Zm9yKHZhciBlPXRoaXMuYWJzKCksaT10LnQ9MiplLnQ7LS1pPj0wOyl0W2ldPTA7Zm9yKGk9MDtpPGUudC0xOysraSl7dmFyIG49",
      "ZS5hbShpLGVbaV0sdCwyKmksMCwxKTsodFtpK2UudF0rPWUuYW0oaSsxLDIqZVtpXSx0LDIqaSsxLG4sZS50LWktMSkpPj1lLkRWJiYodFtpK2UudF0tPWUu",
      "RFYsdFtpK2UudCsxXT0xKX10LnQ+MCYmKHRbdC50LTFdKz1lLmFtKGksZVtpXSx0LDIqaSwwLDEpKSx0LnM9MCx0LmNsYW1wKCl9LHIucHJvdG90eXBlLmRp",
      "dlJlbVRvPWZ1bmN0aW9uKHQsZSxpKXt2YXIgbj10LmFicygpO2lmKCEobi50PD0wKSl7dmFyIHM9dGhpcy5hYnMoKTtpZihzLnQ8bi50KXtlIT1udWxsJiZl",
      "LmZyb21JbnQoMCksaSE9bnVsbCYmdGhpcy5jb3B5VG8oaSk7cmV0dXJufWk9PW51bGwmJihpPXAoKSk7dmFyIGg9cCgpLG89dGhpcy5zLGY9dC5zLHU9dGhp",
      "cy5EQi1HKG5bbi50LTFdKTt1PjA/KG4ubFNoaWZ0VG8odSxoKSxzLmxTaGlmdFRvKHUsaSkpOihuLmNvcHlUbyhoKSxzLmNvcHlUbyhpKSk7dmFyIGw9aC50",
      "LGc9aFtsLTFdO2lmKGchPTApe3ZhciBkPWcqKDE8PHRoaXMuRjEpKyhsPjE/aFtsLTJdPj50aGlzLkYyOjApLHk9dGhpcy5GVi9kLFQ9KDE8PHRoaXMuRjEp",
      "L2QsYj0xPDx0aGlzLkYyLEU9aS50LE09RS1sLEI9ZT09bnVsbD9wKCk6ZTtmb3IoaC5kbFNoaWZ0VG8oTSxCKSxpLmNvbXBhcmVUbyhCKT49MCYmKGlbaS50",
      "KytdPTEsaS5zdWJUbyhCLGkpKSxyLk9ORS5kbFNoaWZ0VG8obCxCKSxCLnN1YlRvKGgsaCk7aC50PGw7KWhbaC50KytdPTA7Zm9yKDstLU0+PTA7KXt2YXIg",
      "cT1pWy0tRV09PWc/dGhpcy5ETTpNYXRoLmZsb29yKGlbRV0qeSsoaVtFLTFdK2IpKlQpO2lmKChpW0VdKz1oLmFtKDAscSxpLE0sMCxsKSk8cSlmb3IoaC5k",
      "bFNoaWZ0VG8oTSxCKSxpLnN1YlRvKEIsaSk7aVtFXTwtLXE7KWkuc3ViVG8oQixpKX1lIT1udWxsJiYoaS5kclNoaWZ0VG8obCxlKSxvIT1mJiZyLlpFUk8u",
      "c3ViVG8oZSxlKSksaS50PWwsaS5jbGFtcCgpLHU+MCYmaS5yU2hpZnRUbyh1LGkpLG88MCYmci5aRVJPLnN1YlRvKGksaSl9fX0sci5wcm90b3R5cGUuaW52",
      "RGlnaXQ9ZnVuY3Rpb24oKXtpZih0aGlzLnQ8MSlyZXR1cm4gMDt2YXIgdD10aGlzWzBdO2lmKCh0JjEpPT0wKXJldHVybiAwO3ZhciBlPXQmMztyZXR1cm4g",
      "ZT1lKigyLSh0JjE1KSplKSYxNSxlPWUqKDItKHQmMjU1KSplKSYyNTUsZT1lKigyLSgodCY2NTUzNSkqZSY2NTUzNSkpJjY1NTM1LGU9ZSooMi10KmUldGhp",
      "cy5EVikldGhpcy5EVixlPjA/dGhpcy5EVi1lOi1lfSxyLnByb3RvdHlwZS5pc0V2ZW49ZnVuY3Rpb24oKXtyZXR1cm4odGhpcy50PjA/dGhpc1swXSYxOnRo",
      "aXMucyk9PTB9LHIucHJvdG90eXBlLmV4cD1mdW5jdGlvbih0LGUpe2lmKHQ+NDI5NDk2NzI5NXx8dDwxKXJldHVybiByLk9ORTt2YXIgaT1wKCksbj1wKCks",
      "cz1lLmNvbnZlcnQodGhpcyksaD1HKHQpLTE7Zm9yKHMuY29weVRvKGkpOy0taD49MDspaWYoZS5zcXJUbyhpLG4pLCh0JjE8PGgpPjApZS5tdWxUbyhuLHMs",
      "aSk7ZWxzZXt2YXIgbz1pO2k9bixuPW99cmV0dXJuIGUucmV2ZXJ0KGkpfSxyLnByb3RvdHlwZS5jaHVua1NpemU9ZnVuY3Rpb24odCl7cmV0dXJuIE1hdGgu",
      "Zmxvb3IoTWF0aC5MTjIqdGhpcy5EQi9NYXRoLmxvZyh0KSl9LHIucHJvdG90eXBlLnRvUmFkaXg9ZnVuY3Rpb24odCl7aWYodD09bnVsbCYmKHQ9MTApLHRo",
      "aXMuc2lnbnVtKCk9PTB8fHQ8Mnx8dD4zNilyZXR1cm4iMCI7dmFyIGU9dGhpcy5jaHVua1NpemUodCksaT1NYXRoLnBvdyh0LGUpLG49TyhpKSxzPXAoKSxo",
      "PXAoKSxvPSIiO2Zvcih0aGlzLmRpdlJlbVRvKG4scyxoKTtzLnNpZ251bSgpPjA7KW89KGkraC5pbnRWYWx1ZSgpKS50b1N0cmluZyh0KS5zdWJzdHIoMSkr",
      "byxzLmRpdlJlbVRvKG4scyxoKTtyZXR1cm4gaC5pbnRWYWx1ZSgpLnRvU3RyaW5nKHQpK299LHIucHJvdG90eXBlLmZyb21SYWRpeD1mdW5jdGlvbih0LGUp",
      "e3RoaXMuZnJvbUludCgwKSxlPT1udWxsJiYoZT0xMCk7Zm9yKHZhciBpPXRoaXMuY2h1bmtTaXplKGUpLG49TWF0aC5wb3coZSxpKSxzPSExLGg9MCxvPTAs",
      "Zj0wO2Y8dC5sZW5ndGg7KytmKXt2YXIgdT15dCh0LGYpO2lmKHU8MCl7dC5jaGFyQXQoZik9PSItIiYmdGhpcy5zaWdudW0oKT09MCYmKHM9ITApO2NvbnRp",
      "bnVlfW89ZSpvK3UsKytoPj1pJiYodGhpcy5kTXVsdGlwbHkobiksdGhpcy5kQWRkT2Zmc2V0KG8sMCksaD0wLG89MCl9aD4wJiYodGhpcy5kTXVsdGlwbHko",
      "TWF0aC5wb3coZSxoKSksdGhpcy5kQWRkT2Zmc2V0KG8sMCkpLHMmJnIuWkVSTy5zdWJUbyh0aGlzLHRoaXMpfSxyLnByb3RvdHlwZS5mcm9tTnVtYmVyPWZ1",
      "bmN0aW9uKHQsZSxpKXtpZih0eXBlb2YgZT09Im51bWJlciIpaWYodDwyKXRoaXMuZnJvbUludCgxKTtlbHNlIGZvcih0aGlzLmZyb21OdW1iZXIodCxpKSx0",
      "aGlzLnRlc3RCaXQodC0xKXx8dGhpcy5iaXR3aXNlVG8oci5PTkUuc2hpZnRMZWZ0KHQtMSksWix0aGlzKSx0aGlzLmlzRXZlbigpJiZ0aGlzLmRBZGRPZmZz",
      "ZXQoMSwwKTshdGhpcy5pc1Byb2JhYmxlUHJpbWUoZSk7KXRoaXMuZEFkZE9mZnNldCgyLDApLHRoaXMuYml0TGVuZ3RoKCk+dCYmdGhpcy5zdWJUbyhyLk9O",
      "RS5zaGlmdExlZnQodC0xKSx0aGlzKTtlbHNle3ZhciBuPVtdLHM9dCY3O24ubGVuZ3RoPSh0Pj4zKSsxLGUubmV4dEJ5dGVzKG4pLHM+MD9uWzBdJj0oMTw8",
      "cyktMTpuWzBdPTAsdGhpcy5mcm9tU3RyaW5nKG4sMjU2KX19LHIucHJvdG90eXBlLmJpdHdpc2VUbz1mdW5jdGlvbih0LGUsaSl7dmFyIG4scyxoPU1hdGgu",
      "bWluKHQudCx0aGlzLnQpO2ZvcihuPTA7bjxoOysrbilpW25dPWUodGhpc1tuXSx0W25dKTtpZih0LnQ8dGhpcy50KXtmb3Iocz10LnMmdGhpcy5ETSxuPWg7",
      "bjx0aGlzLnQ7KytuKWlbbl09ZSh0aGlzW25dLHMpO2kudD10aGlzLnR9ZWxzZXtmb3Iocz10aGlzLnMmdGhpcy5ETSxuPWg7bjx0LnQ7KytuKWlbbl09ZShz",
      "LHRbbl0pO2kudD10LnR9aS5zPWUodGhpcy5zLHQucyksaS5jbGFtcCgpfSxyLnByb3RvdHlwZS5jaGFuZ2VCaXQ9ZnVuY3Rpb24odCxlKXt2YXIgaT1yLk9O",
      "RS5zaGlmdExlZnQodCk7cmV0dXJuIHRoaXMuYml0d2lzZVRvKGksZSxpKSxpfSxyLnByb3RvdHlwZS5hZGRUbz1mdW5jdGlvbih0LGUpe2Zvcih2YXIgaT0w",
      "LG49MCxzPU1hdGgubWluKHQudCx0aGlzLnQpO2k8czspbis9dGhpc1tpXSt0W2ldLGVbaSsrXT1uJnRoaXMuRE0sbj4+PXRoaXMuREI7aWYodC50PHRoaXMu",
      "dCl7Zm9yKG4rPXQucztpPHRoaXMudDspbis9dGhpc1tpXSxlW2krK109biZ0aGlzLkRNLG4+Pj10aGlzLkRCO24rPXRoaXMuc31lbHNle2ZvcihuKz10aGlz",
      "LnM7aTx0LnQ7KW4rPXRbaV0sZVtpKytdPW4mdGhpcy5ETSxuPj49dGhpcy5EQjtuKz10LnN9ZS5zPW48MD8tMTowLG4+MD9lW2krK109bjpuPC0xJiYoZVtp",
      "KytdPXRoaXMuRFYrbiksZS50PWksZS5jbGFtcCgpfSxyLnByb3RvdHlwZS5kTXVsdGlwbHk9ZnVuY3Rpb24odCl7dGhpc1t0aGlzLnRdPXRoaXMuYW0oMCx0",
      "LTEsdGhpcywwLDAsdGhpcy50KSwrK3RoaXMudCx0aGlzLmNsYW1wKCl9LHIucHJvdG90eXBlLmRBZGRPZmZzZXQ9ZnVuY3Rpb24odCxlKXtpZih0IT0wKXtm",
      "b3IoO3RoaXMudDw9ZTspdGhpc1t0aGlzLnQrK109MDtmb3IodGhpc1tlXSs9dDt0aGlzW2VdPj10aGlzLkRWOyl0aGlzW2VdLT10aGlzLkRWLCsrZT49dGhp",
      "cy50JiYodGhpc1t0aGlzLnQrK109MCksKyt0aGlzW2VdfX0sci5wcm90b3R5cGUubXVsdGlwbHlMb3dlclRvPWZ1bmN0aW9uKHQsZSxpKXt2YXIgbj1NYXRo",
      "Lm1pbih0aGlzLnQrdC50LGUpO2ZvcihpLnM9MCxpLnQ9bjtuPjA7KWlbLS1uXT0wO2Zvcih2YXIgcz1pLnQtdGhpcy50O248czsrK24paVtuK3RoaXMudF09",
      "dGhpcy5hbSgwLHRbbl0saSxuLDAsdGhpcy50KTtmb3IodmFyIHM9TWF0aC5taW4odC50LGUpO248czsrK24pdGhpcy5hbSgwLHRbbl0saSxuLDAsZS1uKTtp",
      "LmNsYW1wKCl9LHIucHJvdG90eXBlLm11bHRpcGx5VXBwZXJUbz1mdW5jdGlvbih0LGUsaSl7LS1lO3ZhciBuPWkudD10aGlzLnQrdC50LWU7Zm9yKGkucz0w",
      "Oy0tbj49MDspaVtuXT0wO2ZvcihuPU1hdGgubWF4KGUtdGhpcy50LDApO248dC50OysrbilpW3RoaXMudCtuLWVdPXRoaXMuYW0oZS1uLHRbbl0saSwwLDAs",
      "dGhpcy50K24tZSk7aS5jbGFtcCgpLGkuZHJTaGlmdFRvKDEsaSl9LHIucHJvdG90eXBlLm1vZEludD1mdW5jdGlvbih0KXtpZih0PD0wKXJldHVybiAwO3Zh",
      "ciBlPXRoaXMuRFYldCxpPXRoaXMuczwwP3QtMTowO2lmKHRoaXMudD4wKWlmKGU9PTApaT10aGlzWzBdJXQ7ZWxzZSBmb3IodmFyIG49dGhpcy50LTE7bj49",
      "MDstLW4paT0oZSppK3RoaXNbbl0pJXQ7cmV0dXJuIGl9LHIucHJvdG90eXBlLm1pbGxlclJhYmluPWZ1bmN0aW9uKHQpe3ZhciBlPXRoaXMuc3VidHJhY3Qo",
      "ci5PTkUpLGk9ZS5nZXRMb3dlc3RTZXRCaXQoKTtpZihpPD0wKXJldHVybiExO3ZhciBuPWUuc2hpZnRSaWdodChpKTt0PXQrMT4+MSx0PncubGVuZ3RoJiYo",
      "dD13Lmxlbmd0aCk7Zm9yKHZhciBzPXAoKSxoPTA7aDx0OysraCl7cy5mcm9tSW50KHdbTWF0aC5mbG9vcihNYXRoLnJhbmRvbSgpKncubGVuZ3RoKV0pO3Zh",
      "ciBvPXMubW9kUG93KG4sdGhpcyk7aWYoby5jb21wYXJlVG8oci5PTkUpIT0wJiZvLmNvbXBhcmVUbyhlKSE9MCl7Zm9yKHZhciBmPTE7ZisrPGkmJm8uY29t",
      "cGFyZVRvKGUpIT0wOylpZihvPW8ubW9kUG93SW50KDIsdGhpcyksby5jb21wYXJlVG8oci5PTkUpPT0wKXJldHVybiExO2lmKG8uY29tcGFyZVRvKGUpIT0w",
      "KXJldHVybiExfX1yZXR1cm4hMH0sci5wcm90b3R5cGUuc3F1YXJlPWZ1bmN0aW9uKCl7dmFyIHQ9cCgpO3JldHVybiB0aGlzLnNxdWFyZVRvKHQpLHR9LHIu",
      "cHJvdG90eXBlLmdjZGE9ZnVuY3Rpb24odCxlKXt2YXIgaT10aGlzLnM8MD90aGlzLm5lZ2F0ZSgpOnRoaXMuY2xvbmUoKSxuPXQuczwwP3QubmVnYXRlKCk6",
      "dC5jbG9uZSgpO2lmKGkuY29tcGFyZVRvKG4pPDApe3ZhciBzPWk7aT1uLG49c312YXIgaD1pLmdldExvd2VzdFNldEJpdCgpLG89bi5nZXRMb3dlc3RTZXRC",
      "aXQoKTtpZihvPDApe2UoaSk7cmV0dXJufWg8byYmKG89aCksbz4wJiYoaS5yU2hpZnRUbyhvLGkpLG4uclNoaWZ0VG8obyxuKSk7dmFyIGY9ZnVuY3Rpb24o",
      "KXsoaD1pLmdldExvd2VzdFNldEJpdCgpKT4wJiZpLnJTaGlmdFRvKGgsaSksKGg9bi5nZXRMb3dlc3RTZXRCaXQoKSk+MCYmbi5yU2hpZnRUbyhoLG4pLGku",
      "Y29tcGFyZVRvKG4pPj0wPyhpLnN1YlRvKG4saSksaS5yU2hpZnRUbygxLGkpKToobi5zdWJUbyhpLG4pLG4uclNoaWZ0VG8oMSxuKSksaS5zaWdudW0oKT4w",
      "P3NldFRpbWVvdXQoZiwwKToobz4wJiZuLmxTaGlmdFRvKG8sbiksc2V0VGltZW91dChmdW5jdGlvbigpe2Uobil9LDApKX07c2V0VGltZW91dChmLDEwKX0s",
      "ci5wcm90b3R5cGUuZnJvbU51bWJlckFzeW5jPWZ1bmN0aW9uKHQsZSxpLG4pe2lmKHR5cGVvZiBlPT0ibnVtYmVyIilpZih0PDIpdGhpcy5mcm9tSW50KDEp",
      "O2Vsc2V7dGhpcy5mcm9tTnVtYmVyKHQsaSksdGhpcy50ZXN0Qml0KHQtMSl8fHRoaXMuYml0d2lzZVRvKHIuT05FLnNoaWZ0TGVmdCh0LTEpLFosdGhpcyks",
      "dGhpcy5pc0V2ZW4oKSYmdGhpcy5kQWRkT2Zmc2V0KDEsMCk7dmFyIHM9dGhpcyxoPWZ1bmN0aW9uKCl7cy5kQWRkT2Zmc2V0KDIsMCkscy5iaXRMZW5ndGgo",
      "KT50JiZzLnN1YlRvKHIuT05FLnNoaWZ0TGVmdCh0LTEpLHMpLHMuaXNQcm9iYWJsZVByaW1lKGUpP3NldFRpbWVvdXQoZnVuY3Rpb24oKXtuKCl9LDApOnNl",
      "dFRpbWVvdXQoaCwwKX07c2V0VGltZW91dChoLDApfWVsc2V7dmFyIG89W10sZj10Jjc7by5sZW5ndGg9KHQ+PjMpKzEsZS5uZXh0Qnl0ZXMobyksZj4wP29b",
      "MF0mPSgxPDxmKS0xOm9bMF09MCx0aGlzLmZyb21TdHJpbmcobywyNTYpfX0scn0oKSxQdD1mdW5jdGlvbigpe2Z1bmN0aW9uIHIoKXt9cmV0dXJuIHIucHJv",
      "dG90eXBlLmNvbnZlcnQ9ZnVuY3Rpb24odCl7cmV0dXJuIHR9LHIucHJvdG90eXBlLnJldmVydD1mdW5jdGlvbih0KXtyZXR1cm4gdH0sci5wcm90b3R5cGUu",
      "bXVsVG89ZnVuY3Rpb24odCxlLGkpe3QubXVsdGlwbHlUbyhlLGkpfSxyLnByb3RvdHlwZS5zcXJUbz1mdW5jdGlvbih0LGUpe3Quc3F1YXJlVG8oZSl9LHJ9",
      "KCksZ3Q9ZnVuY3Rpb24oKXtmdW5jdGlvbiByKHQpe3RoaXMubT10fXJldHVybiByLnByb3RvdHlwZS5jb252ZXJ0PWZ1bmN0aW9uKHQpe3JldHVybiB0LnM8",
      "MHx8dC5jb21wYXJlVG8odGhpcy5tKT49MD90Lm1vZCh0aGlzLm0pOnR9LHIucHJvdG90eXBlLnJldmVydD1mdW5jdGlvbih0KXtyZXR1cm4gdH0sci5wcm90",
      "b3R5cGUucmVkdWNlPWZ1bmN0aW9uKHQpe3QuZGl2UmVtVG8odGhpcy5tLG51bGwsdCl9LHIucHJvdG90eXBlLm11bFRvPWZ1bmN0aW9uKHQsZSxpKXt0Lm11",
      "bHRpcGx5VG8oZSxpKSx0aGlzLnJlZHVjZShpKX0sci5wcm90b3R5cGUuc3FyVG89ZnVuY3Rpb24odCxlKXt0LnNxdWFyZVRvKGUpLHRoaXMucmVkdWNlKGUp",
      "fSxyfSgpLHZ0PWZ1bmN0aW9uKCl7ZnVuY3Rpb24gcih0KXt0aGlzLm09dCx0aGlzLm1wPXQuaW52RGlnaXQoKSx0aGlzLm1wbD10aGlzLm1wJjMyNzY3LHRo",
      "aXMubXBoPXRoaXMubXA+PjE1LHRoaXMudW09KDE8PHQuREItMTUpLTEsdGhpcy5tdDI9Mip0LnR9cmV0dXJuIHIucHJvdG90eXBlLmNvbnZlcnQ9ZnVuY3Rp",
      "b24odCl7dmFyIGU9cCgpO3JldHVybiB0LmFicygpLmRsU2hpZnRUbyh0aGlzLm0udCxlKSxlLmRpdlJlbVRvKHRoaXMubSxudWxsLGUpLHQuczwwJiZlLmNv",
      "bXBhcmVUbyhjLlpFUk8pPjAmJnRoaXMubS5zdWJUbyhlLGUpLGV9LHIucHJvdG90eXBlLnJldmVydD1mdW5jdGlvbih0KXt2YXIgZT1wKCk7cmV0dXJuIHQu",
      "Y29weVRvKGUpLHRoaXMucmVkdWNlKGUpLGV9LHIucHJvdG90eXBlLnJlZHVjZT1mdW5jdGlvbih0KXtmb3IoO3QudDw9dGhpcy5tdDI7KXRbdC50KytdPTA7",
      "Zm9yKHZhciBlPTA7ZTx0aGlzLm0udDsrK2Upe3ZhciBpPXRbZV0mMzI3Njcsbj1pKnRoaXMubXBsKygoaSp0aGlzLm1waCsodFtlXT4+MTUpKnRoaXMubXBs",
      "JnRoaXMudW0pPDwxNSkmdC5ETTtmb3IoaT1lK3RoaXMubS50LHRbaV0rPXRoaXMubS5hbSgwLG4sdCxlLDAsdGhpcy5tLnQpO3RbaV0+PXQuRFY7KXRbaV0t",
      "PXQuRFYsdFsrK2ldKyt9dC5jbGFtcCgpLHQuZHJTaGlmdFRvKHRoaXMubS50LHQpLHQuY29tcGFyZVRvKHRoaXMubSk+PTAmJnQuc3ViVG8odGhpcy5tLHQp",
      "fSxyLnByb3RvdHlwZS5tdWxUbz1mdW5jdGlvbih0LGUsaSl7dC5tdWx0aXBseVRvKGUsaSksdGhpcy5yZWR1Y2UoaSl9LHIucHJvdG90eXBlLnNxclRvPWZ1",
      "bmN0aW9uKHQsZSl7dC5zcXVhcmVUbyhlKSx0aGlzLnJlZHVjZShlKX0scn0oKSxNdD1mdW5jdGlvbigpe2Z1bmN0aW9uIHIodCl7dGhpcy5tPXQsdGhpcy5y",
      "Mj1wKCksdGhpcy5xMz1wKCksYy5PTkUuZGxTaGlmdFRvKDIqdC50LHRoaXMucjIpLHRoaXMubXU9dGhpcy5yMi5kaXZpZGUodCl9cmV0dXJuIHIucHJvdG90",
      "eXBlLmNvbnZlcnQ9ZnVuY3Rpb24odCl7aWYodC5zPDB8fHQudD4yKnRoaXMubS50KXJldHVybiB0Lm1vZCh0aGlzLm0pO2lmKHQuY29tcGFyZVRvKHRoaXMu",
      "bSk8MClyZXR1cm4gdDt2YXIgZT1wKCk7cmV0dXJuIHQuY29weVRvKGUpLHRoaXMucmVkdWNlKGUpLGV9LHIucHJvdG90eXBlLnJldmVydD1mdW5jdGlvbih0",
      "KXtyZXR1cm4gdH0sci5wcm90b3R5cGUucmVkdWNlPWZ1bmN0aW9uKHQpe2Zvcih0LmRyU2hpZnRUbyh0aGlzLm0udC0xLHRoaXMucjIpLHQudD50aGlzLm0u",
      "dCsxJiYodC50PXRoaXMubS50KzEsdC5jbGFtcCgpKSx0aGlzLm11Lm11bHRpcGx5VXBwZXJUbyh0aGlzLnIyLHRoaXMubS50KzEsdGhpcy5xMyksdGhpcy5t",
      "Lm11bHRpcGx5TG93ZXJUbyh0aGlzLnEzLHRoaXMubS50KzEsdGhpcy5yMik7dC5jb21wYXJlVG8odGhpcy5yMik8MDspdC5kQWRkT2Zmc2V0KDEsdGhpcy5t",
      "LnQrMSk7Zm9yKHQuc3ViVG8odGhpcy5yMix0KTt0LmNvbXBhcmVUbyh0aGlzLm0pPj0wOyl0LnN1YlRvKHRoaXMubSx0KX0sci5wcm90b3R5cGUubXVsVG89",
      "ZnVuY3Rpb24odCxlLGkpe3QubXVsdGlwbHlUbyhlLGkpLHRoaXMucmVkdWNlKGkpfSxyLnByb3RvdHlwZS5zcXJUbz1mdW5jdGlvbih0LGUpe3Quc3F1YXJl",
      "VG8oZSksdGhpcy5yZWR1Y2UoZSl9LHJ9KCk7ZnVuY3Rpb24gcCgpe3JldHVybiBuZXcgYyhudWxsKX1mdW5jdGlvbiBTKHIsdCl7cmV0dXJuIG5ldyBjKHIs",
      "dCl9dmFyIGR0PXR5cGVvZiBuYXZpZ2F0b3I8InUiO2R0JiZwdCYmbmF2aWdhdG9yLmFwcE5hbWU9PSJNaWNyb3NvZnQgSW50ZXJuZXQgRXhwbG9yZXIiPyhj",
      "LnByb3RvdHlwZS5hbT1mdW5jdGlvbih0LGUsaSxuLHMsaCl7Zm9yKHZhciBvPWUmMzI3NjcsZj1lPj4xNTstLWg+PTA7KXt2YXIgdT10aGlzW3RdJjMyNzY3",
      "LGw9dGhpc1t0KytdPj4xNSxnPWYqdStsKm87dT1vKnUrKChnJjMyNzY3KTw8MTUpK2lbbl0rKHMmMTA3Mzc0MTgyMykscz0odT4+PjMwKSsoZz4+PjE1KStm",
      "KmwrKHM+Pj4zMCksaVtuKytdPXUmMTA3Mzc0MTgyM31yZXR1cm4gc30sST0zMCk6ZHQmJnB0JiZuYXZpZ2F0b3IuYXBwTmFtZSE9Ik5ldHNjYXBlIj8oYy5w",
      "cm90b3R5cGUuYW09ZnVuY3Rpb24odCxlLGksbixzLGgpe2Zvcig7LS1oPj0wOyl7dmFyIG89ZSp0aGlzW3QrK10raVtuXStzO3M9TWF0aC5mbG9vcihvLzY3",
      "MTA4ODY0KSxpW24rK109byY2NzEwODg2M31yZXR1cm4gc30sST0yNik6KGMucHJvdG90eXBlLmFtPWZ1bmN0aW9uKHQsZSxpLG4scyxoKXtmb3IodmFyIG89",
      "ZSYxNjM4MyxmPWU+PjE0Oy0taD49MDspe3ZhciB1PXRoaXNbdF0mMTYzODMsbD10aGlzW3QrK10+PjE0LGc9Zip1K2wqbzt1PW8qdSsoKGcmMTYzODMpPDwx",
      "NCkraVtuXStzLHM9KHU+PjI4KSsoZz4+MTQpK2YqbCxpW24rK109dSYyNjg0MzU0NTV9cmV0dXJuIHN9LEk9MjgpO2MucHJvdG90eXBlLkRCPUk7Yy5wcm90",
      "b3R5cGUuRE09KDE8PEkpLTE7Yy5wcm90b3R5cGUuRFY9MTw8STt2YXIgaHQ9NTI7Yy5wcm90b3R5cGUuRlY9TWF0aC5wb3coMixodCk7Yy5wcm90b3R5cGUu",
      "RjE9aHQtSTtjLnByb3RvdHlwZS5GMj0yKkktaHQ7dmFyIHR0PVtdLEwsRDtMPTQ4O2ZvcihEPTA7RDw9OTsrK0QpdHRbTCsrXT1EO0w9OTc7Zm9yKEQ9MTA7",
      "RDwzNjsrK0QpdHRbTCsrXT1EO0w9NjU7Zm9yKEQ9MTA7RDwzNjsrK0QpdHRbTCsrXT1EO2Z1bmN0aW9uIHl0KHIsdCl7dmFyIGU9dHRbci5jaGFyQ29kZUF0",
      "KHQpXTtyZXR1cm4gZT09bnVsbD8tMTplfWZ1bmN0aW9uIE8ocil7dmFyIHQ9cCgpO3JldHVybiB0LmZyb21JbnQociksdH1mdW5jdGlvbiBHKHIpe3ZhciB0",
      "PTEsZTtyZXR1cm4oZT1yPj4+MTYpIT0wJiYocj1lLHQrPTE2KSwoZT1yPj44KSE9MCYmKHI9ZSx0Kz04KSwoZT1yPj40KSE9MCYmKHI9ZSx0Kz00KSwoZT1y",
      "Pj4yKSE9MCYmKHI9ZSx0Kz0yKSwoZT1yPj4xKSE9MCYmKHI9ZSx0Kz0xKSx0fWMuWkVSTz1PKDApO2MuT05FPU8oMSk7dmFyIHF0PWZ1bmN0aW9uKCl7ZnVu",
      "Y3Rpb24gcigpe3RoaXMuaT0wLHRoaXMuaj0wLHRoaXMuUz1bXX1yZXR1cm4gci5wcm90b3R5cGUuaW5pdD1mdW5jdGlvbih0KXt2YXIgZSxpLG47Zm9yKGU9",
      "MDtlPDI1NjsrK2UpdGhpcy5TW2VdPWU7Zm9yKGk9MCxlPTA7ZTwyNTY7KytlKWk9aSt0aGlzLlNbZV0rdFtlJXQubGVuZ3RoXSYyNTUsbj10aGlzLlNbZV0s",
      "dGhpcy5TW2VdPXRoaXMuU1tpXSx0aGlzLlNbaV09bjt0aGlzLmk9MCx0aGlzLmo9MH0sci5wcm90b3R5cGUubmV4dD1mdW5jdGlvbigpe3ZhciB0O3JldHVy",
      "biB0aGlzLmk9dGhpcy5pKzEmMjU1LHRoaXMuaj10aGlzLmordGhpcy5TW3RoaXMuaV0mMjU1LHQ9dGhpcy5TW3RoaXMuaV0sdGhpcy5TW3RoaXMuaV09dGhp",
      "cy5TW3RoaXMual0sdGhpcy5TW3RoaXMual09dCx0aGlzLlNbdCt0aGlzLlNbdGhpcy5pXSYyNTVdfSxyfSgpO2Z1bmN0aW9uIEh0KCl7cmV0dXJuIG5ldyBx",
      "dH12YXIgYnQ9MjU2LCQsVj1udWxsLFI7aWYoVj09bnVsbCl7Vj1bXSxSPTA7dmFyIEo9dm9pZCAwO2lmKHR5cGVvZiB3aW5kb3c8InUiJiZ3aW5kb3cuY3J5",
      "cHRvJiZ3aW5kb3cuY3J5cHRvLmdldFJhbmRvbVZhbHVlcyl7dmFyIHJ0PW5ldyBVaW50MzJBcnJheSgyNTYpO2Zvcih3aW5kb3cuY3J5cHRvLmdldFJhbmRv",
      "bVZhbHVlcyhydCksSj0wO0o8cnQubGVuZ3RoOysrSilWW1IrK109cnRbSl0mMjU1fXZhciBZPTAsWD1mdW5jdGlvbihyKXtpZihZPVl8fDAsWT49MjU2fHxS",
      "Pj1idCl7d2luZG93LnJlbW92ZUV2ZW50TGlzdGVuZXI/d2luZG93LnJlbW92ZUV2ZW50TGlzdGVuZXIoIm1vdXNlbW92ZSIsWCwhMSk6d2luZG93LmRldGFj",
      "aEV2ZW50JiZ3aW5kb3cuZGV0YWNoRXZlbnQoIm9ubW91c2Vtb3ZlIixYKTtyZXR1cm59dHJ5e3ZhciB0PXIueCtyLnk7VltSKytdPXQmMjU1LFkrPTF9Y2F0",
      "Y2goZSl7fX07dHlwZW9mIHdpbmRvdzwidSImJih3aW5kb3cuYWRkRXZlbnRMaXN0ZW5lcj93aW5kb3cuYWRkRXZlbnRMaXN0ZW5lcigibW91c2Vtb3ZlIixY",
      "LCExKTp3aW5kb3cuYXR0YWNoRXZlbnQmJndpbmRvdy5hdHRhY2hFdmVudCgib25tb3VzZW1vdmUiLFgpKX1mdW5jdGlvbiBfdCgpe2lmKCQ9PW51bGwpe2Zv",
      "cigkPUh0KCk7UjxidDspe3ZhciByPU1hdGguZmxvb3IoNjU1MzYqTWF0aC5yYW5kb20oKSk7VltSKytdPXImMjU1fWZvcigkLmluaXQoViksUj0wO1I8Vi5s",
      "ZW5ndGg7KytSKVZbUl09MDtSPTB9cmV0dXJuICQubmV4dCgpfXZhciBvdD1mdW5jdGlvbigpe2Z1bmN0aW9uIHIoKXt9cmV0dXJuIHIucHJvdG90eXBlLm5l",
      "eHRCeXRlcz1mdW5jdGlvbih0KXtmb3IodmFyIGU9MDtlPHQubGVuZ3RoOysrZSl0W2VdPV90KCl9LHJ9KCk7ZnVuY3Rpb24gQ3Qocix0KXtpZih0PHIubGVu",
      "Z3RoKzIyKXJldHVybiBjb25zb2xlLmVycm9yKCJNZXNzYWdlIHRvbyBsb25nIGZvciBSU0EiKSxudWxsO2Zvcih2YXIgZT10LXIubGVuZ3RoLTYsaT0iIixu",
      "PTA7bjxlO24rPTIpaSs9ImZmIjt2YXIgcz0iMDAwMSIraSsiMDAiK3I7cmV0dXJuIFMocywxNil9ZnVuY3Rpb24gRnQocix0KXtpZih0PHIubGVuZ3RoKzEx",
      "KXJldHVybiBjb25zb2xlLmVycm9yKCJNZXNzYWdlIHRvbyBsb25nIGZvciBSU0EiKSxudWxsO2Zvcih2YXIgZT1bXSxpPXIubGVuZ3RoLTE7aT49MCYmdD4w",
      "Oyl7dmFyIG49ci5jaGFyQ29kZUF0KGktLSk7bjwxMjg/ZVstLXRdPW46bj4xMjcmJm48MjA0OD8oZVstLXRdPW4mNjN8MTI4LGVbLS10XT1uPj42fDE5Mik6",
      "KGVbLS10XT1uJjYzfDEyOCxlWy0tdF09bj4+NiY2M3wxMjgsZVstLXRdPW4+PjEyfDIyNCl9ZVstLXRdPTA7Zm9yKHZhciBzPW5ldyBvdCxoPVtdO3Q+Mjsp",
      "e2ZvcihoWzBdPTA7aFswXT09MDspcy5uZXh0Qnl0ZXMoaCk7ZVstLXRdPWhbMF19cmV0dXJuIGVbLS10XT0yLGVbLS10XT0wLG5ldyBjKGUpfXZhciBMdD1m",
      "dW5jdGlvbigpe2Z1bmN0aW9uIHIoKXt0aGlzLm49bnVsbCx0aGlzLmU9MCx0aGlzLmQ9bnVsbCx0aGlzLnA9bnVsbCx0aGlzLnE9bnVsbCx0aGlzLmRtcDE9",
      "bnVsbCx0aGlzLmRtcTE9bnVsbCx0aGlzLmNvZWZmPW51bGx9cmV0dXJuIHIucHJvdG90eXBlLmRvUHVibGljPWZ1bmN0aW9uKHQpe3JldHVybiB0Lm1vZFBv",
      "d0ludCh0aGlzLmUsdGhpcy5uKX0sci5wcm90b3R5cGUuZG9Qcml2YXRlPWZ1bmN0aW9uKHQpe2lmKHRoaXMucD09bnVsbHx8dGhpcy5xPT1udWxsKXJldHVy",
      "biB0Lm1vZFBvdyh0aGlzLmQsdGhpcy5uKTtmb3IodmFyIGU9dC5tb2QodGhpcy5wKS5tb2RQb3codGhpcy5kbXAxLHRoaXMucCksaT10Lm1vZCh0aGlzLnEp",
      "Lm1vZFBvdyh0aGlzLmRtcTEsdGhpcy5xKTtlLmNvbXBhcmVUbyhpKTwwOyllPWUuYWRkKHRoaXMucCk7cmV0dXJuIGUuc3VidHJhY3QoaSkubXVsdGlwbHko",
      "dGhpcy5jb2VmZikubW9kKHRoaXMucCkubXVsdGlwbHkodGhpcy5xKS5hZGQoaSl9LHIucHJvdG90eXBlLnNldFB1YmxpYz1mdW5jdGlvbih0LGUpe3QhPW51",
      "bGwmJmUhPW51bGwmJnQubGVuZ3RoPjAmJmUubGVuZ3RoPjA/KHRoaXMubj1TKHQsMTYpLHRoaXMuZT1wYXJzZUludChlLDE2KSk6Y29uc29sZS5lcnJvcigi",
      "SW52YWxpZCBSU0EgcHVibGljIGtleSIpfSxyLnByb3RvdHlwZS5lbmNyeXB0PWZ1bmN0aW9uKHQpe3ZhciBlPXRoaXMubi5iaXRMZW5ndGgoKSs3Pj4zLGk9",
      "RnQodCxlKTtpZihpPT1udWxsKXJldHVybiBudWxsO3ZhciBuPXRoaXMuZG9QdWJsaWMoaSk7aWYobj09bnVsbClyZXR1cm4gbnVsbDtmb3IodmFyIHM9bi50",
      "b1N0cmluZygxNiksaD1zLmxlbmd0aCxvPTA7bzxlKjItaDtvKyspcz0iMCIrcztyZXR1cm4gc30sci5wcm90b3R5cGUuc2V0UHJpdmF0ZT1mdW5jdGlvbih0",
      "LGUsaSl7dCE9bnVsbCYmZSE9bnVsbCYmdC5sZW5ndGg+MCYmZS5sZW5ndGg+MD8odGhpcy5uPVModCwxNiksdGhpcy5lPXBhcnNlSW50KGUsMTYpLHRoaXMu",
      "ZD1TKGksMTYpKTpjb25zb2xlLmVycm9yKCJJbnZhbGlkIFJTQSBwcml2YXRlIGtleSIpfSxyLnByb3RvdHlwZS5zZXRQcml2YXRlRXg9ZnVuY3Rpb24odCxl",
      "LGksbixzLGgsbyxmKXt0IT1udWxsJiZlIT1udWxsJiZ0Lmxlbmd0aD4wJiZlLmxlbmd0aD4wPyh0aGlzLm49Uyh0LDE2KSx0aGlzLmU9cGFyc2VJbnQoZSwx",
      "NiksdGhpcy5kPVMoaSwxNiksdGhpcy5wPVMobiwxNiksdGhpcy5xPVMocywxNiksdGhpcy5kbXAxPVMoaCwxNiksdGhpcy5kbXExPVMobywxNiksdGhpcy5j",
      "b2VmZj1TKGYsMTYpKTpjb25zb2xlLmVycm9yKCJJbnZhbGlkIFJTQSBwcml2YXRlIGtleSIpfSxyLnByb3RvdHlwZS5nZW5lcmF0ZT1mdW5jdGlvbih0LGUp",
      "e3ZhciBpPW5ldyBvdCxuPXQ+PjE7dGhpcy5lPXBhcnNlSW50KGUsMTYpO2Zvcih2YXIgcz1uZXcgYyhlLDE2KTs7KXtmb3IoO3RoaXMucD1uZXcgYyh0LW4s",
      "MSxpKSwhKHRoaXMucC5zdWJ0cmFjdChjLk9ORSkuZ2NkKHMpLmNvbXBhcmVUbyhjLk9ORSk9PTAmJnRoaXMucC5pc1Byb2JhYmxlUHJpbWUoMTApKTspO2Zv",
      "cig7dGhpcy5xPW5ldyBjKG4sMSxpKSwhKHRoaXMucS5zdWJ0cmFjdChjLk9ORSkuZ2NkKHMpLmNvbXBhcmVUbyhjLk9ORSk9PTAmJnRoaXMucS5pc1Byb2Jh",
      "YmxlUHJpbWUoMTApKTspO2lmKHRoaXMucC5jb21wYXJlVG8odGhpcy5xKTw9MCl7dmFyIGg9dGhpcy5wO3RoaXMucD10aGlzLnEsdGhpcy5xPWh9dmFyIG89",
      "dGhpcy5wLnN1YnRyYWN0KGMuT05FKSxmPXRoaXMucS5zdWJ0cmFjdChjLk9ORSksdT1vLm11bHRpcGx5KGYpO2lmKHUuZ2NkKHMpLmNvbXBhcmVUbyhjLk9O",
      "RSk9PTApe3RoaXMubj10aGlzLnAubXVsdGlwbHkodGhpcy5xKSx0aGlzLmQ9cy5tb2RJbnZlcnNlKHUpLHRoaXMuZG1wMT10aGlzLmQubW9kKG8pLHRoaXMu",
      "ZG1xMT10aGlzLmQubW9kKGYpLHRoaXMuY29lZmY9dGhpcy5xLm1vZEludmVyc2UodGhpcy5wKTticmVha319fSxyLnByb3RvdHlwZS5kZWNyeXB0PWZ1bmN0",
      "aW9uKHQpe3ZhciBlPVModCwxNiksaT10aGlzLmRvUHJpdmF0ZShlKTtyZXR1cm4gaT09bnVsbD9udWxsOkt0KGksdGhpcy5uLmJpdExlbmd0aCgpKzc+PjMp",
      "fSxyLnByb3RvdHlwZS5nZW5lcmF0ZUFzeW5jPWZ1bmN0aW9uKHQsZSxpKXt2YXIgbj1uZXcgb3Qscz10Pj4xO3RoaXMuZT1wYXJzZUludChlLDE2KTt2YXIg",
      "aD1uZXcgYyhlLDE2KSxvPXRoaXMsZj1mdW5jdGlvbigpe3ZhciB1PWZ1bmN0aW9uKCl7aWYoby5wLmNvbXBhcmVUbyhvLnEpPD0wKXt2YXIgZD1vLnA7by5w",
      "PW8ucSxvLnE9ZH12YXIgeT1vLnAuc3VidHJhY3QoYy5PTkUpLFQ9by5xLnN1YnRyYWN0KGMuT05FKSxiPXkubXVsdGlwbHkoVCk7Yi5nY2QoaCkuY29tcGFy",
      "ZVRvKGMuT05FKT09MD8oby5uPW8ucC5tdWx0aXBseShvLnEpLG8uZD1oLm1vZEludmVyc2UoYiksby5kbXAxPW8uZC5tb2QoeSksby5kbXExPW8uZC5tb2Qo",
      "VCksby5jb2VmZj1vLnEubW9kSW52ZXJzZShvLnApLHNldFRpbWVvdXQoZnVuY3Rpb24oKXtpKCl9LDApKTpzZXRUaW1lb3V0KGYsMCl9LGw9ZnVuY3Rpb24o",
      "KXtvLnE9cCgpLG8ucS5mcm9tTnVtYmVyQXN5bmMocywxLG4sZnVuY3Rpb24oKXtvLnEuc3VidHJhY3QoYy5PTkUpLmdjZGEoaCxmdW5jdGlvbihkKXtkLmNv",
      "bXBhcmVUbyhjLk9ORSk9PTAmJm8ucS5pc1Byb2JhYmxlUHJpbWUoMTApP3NldFRpbWVvdXQodSwwKTpzZXRUaW1lb3V0KGwsMCl9KX0pfSxnPWZ1bmN0aW9u",
      "KCl7by5wPXAoKSxvLnAuZnJvbU51bWJlckFzeW5jKHQtcywxLG4sZnVuY3Rpb24oKXtvLnAuc3VidHJhY3QoYy5PTkUpLmdjZGEoaCxmdW5jdGlvbihkKXtk",
      "LmNvbXBhcmVUbyhjLk9ORSk9PTAmJm8ucC5pc1Byb2JhYmxlUHJpbWUoMTApP3NldFRpbWVvdXQobCwwKTpzZXRUaW1lb3V0KGcsMCl9KX0pfTtzZXRUaW1l",
      "b3V0KGcsMCl9O3NldFRpbWVvdXQoZiwwKX0sci5wcm90b3R5cGUuc2lnbj1mdW5jdGlvbih0LGUsaSl7dmFyIG49VXQoaSkscz1uK2UodCkudG9TdHJpbmco",
      "KSxoPUN0KHMsdGhpcy5uLmJpdExlbmd0aCgpLzQpO2lmKGg9PW51bGwpcmV0dXJuIG51bGw7dmFyIG89dGhpcy5kb1ByaXZhdGUoaCk7aWYobz09bnVsbCly",
      "ZXR1cm4gbnVsbDt2YXIgZj1vLnRvU3RyaW5nKDE2KTtyZXR1cm4oZi5sZW5ndGgmMSk9PTA/ZjoiMCIrZn0sci5wcm90b3R5cGUudmVyaWZ5PWZ1bmN0aW9u",
      "KHQsZSxpKXt2YXIgbj1TKGUsMTYpLHM9dGhpcy5kb1B1YmxpYyhuKTtpZihzPT1udWxsKXJldHVybiBudWxsO3ZhciBoPXMudG9TdHJpbmcoMTYpLnJlcGxh",
      "Y2UoL14xZiswMC8sIiIpLG89anQoaCk7cmV0dXJuIG89PWkodCkudG9TdHJpbmcoKX0scn0oKTtmdW5jdGlvbiBLdChyLHQpe2Zvcih2YXIgZT1yLnRvQnl0",
      "ZUFycmF5KCksaT0wO2k8ZS5sZW5ndGgmJmVbaV09PTA7KSsraTtpZihlLmxlbmd0aC1pIT10LTF8fGVbaV0hPTIpcmV0dXJuIG51bGw7Zm9yKCsraTtlW2ld",
      "IT0wOylpZigrK2k+PWUubGVuZ3RoKXJldHVybiBudWxsO2Zvcih2YXIgbj0iIjsrK2k8ZS5sZW5ndGg7KXt2YXIgcz1lW2ldJjI1NTtzPDEyOD9uKz1TdHJp",
      "bmcuZnJvbUNoYXJDb2RlKHMpOnM+MTkxJiZzPDIyND8obis9U3RyaW5nLmZyb21DaGFyQ29kZSgocyYzMSk8PDZ8ZVtpKzFdJjYzKSwrK2kpOihuKz1TdHJp",
      "bmcuZnJvbUNoYXJDb2RlKChzJjE1KTw8MTJ8KGVbaSsxXSY2Myk8PDZ8ZVtpKzJdJjYzKSxpKz0yKX1yZXR1cm4gbn12YXIgUT17bWQyOiIzMDIwMzAwYzA2",
      "MDgyYTg2NDg4NmY3MGQwMjAyMDUwMDA0MTAiLG1kNToiMzAyMDMwMGMwNjA4MmE4NjQ4ODZmNzBkMDIwNTA1MDAwNDEwIixzaGExOiIzMDIxMzAwOTA2MDUy",
      "YjBlMDMwMjFhMDUwMDA0MTQiLHNoYTIyNDoiMzAyZDMwMGQwNjA5NjA4NjQ4MDE2NTAzMDQwMjA0MDUwMDA0MWMiLHNoYTI1NjoiMzAzMTMwMGQwNjA5NjA4",
      "NjQ4MDE2NTAzMDQwMjAxMDUwMDA0MjAiLHNoYTM4NDoiMzA0MTMwMGQwNjA5NjA4NjQ4MDE2NTAzMDQwMjAyMDUwMDA0MzAiLHNoYTUxMjoiMzA1MTMwMGQw",
      "NjA5NjA4NjQ4MDE2NTAzMDQwMjAzMDUwMDA0NDAiLHJpcGVtZDE2MDoiMzAyMTMwMDkwNjA1MmIyNDAzMDIwMTA1MDAwNDE0In07ZnVuY3Rpb24gVXQocil7",
      "cmV0dXJuIFFbcl18fCIifWZ1bmN0aW9uIGp0KHIpe2Zvcih2YXIgdCBpbiBRKWlmKFEuaGFzT3duUHJvcGVydHkodCkpe3ZhciBlPVFbdF0saT1lLmxlbmd0",
      "aDtpZihyLnN1YnN0cigwLGkpPT1lKXJldHVybiByLnN1YnN0cihpKX1yZXR1cm4gcn0vKiEKQ29weXJpZ2h0IChjKSAyMDExLCBZYWhvbyEgSW5jLiBBbGwg",
      "cmlnaHRzIHJlc2VydmVkLgpDb2RlIGxpY2Vuc2VkIHVuZGVyIHRoZSBCU0QgTGljZW5zZToKaHR0cDovL2RldmVsb3Blci55YWhvby5jb20veXVpL2xpY2Vu",
      "c2UuaHRtbAp2ZXJzaW9uOiAyLjkuMAoqL3ZhciBtPXt9O20ubGFuZz17ZXh0ZW5kOmZ1bmN0aW9uKHIsdCxlKXtpZighdHx8IXIpdGhyb3cgbmV3IEVycm9y",
      "KCJZQUhPTy5sYW5nLmV4dGVuZCBmYWlsZWQsIHBsZWFzZSBjaGVjayB0aGF0IGFsbCBkZXBlbmRlbmNpZXMgYXJlIGluY2x1ZGVkLiIpO3ZhciBpPWZ1bmN0",
      "aW9uKCl7fTtpZihpLnByb3RvdHlwZT10LnByb3RvdHlwZSxyLnByb3RvdHlwZT1uZXcgaSxyLnByb3RvdHlwZS5jb25zdHJ1Y3Rvcj1yLHIuc3VwZXJjbGFz",
      "cz10LnByb3RvdHlwZSx0LnByb3RvdHlwZS5jb25zdHJ1Y3Rvcj09T2JqZWN0LnByb3RvdHlwZS5jb25zdHJ1Y3RvciYmKHQucHJvdG90eXBlLmNvbnN0cnVj",
      "dG9yPXQpLGUpe3ZhciBuO2ZvcihuIGluIGUpci5wcm90b3R5cGVbbl09ZVtuXTt2YXIgcz1mdW5jdGlvbigpe30saD1bInRvU3RyaW5nIiwidmFsdWVPZiJd",
      "O3RyeXsvTVNJRS8udGVzdChuYXZpZ2F0b3IudXNlckFnZW50KSYmKHM9ZnVuY3Rpb24obyxmKXtmb3Iobj0wO248aC5sZW5ndGg7bj1uKzEpe3ZhciB1PWhb",
      "bl0sbD1mW3VdO3R5cGVvZiBsPT0iZnVuY3Rpb24iJiZsIT1PYmplY3QucHJvdG90eXBlW3VdJiYob1t1XT1sKX19KX1jYXRjaChvKXt9cyhyLnByb3RvdHlw",
      "ZSxlKX19fTsvKioKICogQGZpbGVPdmVydmlldwogKiBAbmFtZSBhc24xLTEuMC5qcwogKiBAYXV0aG9yIEtlbmppIFVydXNoaW1hIGtlbmppLnVydXNoaW1h",
      "QGdtYWlsLmNvbQogKiBAdmVyc2lvbiBhc24xIDEuMC4xMyAoMjAxNy1KdW4tMDIpCiAqIEBzaW5jZSBqc3JzYXNpZ24gMi4xCiAqIEBsaWNlbnNlIDxhIGhy",
      "ZWY9Imh0dHBzOi8va2p1ci5naXRodWIuaW8vanNyc2FzaWduL2xpY2Vuc2UvIj5NSVQgTGljZW5zZTwvYT4KICovdmFyIGE9e307KHR5cGVvZiBhLmFzbjE+",
      "InUifHwhYS5hc24xKSYmKGEuYXNuMT17fSk7YS5hc24xLkFTTjFVdGlsPW5ldyBmdW5jdGlvbigpe3RoaXMuaW50ZWdlclRvQnl0ZUhleD1mdW5jdGlvbihy",
      "KXt2YXIgdD1yLnRvU3RyaW5nKDE2KTtyZXR1cm4gdC5sZW5ndGglMj09MSYmKHQ9IjAiK3QpLHR9LHRoaXMuYmlnSW50VG9NaW5Ud29zQ29tcGxlbWVudHNI",
      "ZXg9ZnVuY3Rpb24ocil7dmFyIHQ9ci50b1N0cmluZygxNik7aWYodC5zdWJzdHIoMCwxKSE9Ii0iKXQubGVuZ3RoJTI9PTE/dD0iMCIrdDp0Lm1hdGNoKC9e",
      "WzAtN10vKXx8KHQ9IjAwIit0KTtlbHNle3ZhciBlPXQuc3Vic3RyKDEpLGk9ZS5sZW5ndGg7aSUyPT0xP2krPTE6dC5tYXRjaCgvXlswLTddLyl8fChpKz0y",
      "KTtmb3IodmFyIG49IiIscz0wO3M8aTtzKyspbis9ImYiO3ZhciBoPW5ldyBjKG4sMTYpLG89aC54b3IocikuYWRkKGMuT05FKTt0PW8udG9TdHJpbmcoMTYp",
      "LnJlcGxhY2UoL14tLywiIil9cmV0dXJuIHR9LHRoaXMuZ2V0UEVNU3RyaW5nRnJvbUhleD1mdW5jdGlvbihyLHQpe3JldHVybiBoZXh0b3BlbShyLHQpfSx0",
      "aGlzLm5ld09iamVjdD1mdW5jdGlvbihyKXt2YXIgdD1hLGU9dC5hc24xLGk9ZS5ERVJCb29sZWFuLG49ZS5ERVJJbnRlZ2VyLHM9ZS5ERVJCaXRTdHJpbmcs",
      "aD1lLkRFUk9jdGV0U3RyaW5nLG89ZS5ERVJOdWxsLGY9ZS5ERVJPYmplY3RJZGVudGlmaWVyLHU9ZS5ERVJFbnVtZXJhdGVkLGw9ZS5ERVJVVEY4U3RyaW5n",
      "LGc9ZS5ERVJOdW1lcmljU3RyaW5nLGQ9ZS5ERVJQcmludGFibGVTdHJpbmcseT1lLkRFUlRlbGV0ZXhTdHJpbmcsVD1lLkRFUklBNVN0cmluZyxiPWUuREVS",
      "VVRDVGltZSxFPWUuREVSR2VuZXJhbGl6ZWRUaW1lLE09ZS5ERVJTZXF1ZW5jZSxCPWUuREVSU2V0LHE9ZS5ERVJUYWdnZWRPYmplY3Qsaz1lLkFTTjFVdGls",
      "Lm5ld09iamVjdCxmdD1PYmplY3Qua2V5cyhyKTtpZihmdC5sZW5ndGghPTEpdGhyb3cia2V5IG9mIHBhcmFtIHNoYWxsIGJlIG9ubHkgb25lLiI7dmFyIHY9",
      "ZnRbMF07aWYoIjpib29sOmludDpiaXRzdHI6b2N0c3RyOm51bGw6b2lkOmVudW06dXRmOHN0cjpudW1zdHI6cHJuc3RyOnRlbHN0cjppYTVzdHI6dXRjdGlt",
      "ZTpnZW50aW1lOnNlcTpzZXQ6dGFnOiIuaW5kZXhPZigiOiIrdisiOiIpPT0tMSl0aHJvdyJ1bmRlZmluZWQga2V5OiAiK3Y7aWYodj09ImJvb2wiKXJldHVy",
      "biBuZXcgaShyW3ZdKTtpZih2PT0iaW50IilyZXR1cm4gbmV3IG4oclt2XSk7aWYodj09ImJpdHN0ciIpcmV0dXJuIG5ldyBzKHJbdl0pO2lmKHY9PSJvY3Rz",
      "dHIiKXJldHVybiBuZXcgaChyW3ZdKTtpZih2PT0ibnVsbCIpcmV0dXJuIG5ldyBvKHJbdl0pO2lmKHY9PSJvaWQiKXJldHVybiBuZXcgZihyW3ZdKTtpZih2",
      "PT0iZW51bSIpcmV0dXJuIG5ldyB1KHJbdl0pO2lmKHY9PSJ1dGY4c3RyIilyZXR1cm4gbmV3IGwoclt2XSk7aWYodj09Im51bXN0ciIpcmV0dXJuIG5ldyBn",
      "KHJbdl0pO2lmKHY9PSJwcm5zdHIiKXJldHVybiBuZXcgZChyW3ZdKTtpZih2PT0idGVsc3RyIilyZXR1cm4gbmV3IHkoclt2XSk7aWYodj09ImlhNXN0ciIp",
      "cmV0dXJuIG5ldyBUKHJbdl0pO2lmKHY9PSJ1dGN0aW1lIilyZXR1cm4gbmV3IGIoclt2XSk7aWYodj09ImdlbnRpbWUiKXJldHVybiBuZXcgRShyW3ZdKTtp",
      "Zih2PT0ic2VxIil7Zm9yKHZhciBLPXJbdl0sVT1bXSxOPTA7TjxLLmxlbmd0aDtOKyspe3ZhciBldD1rKEtbTl0pO1UucHVzaChldCl9cmV0dXJuIG5ldyBN",
      "KHthcnJheTpVfSl9aWYodj09InNldCIpe2Zvcih2YXIgSz1yW3ZdLFU9W10sTj0wO048Sy5sZW5ndGg7TisrKXt2YXIgZXQ9ayhLW05dKTtVLnB1c2goZXQp",
      "fXJldHVybiBuZXcgQih7YXJyYXk6VX0pfWlmKHY9PSJ0YWciKXt2YXIgeD1yW3ZdO2lmKE9iamVjdC5wcm90b3R5cGUudG9TdHJpbmcuY2FsbCh4KT09PSJb",
      "b2JqZWN0IEFycmF5XSImJngubGVuZ3RoPT0zKXt2YXIgd3Q9ayh4WzJdKTtyZXR1cm4gbmV3IHEoe3RhZzp4WzBdLGV4cGxpY2l0OnhbMV0sb2JqOnd0fSl9",
      "ZWxzZXt2YXIgej17fTtpZih4LmV4cGxpY2l0IT09dm9pZCAwJiYoei5leHBsaWNpdD14LmV4cGxpY2l0KSx4LnRhZyE9PXZvaWQgMCYmKHoudGFnPXgudGFn",
      "KSx4Lm9iaj09PXZvaWQgMCl0aHJvdyJvYmogc2hhbGwgYmUgc3BlY2lmaWVkIGZvciAndGFnJy4iO3JldHVybiB6Lm9iaj1rKHgub2JqKSxuZXcgcSh6KX19",
      "fSx0aGlzLmpzb25Ub0FTTjFIRVg9ZnVuY3Rpb24ocil7dmFyIHQ9dGhpcy5uZXdPYmplY3Qocik7cmV0dXJuIHQuZ2V0RW5jb2RlZEhleCgpfX07YS5hc24x",
      "LkFTTjFVdGlsLm9pZEhleFRvSW50PWZ1bmN0aW9uKHIpe2Zvcih2YXIgbj0iIix0PXBhcnNlSW50KHIuc3Vic3RyKDAsMiksMTYpLGU9TWF0aC5mbG9vcih0",
      "LzQwKSxpPXQlNDAsbj1lKyIuIitpLHM9IiIsaD0yO2g8ci5sZW5ndGg7aCs9Mil7dmFyIG89cGFyc2VJbnQoci5zdWJzdHIoaCwyKSwxNiksZj0oIjAwMDAw",
      "MDAwIitvLnRvU3RyaW5nKDIpKS5zbGljZSgtOCk7aWYocz1zK2Yuc3Vic3RyKDEsNyksZi5zdWJzdHIoMCwxKT09IjAiKXt2YXIgdT1uZXcgYyhzLDIpO249",
      "bisiLiIrdS50b1N0cmluZygxMCkscz0iIn19cmV0dXJuIG59O2EuYXNuMS5BU04xVXRpbC5vaWRJbnRUb0hleD1mdW5jdGlvbihyKXt2YXIgdD1mdW5jdGlv",
      "bihvKXt2YXIgZj1vLnRvU3RyaW5nKDE2KTtyZXR1cm4gZi5sZW5ndGg9PTEmJihmPSIwIitmKSxmfSxlPWZ1bmN0aW9uKG8pe3ZhciBmPSIiLHU9bmV3IGMo",
      "bywxMCksbD11LnRvU3RyaW5nKDIpLGc9Ny1sLmxlbmd0aCU3O2c9PTcmJihnPTApO2Zvcih2YXIgZD0iIix5PTA7eTxnO3krKylkKz0iMCI7bD1kK2w7Zm9y",
      "KHZhciB5PTA7eTxsLmxlbmd0aC0xO3krPTcpe3ZhciBUPWwuc3Vic3RyKHksNyk7eSE9bC5sZW5ndGgtNyYmKFQ9IjEiK1QpLGYrPXQocGFyc2VJbnQoVCwy",
      "KSl9cmV0dXJuIGZ9O2lmKCFyLm1hdGNoKC9eWzAtOS5dKyQvKSl0aHJvdyJtYWxmb3JtZWQgb2lkIHN0cmluZzogIityO3ZhciBpPSIiLG49ci5zcGxpdCgi",
      "LiIpLHM9cGFyc2VJbnQoblswXSkqNDArcGFyc2VJbnQoblsxXSk7aSs9dChzKSxuLnNwbGljZSgwLDIpO2Zvcih2YXIgaD0wO2g8bi5sZW5ndGg7aCsrKWkr",
      "PWUobltoXSk7cmV0dXJuIGl9O2EuYXNuMS5BU04xT2JqZWN0PWZ1bmN0aW9uKCl7dmFyIHI9IiI7dGhpcy5nZXRMZW5ndGhIZXhGcm9tVmFsdWU9ZnVuY3Rp",
      "b24oKXtpZih0eXBlb2YgdGhpcy5oVj4idSJ8fHRoaXMuaFY9PW51bGwpdGhyb3cidGhpcy5oViBpcyBudWxsIG9yIHVuZGVmaW5lZC4iO2lmKHRoaXMuaFYu",
      "bGVuZ3RoJTI9PTEpdGhyb3cidmFsdWUgaGV4IG11c3QgYmUgZXZlbiBsZW5ndGg6IG49IityLmxlbmd0aCsiLHY9Iit0aGlzLmhWO3ZhciB0PXRoaXMuaFYu",
      "bGVuZ3RoLzIsZT10LnRvU3RyaW5nKDE2KTtpZihlLmxlbmd0aCUyPT0xJiYoZT0iMCIrZSksdDwxMjgpcmV0dXJuIGU7dmFyIGk9ZS5sZW5ndGgvMjtpZihp",
      "PjE1KXRocm93IkFTTi4xIGxlbmd0aCB0b28gbG9uZyB0byByZXByZXNlbnQgYnkgOHg6IG4gPSAiK3QudG9TdHJpbmcoMTYpO3ZhciBuPTEyOCtpO3JldHVy",
      "biBuLnRvU3RyaW5nKDE2KStlfSx0aGlzLmdldEVuY29kZWRIZXg9ZnVuY3Rpb24oKXtyZXR1cm4odGhpcy5oVExWPT1udWxsfHx0aGlzLmlzTW9kaWZpZWQp",
      "JiYodGhpcy5oVj10aGlzLmdldEZyZXNoVmFsdWVIZXgoKSx0aGlzLmhMPXRoaXMuZ2V0TGVuZ3RoSGV4RnJvbVZhbHVlKCksdGhpcy5oVExWPXRoaXMuaFQr",
      "dGhpcy5oTCt0aGlzLmhWLHRoaXMuaXNNb2RpZmllZD0hMSksdGhpcy5oVExWfSx0aGlzLmdldFZhbHVlSGV4PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuZ2V0",
      "RW5jb2RlZEhleCgpLHRoaXMuaFZ9LHRoaXMuZ2V0RnJlc2hWYWx1ZUhleD1mdW5jdGlvbigpe3JldHVybiIifX07YS5hc24xLkRFUkFic3RyYWN0U3RyaW5n",
      "PWZ1bmN0aW9uKHIpe2EuYXNuMS5ERVJBYnN0cmFjdFN0cmluZy5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyksdGhpcy5nZXRTdHJpbmc9ZnVu",
      "Y3Rpb24oKXtyZXR1cm4gdGhpcy5zfSx0aGlzLnNldFN0cmluZz1mdW5jdGlvbih0KXt0aGlzLmhUTFY9bnVsbCx0aGlzLmlzTW9kaWZpZWQ9ITAsdGhpcy5z",
      "PXQsdGhpcy5oVj1zdG9oZXgodGhpcy5zKX0sdGhpcy5zZXRTdHJpbmdIZXg9ZnVuY3Rpb24odCl7dGhpcy5oVExWPW51bGwsdGhpcy5pc01vZGlmaWVkPSEw",
      "LHRoaXMucz1udWxsLHRoaXMuaFY9dH0sdGhpcy5nZXRGcmVzaFZhbHVlSGV4PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuaFZ9LHR5cGVvZiByPCJ1IiYmKHR5",
      "cGVvZiByPT0ic3RyaW5nIj90aGlzLnNldFN0cmluZyhyKTp0eXBlb2Ygci5zdHI8InUiP3RoaXMuc2V0U3RyaW5nKHIuc3RyKTp0eXBlb2Ygci5oZXg8InUi",
      "JiZ0aGlzLnNldFN0cmluZ0hleChyLmhleCkpfTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJBYnN0cmFjdFN0cmluZyxhLmFzbjEuQVNOMU9iamVjdCk7YS5h",
      "c24xLkRFUkFic3RyYWN0VGltZT1mdW5jdGlvbihyKXthLmFzbjEuREVSQWJzdHJhY3RUaW1lLnN1cGVyY2xhc3MuY29uc3RydWN0b3IuY2FsbCh0aGlzKSx0",
      "aGlzLmxvY2FsRGF0ZVRvVVRDPWZ1bmN0aW9uKHQpe3V0Yz10LmdldFRpbWUoKSt0LmdldFRpbWV6b25lT2Zmc2V0KCkqNmU0O3ZhciBlPW5ldyBEYXRlKHV0",
      "Yyk7cmV0dXJuIGV9LHRoaXMuZm9ybWF0RGF0ZT1mdW5jdGlvbih0LGUsaSl7dmFyIG49dGhpcy56ZXJvUGFkZGluZyxzPXRoaXMubG9jYWxEYXRlVG9VVEMo",
      "dCksaD1TdHJpbmcocy5nZXRGdWxsWWVhcigpKTtlPT0idXRjIiYmKGg9aC5zdWJzdHIoMiwyKSk7dmFyIG89bihTdHJpbmcocy5nZXRNb250aCgpKzEpLDIp",
      "LGY9bihTdHJpbmcocy5nZXREYXRlKCkpLDIpLHU9bihTdHJpbmcocy5nZXRIb3VycygpKSwyKSxsPW4oU3RyaW5nKHMuZ2V0TWludXRlcygpKSwyKSxnPW4o",
      "U3RyaW5nKHMuZ2V0U2Vjb25kcygpKSwyKSxkPWgrbytmK3UrbCtnO2lmKGk9PT0hMCl7dmFyIHk9cy5nZXRNaWxsaXNlY29uZHMoKTtpZih5IT0wKXt2YXIg",
      "VD1uKFN0cmluZyh5KSwzKTtUPVQucmVwbGFjZSgvWzBdKyQvLCIiKSxkPWQrIi4iK1R9fXJldHVybiBkKyJaIn0sdGhpcy56ZXJvUGFkZGluZz1mdW5jdGlv",
      "bih0LGUpe3JldHVybiB0Lmxlbmd0aD49ZT90Om5ldyBBcnJheShlLXQubGVuZ3RoKzEpLmpvaW4oIjAiKSt0fSx0aGlzLmdldFN0cmluZz1mdW5jdGlvbigp",
      "e3JldHVybiB0aGlzLnN9LHRoaXMuc2V0U3RyaW5nPWZ1bmN0aW9uKHQpe3RoaXMuaFRMVj1udWxsLHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLnM9dCx0aGlz",
      "LmhWPXN0b2hleCh0KX0sdGhpcy5zZXRCeURhdGVWYWx1ZT1mdW5jdGlvbih0LGUsaSxuLHMsaCl7dmFyIG89bmV3IERhdGUoRGF0ZS5VVEModCxlLTEsaSxu",
      "LHMsaCwwKSk7dGhpcy5zZXRCeURhdGUobyl9LHRoaXMuZ2V0RnJlc2hWYWx1ZUhleD1mdW5jdGlvbigpe3JldHVybiB0aGlzLmhWfX07bS5sYW5nLmV4dGVu",
      "ZChhLmFzbjEuREVSQWJzdHJhY3RUaW1lLGEuYXNuMS5BU04xT2JqZWN0KTthLmFzbjEuREVSQWJzdHJhY3RTdHJ1Y3R1cmVkPWZ1bmN0aW9uKHIpe2EuYXNu",
      "MS5ERVJBYnN0cmFjdFN0cmluZy5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyksdGhpcy5zZXRCeUFTTjFPYmplY3RBcnJheT1mdW5jdGlvbih0",
      "KXt0aGlzLmhUTFY9bnVsbCx0aGlzLmlzTW9kaWZpZWQ9ITAsdGhpcy5hc24xQXJyYXk9dH0sdGhpcy5hcHBlbmRBU04xT2JqZWN0PWZ1bmN0aW9uKHQpe3Ro",
      "aXMuaFRMVj1udWxsLHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLmFzbjFBcnJheS5wdXNoKHQpfSx0aGlzLmFzbjFBcnJheT1uZXcgQXJyYXksdHlwZW9mIHI8",
      "InUiJiZ0eXBlb2Ygci5hcnJheTwidSImJih0aGlzLmFzbjFBcnJheT1yLmFycmF5KX07bS5sYW5nLmV4dGVuZChhLmFzbjEuREVSQWJzdHJhY3RTdHJ1Y3R1",
      "cmVkLGEuYXNuMS5BU04xT2JqZWN0KTthLmFzbjEuREVSQm9vbGVhbj1mdW5jdGlvbigpe2EuYXNuMS5ERVJCb29sZWFuLnN1cGVyY2xhc3MuY29uc3RydWN0",
      "b3IuY2FsbCh0aGlzKSx0aGlzLmhUPSIwMSIsdGhpcy5oVExWPSIwMTAxZmYifTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJCb29sZWFuLGEuYXNuMS5BU04x",
      "T2JqZWN0KTthLmFzbjEuREVSSW50ZWdlcj1mdW5jdGlvbihyKXthLmFzbjEuREVSSW50ZWdlci5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyks",
      "dGhpcy5oVD0iMDIiLHRoaXMuc2V0QnlCaWdJbnRlZ2VyPWZ1bmN0aW9uKHQpe3RoaXMuaFRMVj1udWxsLHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLmhWPWEu",
      "YXNuMS5BU04xVXRpbC5iaWdJbnRUb01pblR3b3NDb21wbGVtZW50c0hleCh0KX0sdGhpcy5zZXRCeUludGVnZXI9ZnVuY3Rpb24odCl7dmFyIGU9bmV3IGMo",
      "U3RyaW5nKHQpLDEwKTt0aGlzLnNldEJ5QmlnSW50ZWdlcihlKX0sdGhpcy5zZXRWYWx1ZUhleD1mdW5jdGlvbih0KXt0aGlzLmhWPXR9LHRoaXMuZ2V0RnJl",
      "c2hWYWx1ZUhleD1mdW5jdGlvbigpe3JldHVybiB0aGlzLmhWfSx0eXBlb2YgcjwidSImJih0eXBlb2Ygci5iaWdpbnQ8InUiP3RoaXMuc2V0QnlCaWdJbnRl",
      "Z2VyKHIuYmlnaW50KTp0eXBlb2Ygci5pbnQ8InUiP3RoaXMuc2V0QnlJbnRlZ2VyKHIuaW50KTp0eXBlb2Ygcj09Im51bWJlciI/dGhpcy5zZXRCeUludGVn",
      "ZXIocik6dHlwZW9mIHIuaGV4PCJ1IiYmdGhpcy5zZXRWYWx1ZUhleChyLmhleCkpfTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJJbnRlZ2VyLGEuYXNuMS5B",
      "U04xT2JqZWN0KTthLmFzbjEuREVSQml0U3RyaW5nPWZ1bmN0aW9uKHIpe2lmKHIhPT12b2lkIDAmJnR5cGVvZiByLm9iajwidSIpe3ZhciB0PWEuYXNuMS5B",
      "U04xVXRpbC5uZXdPYmplY3Qoci5vYmopO3IuaGV4PSIwMCIrdC5nZXRFbmNvZGVkSGV4KCl9YS5hc24xLkRFUkJpdFN0cmluZy5zdXBlcmNsYXNzLmNvbnN0",
      "cnVjdG9yLmNhbGwodGhpcyksdGhpcy5oVD0iMDMiLHRoaXMuc2V0SGV4VmFsdWVJbmNsdWRpbmdVbnVzZWRCaXRzPWZ1bmN0aW9uKGUpe3RoaXMuaFRMVj1u",
      "dWxsLHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLmhWPWV9LHRoaXMuc2V0VW51c2VkQml0c0FuZEhleFZhbHVlPWZ1bmN0aW9uKGUsaSl7aWYoZTwwfHw3PGUp",
      "dGhyb3cidW51c2VkIGJpdHMgc2hhbGwgYmUgZnJvbSAwIHRvIDc6IHUgPSAiK2U7dmFyIG49IjAiK2U7dGhpcy5oVExWPW51bGwsdGhpcy5pc01vZGlmaWVk",
      "PSEwLHRoaXMuaFY9bitpfSx0aGlzLnNldEJ5QmluYXJ5U3RyaW5nPWZ1bmN0aW9uKGUpe2U9ZS5yZXBsYWNlKC8wKyQvLCIiKTt2YXIgaT04LWUubGVuZ3Ro",
      "JTg7aT09OCYmKGk9MCk7Zm9yKHZhciBuPTA7bjw9aTtuKyspZSs9IjAiO2Zvcih2YXIgcz0iIixuPTA7bjxlLmxlbmd0aC0xO24rPTgpe3ZhciBoPWUuc3Vi",
      "c3RyKG4sOCksbz1wYXJzZUludChoLDIpLnRvU3RyaW5nKDE2KTtvLmxlbmd0aD09MSYmKG89IjAiK28pLHMrPW99dGhpcy5oVExWPW51bGwsdGhpcy5pc01v",
      "ZGlmaWVkPSEwLHRoaXMuaFY9IjAiK2krc30sdGhpcy5zZXRCeUJvb2xlYW5BcnJheT1mdW5jdGlvbihlKXtmb3IodmFyIGk9IiIsbj0wO248ZS5sZW5ndGg7",
      "bisrKWVbbl09PSEwP2krPSIxIjppKz0iMCI7dGhpcy5zZXRCeUJpbmFyeVN0cmluZyhpKX0sdGhpcy5uZXdGYWxzZUFycmF5PWZ1bmN0aW9uKGUpe2Zvcih2",
      "YXIgaT1uZXcgQXJyYXkoZSksbj0wO248ZTtuKyspaVtuXT0hMTtyZXR1cm4gaX0sdGhpcy5nZXRGcmVzaFZhbHVlSGV4PWZ1bmN0aW9uKCl7cmV0dXJuIHRo",
      "aXMuaFZ9LHR5cGVvZiByPCJ1IiYmKHR5cGVvZiByPT0ic3RyaW5nIiYmci50b0xvd2VyQ2FzZSgpLm1hdGNoKC9eWzAtOWEtZl0rJC8pP3RoaXMuc2V0SGV4",
      "VmFsdWVJbmNsdWRpbmdVbnVzZWRCaXRzKHIpOnR5cGVvZiByLmhleDwidSI/dGhpcy5zZXRIZXhWYWx1ZUluY2x1ZGluZ1VudXNlZEJpdHMoci5oZXgpOnR5",
      "cGVvZiByLmJpbjwidSI/dGhpcy5zZXRCeUJpbmFyeVN0cmluZyhyLmJpbik6dHlwZW9mIHIuYXJyYXk8InUiJiZ0aGlzLnNldEJ5Qm9vbGVhbkFycmF5KHIu",
      "YXJyYXkpKX07bS5sYW5nLmV4dGVuZChhLmFzbjEuREVSQml0U3RyaW5nLGEuYXNuMS5BU04xT2JqZWN0KTthLmFzbjEuREVST2N0ZXRTdHJpbmc9ZnVuY3Rp",
      "b24ocil7aWYociE9PXZvaWQgMCYmdHlwZW9mIHIub2JqPCJ1Iil7dmFyIHQ9YS5hc24xLkFTTjFVdGlsLm5ld09iamVjdChyLm9iaik7ci5oZXg9dC5nZXRF",
      "bmNvZGVkSGV4KCl9YS5hc24xLkRFUk9jdGV0U3RyaW5nLnN1cGVyY2xhc3MuY29uc3RydWN0b3IuY2FsbCh0aGlzLHIpLHRoaXMuaFQ9IjA0In07bS5sYW5n",
      "LmV4dGVuZChhLmFzbjEuREVST2N0ZXRTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSTnVsbD1mdW5jdGlvbigpe2EuYXNuMS5E",
      "RVJOdWxsLnN1cGVyY2xhc3MuY29uc3RydWN0b3IuY2FsbCh0aGlzKSx0aGlzLmhUPSIwNSIsdGhpcy5oVExWPSIwNTAwIn07bS5sYW5nLmV4dGVuZChhLmFz",
      "bjEuREVSTnVsbCxhLmFzbjEuQVNOMU9iamVjdCk7YS5hc24xLkRFUk9iamVjdElkZW50aWZpZXI9ZnVuY3Rpb24ocil7dmFyIHQ9ZnVuY3Rpb24oaSl7dmFy",
      "IG49aS50b1N0cmluZygxNik7cmV0dXJuIG4ubGVuZ3RoPT0xJiYobj0iMCIrbiksbn0sZT1mdW5jdGlvbihpKXt2YXIgbj0iIixzPW5ldyBjKGksMTApLGg9",
      "cy50b1N0cmluZygyKSxvPTctaC5sZW5ndGglNztvPT03JiYobz0wKTtmb3IodmFyIGY9IiIsdT0wO3U8bzt1KyspZis9IjAiO2g9ZitoO2Zvcih2YXIgdT0w",
      "O3U8aC5sZW5ndGgtMTt1Kz03KXt2YXIgbD1oLnN1YnN0cih1LDcpO3UhPWgubGVuZ3RoLTcmJihsPSIxIitsKSxuKz10KHBhcnNlSW50KGwsMikpfXJldHVy",
      "biBufTthLmFzbjEuREVST2JqZWN0SWRlbnRpZmllci5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyksdGhpcy5oVD0iMDYiLHRoaXMuc2V0VmFs",
      "dWVIZXg9ZnVuY3Rpb24oaSl7dGhpcy5oVExWPW51bGwsdGhpcy5pc01vZGlmaWVkPSEwLHRoaXMucz1udWxsLHRoaXMuaFY9aX0sdGhpcy5zZXRWYWx1ZU9p",
      "ZFN0cmluZz1mdW5jdGlvbihpKXtpZighaS5tYXRjaCgvXlswLTkuXSskLykpdGhyb3cibWFsZm9ybWVkIG9pZCBzdHJpbmc6ICIraTt2YXIgbj0iIixzPWku",
      "c3BsaXQoIi4iKSxoPXBhcnNlSW50KHNbMF0pKjQwK3BhcnNlSW50KHNbMV0pO24rPXQoaCkscy5zcGxpY2UoMCwyKTtmb3IodmFyIG89MDtvPHMubGVuZ3Ro",
      "O28rKyluKz1lKHNbb10pO3RoaXMuaFRMVj1udWxsLHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLnM9bnVsbCx0aGlzLmhWPW59LHRoaXMuc2V0VmFsdWVOYW1l",
      "PWZ1bmN0aW9uKGkpe3ZhciBuPWEuYXNuMS54NTA5Lk9JRC5uYW1lMm9pZChpKTtpZihuIT09IiIpdGhpcy5zZXRWYWx1ZU9pZFN0cmluZyhuKTtlbHNlIHRo",
      "cm93IkRFUk9iamVjdElkZW50aWZpZXIgb2lkTmFtZSB1bmRlZmluZWQ6ICIraX0sdGhpcy5nZXRGcmVzaFZhbHVlSGV4PWZ1bmN0aW9uKCl7cmV0dXJuIHRo",
      "aXMuaFZ9LHIhPT12b2lkIDAmJih0eXBlb2Ygcj09InN0cmluZyI/ci5tYXRjaCgvXlswLTJdLlswLTkuXSskLyk/dGhpcy5zZXRWYWx1ZU9pZFN0cmluZyhy",
      "KTp0aGlzLnNldFZhbHVlTmFtZShyKTpyLm9pZCE9PXZvaWQgMD90aGlzLnNldFZhbHVlT2lkU3RyaW5nKHIub2lkKTpyLmhleCE9PXZvaWQgMD90aGlzLnNl",
      "dFZhbHVlSGV4KHIuaGV4KTpyLm5hbWUhPT12b2lkIDAmJnRoaXMuc2V0VmFsdWVOYW1lKHIubmFtZSkpfTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJPYmpl",
      "Y3RJZGVudGlmaWVyLGEuYXNuMS5BU04xT2JqZWN0KTthLmFzbjEuREVSRW51bWVyYXRlZD1mdW5jdGlvbihyKXthLmFzbjEuREVSRW51bWVyYXRlZC5zdXBl",
      "cmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyksdGhpcy5oVD0iMGEiLHRoaXMuc2V0QnlCaWdJbnRlZ2VyPWZ1bmN0aW9uKHQpe3RoaXMuaFRMVj1udWxs",
      "LHRoaXMuaXNNb2RpZmllZD0hMCx0aGlzLmhWPWEuYXNuMS5BU04xVXRpbC5iaWdJbnRUb01pblR3b3NDb21wbGVtZW50c0hleCh0KX0sdGhpcy5zZXRCeUlu",
      "dGVnZXI9ZnVuY3Rpb24odCl7dmFyIGU9bmV3IGMoU3RyaW5nKHQpLDEwKTt0aGlzLnNldEJ5QmlnSW50ZWdlcihlKX0sdGhpcy5zZXRWYWx1ZUhleD1mdW5j",
      "dGlvbih0KXt0aGlzLmhWPXR9LHRoaXMuZ2V0RnJlc2hWYWx1ZUhleD1mdW5jdGlvbigpe3JldHVybiB0aGlzLmhWfSx0eXBlb2YgcjwidSImJih0eXBlb2Yg",
      "ci5pbnQ8InUiP3RoaXMuc2V0QnlJbnRlZ2VyKHIuaW50KTp0eXBlb2Ygcj09Im51bWJlciI/dGhpcy5zZXRCeUludGVnZXIocik6dHlwZW9mIHIuaGV4PCJ1",
      "IiYmdGhpcy5zZXRWYWx1ZUhleChyLmhleCkpfTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJFbnVtZXJhdGVkLGEuYXNuMS5BU04xT2JqZWN0KTthLmFzbjEu",
      "REVSVVRGOFN0cmluZz1mdW5jdGlvbihyKXthLmFzbjEuREVSVVRGOFN0cmluZy5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyxyKSx0aGlzLmhU",
      "PSIwYyJ9O20ubGFuZy5leHRlbmQoYS5hc24xLkRFUlVURjhTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSTnVtZXJpY1N0cmlu",
      "Zz1mdW5jdGlvbihyKXthLmFzbjEuREVSTnVtZXJpY1N0cmluZy5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyxyKSx0aGlzLmhUPSIxMiJ9O20u",
      "bGFuZy5leHRlbmQoYS5hc24xLkRFUk51bWVyaWNTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSUHJpbnRhYmxlU3RyaW5nPWZ1",
      "bmN0aW9uKHIpe2EuYXNuMS5ERVJQcmludGFibGVTdHJpbmcuc3VwZXJjbGFzcy5jb25zdHJ1Y3Rvci5jYWxsKHRoaXMsciksdGhpcy5oVD0iMTMifTttLmxh",
      "bmcuZXh0ZW5kKGEuYXNuMS5ERVJQcmludGFibGVTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSVGVsZXRleFN0cmluZz1mdW5j",
      "dGlvbihyKXthLmFzbjEuREVSVGVsZXRleFN0cmluZy5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyxyKSx0aGlzLmhUPSIxNCJ9O20ubGFuZy5l",
      "eHRlbmQoYS5hc24xLkRFUlRlbGV0ZXhTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSSUE1U3RyaW5nPWZ1bmN0aW9uKHIpe2Eu",
      "YXNuMS5ERVJJQTVTdHJpbmcuc3VwZXJjbGFzcy5jb25zdHJ1Y3Rvci5jYWxsKHRoaXMsciksdGhpcy5oVD0iMTYifTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5E",
      "RVJJQTVTdHJpbmcsYS5hc24xLkRFUkFic3RyYWN0U3RyaW5nKTthLmFzbjEuREVSVVRDVGltZT1mdW5jdGlvbihyKXthLmFzbjEuREVSVVRDVGltZS5zdXBl",
      "cmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyxyKSx0aGlzLmhUPSIxNyIsdGhpcy5zZXRCeURhdGU9ZnVuY3Rpb24odCl7dGhpcy5oVExWPW51bGwsdGhp",
      "cy5pc01vZGlmaWVkPSEwLHRoaXMuZGF0ZT10LHRoaXMucz10aGlzLmZvcm1hdERhdGUodGhpcy5kYXRlLCJ1dGMiKSx0aGlzLmhWPXN0b2hleCh0aGlzLnMp",
      "fSx0aGlzLmdldEZyZXNoVmFsdWVIZXg9ZnVuY3Rpb24oKXtyZXR1cm4gdHlwZW9mIHRoaXMuZGF0ZT4idSImJnR5cGVvZiB0aGlzLnM+InUiJiYodGhpcy5k",
      "YXRlPW5ldyBEYXRlLHRoaXMucz10aGlzLmZvcm1hdERhdGUodGhpcy5kYXRlLCJ1dGMiKSx0aGlzLmhWPXN0b2hleCh0aGlzLnMpKSx0aGlzLmhWfSxyIT09",
      "dm9pZCAwJiYoci5zdHIhPT12b2lkIDA/dGhpcy5zZXRTdHJpbmcoci5zdHIpOnR5cGVvZiByPT0ic3RyaW5nIiYmci5tYXRjaCgvXlswLTldezEyfVokLyk/",
      "dGhpcy5zZXRTdHJpbmcocik6ci5oZXghPT12b2lkIDA/dGhpcy5zZXRTdHJpbmdIZXgoci5oZXgpOnIuZGF0ZSE9PXZvaWQgMCYmdGhpcy5zZXRCeURhdGUo",
      "ci5kYXRlKSl9O20ubGFuZy5leHRlbmQoYS5hc24xLkRFUlVUQ1RpbWUsYS5hc24xLkRFUkFic3RyYWN0VGltZSk7YS5hc24xLkRFUkdlbmVyYWxpemVkVGlt",
      "ZT1mdW5jdGlvbihyKXthLmFzbjEuREVSR2VuZXJhbGl6ZWRUaW1lLnN1cGVyY2xhc3MuY29uc3RydWN0b3IuY2FsbCh0aGlzLHIpLHRoaXMuaFQ9IjE4Iix0",
      "aGlzLndpdGhNaWxsaXM9ITEsdGhpcy5zZXRCeURhdGU9ZnVuY3Rpb24odCl7dGhpcy5oVExWPW51bGwsdGhpcy5pc01vZGlmaWVkPSEwLHRoaXMuZGF0ZT10",
      "LHRoaXMucz10aGlzLmZvcm1hdERhdGUodGhpcy5kYXRlLCJnZW4iLHRoaXMud2l0aE1pbGxpcyksdGhpcy5oVj1zdG9oZXgodGhpcy5zKX0sdGhpcy5nZXRG",
      "cmVzaFZhbHVlSGV4PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuZGF0ZT09PXZvaWQgMCYmdGhpcy5zPT09dm9pZCAwJiYodGhpcy5kYXRlPW5ldyBEYXRlLHRo",
      "aXMucz10aGlzLmZvcm1hdERhdGUodGhpcy5kYXRlLCJnZW4iLHRoaXMud2l0aE1pbGxpcyksdGhpcy5oVj1zdG9oZXgodGhpcy5zKSksdGhpcy5oVn0sciE9",
      "PXZvaWQgMCYmKHIuc3RyIT09dm9pZCAwP3RoaXMuc2V0U3RyaW5nKHIuc3RyKTp0eXBlb2Ygcj09InN0cmluZyImJnIubWF0Y2goL15bMC05XXsxNH1aJC8p",
      "P3RoaXMuc2V0U3RyaW5nKHIpOnIuaGV4IT09dm9pZCAwP3RoaXMuc2V0U3RyaW5nSGV4KHIuaGV4KTpyLmRhdGUhPT12b2lkIDAmJnRoaXMuc2V0QnlEYXRl",
      "KHIuZGF0ZSksci5taWxsaXM9PT0hMCYmKHRoaXMud2l0aE1pbGxpcz0hMCkpfTttLmxhbmcuZXh0ZW5kKGEuYXNuMS5ERVJHZW5lcmFsaXplZFRpbWUsYS5h",
      "c24xLkRFUkFic3RyYWN0VGltZSk7YS5hc24xLkRFUlNlcXVlbmNlPWZ1bmN0aW9uKHIpe2EuYXNuMS5ERVJTZXF1ZW5jZS5zdXBlcmNsYXNzLmNvbnN0cnVj",
      "dG9yLmNhbGwodGhpcyxyKSx0aGlzLmhUPSIzMCIsdGhpcy5nZXRGcmVzaFZhbHVlSGV4PWZ1bmN0aW9uKCl7Zm9yKHZhciB0PSIiLGU9MDtlPHRoaXMuYXNu",
      "MUFycmF5Lmxlbmd0aDtlKyspe3ZhciBpPXRoaXMuYXNuMUFycmF5W2VdO3QrPWkuZ2V0RW5jb2RlZEhleCgpfXJldHVybiB0aGlzLmhWPXQsdGhpcy5oVn19",
      "O20ubGFuZy5leHRlbmQoYS5hc24xLkRFUlNlcXVlbmNlLGEuYXNuMS5ERVJBYnN0cmFjdFN0cnVjdHVyZWQpO2EuYXNuMS5ERVJTZXQ9ZnVuY3Rpb24ocil7",
      "YS5hc24xLkRFUlNldC5zdXBlcmNsYXNzLmNvbnN0cnVjdG9yLmNhbGwodGhpcyxyKSx0aGlzLmhUPSIzMSIsdGhpcy5zb3J0RmxhZz0hMCx0aGlzLmdldEZy",
      "ZXNoVmFsdWVIZXg9ZnVuY3Rpb24oKXtmb3IodmFyIHQ9bmV3IEFycmF5LGU9MDtlPHRoaXMuYXNuMUFycmF5Lmxlbmd0aDtlKyspe3ZhciBpPXRoaXMuYXNu",
      "MUFycmF5W2VdO3QucHVzaChpLmdldEVuY29kZWRIZXgoKSl9cmV0dXJuIHRoaXMuc29ydEZsYWc9PSEwJiZ0LnNvcnQoKSx0aGlzLmhWPXQuam9pbigiIiks",
      "dGhpcy5oVn0sdHlwZW9mIHI8InUiJiZ0eXBlb2Ygci5zb3J0ZmxhZzwidSImJnIuc29ydGZsYWc9PSExJiYodGhpcy5zb3J0RmxhZz0hMSl9O20ubGFuZy5l",
      "eHRlbmQoYS5hc24xLkRFUlNldCxhLmFzbjEuREVSQWJzdHJhY3RTdHJ1Y3R1cmVkKTthLmFzbjEuREVSVGFnZ2VkT2JqZWN0PWZ1bmN0aW9uKHIpe2EuYXNu",
      "MS5ERVJUYWdnZWRPYmplY3Quc3VwZXJjbGFzcy5jb25zdHJ1Y3Rvci5jYWxsKHRoaXMpLHRoaXMuaFQ9ImEwIix0aGlzLmhWPSIiLHRoaXMuaXNFeHBsaWNp",
      "dD0hMCx0aGlzLmFzbjFPYmplY3Q9bnVsbCx0aGlzLnNldEFTTjFPYmplY3Q9ZnVuY3Rpb24odCxlLGkpe3RoaXMuaFQ9ZSx0aGlzLmlzRXhwbGljaXQ9dCx0",
      "aGlzLmFzbjFPYmplY3Q9aSx0aGlzLmlzRXhwbGljaXQ/KHRoaXMuaFY9dGhpcy5hc24xT2JqZWN0LmdldEVuY29kZWRIZXgoKSx0aGlzLmhUTFY9bnVsbCx0",
      "aGlzLmlzTW9kaWZpZWQ9ITApOih0aGlzLmhWPW51bGwsdGhpcy5oVExWPWkuZ2V0RW5jb2RlZEhleCgpLHRoaXMuaFRMVj10aGlzLmhUTFYucmVwbGFjZSgv",
      "Xi4uLyxlKSx0aGlzLmlzTW9kaWZpZWQ9ITEpfSx0aGlzLmdldEZyZXNoVmFsdWVIZXg9ZnVuY3Rpb24oKXtyZXR1cm4gdGhpcy5oVn0sdHlwZW9mIHI8InUi",
      "JiYodHlwZW9mIHIudGFnPCJ1IiYmKHRoaXMuaFQ9ci50YWcpLHR5cGVvZiByLmV4cGxpY2l0PCJ1IiYmKHRoaXMuaXNFeHBsaWNpdD1yLmV4cGxpY2l0KSx0",
      "eXBlb2Ygci5vYmo8InUiJiYodGhpcy5hc24xT2JqZWN0PXIub2JqLHRoaXMuc2V0QVNOMU9iamVjdCh0aGlzLmlzRXhwbGljaXQsdGhpcy5oVCx0aGlzLmFz",
      "bjFPYmplY3QpKSl9O20ubGFuZy5leHRlbmQoYS5hc24xLkRFUlRhZ2dlZE9iamVjdCxhLmFzbjEuQVNOMU9iamVjdCk7dmFyIGt0PWZ1bmN0aW9uKCl7dmFy",
      "IHI9ZnVuY3Rpb24odCxlKXtyZXR1cm4gcj1PYmplY3Quc2V0UHJvdG90eXBlT2Z8fHtfX3Byb3RvX186W119aW5zdGFuY2VvZiBBcnJheSYmZnVuY3Rpb24o",
      "aSxuKXtpLl9fcHJvdG9fXz1ufXx8ZnVuY3Rpb24oaSxuKXtmb3IodmFyIHMgaW4gbilPYmplY3QucHJvdG90eXBlLmhhc093blByb3BlcnR5LmNhbGwobixz",
      "KSYmKGlbc109bltzXSl9LHIodCxlKX07cmV0dXJuIGZ1bmN0aW9uKHQsZSl7aWYodHlwZW9mIGUhPSJmdW5jdGlvbiImJmUhPT1udWxsKXRocm93IG5ldyBU",
      "eXBlRXJyb3IoIkNsYXNzIGV4dGVuZHMgdmFsdWUgIitTdHJpbmcoZSkrIiBpcyBub3QgYSBjb25zdHJ1Y3RvciBvciBudWxsIik7cih0LGUpO2Z1bmN0aW9u",
      "IGkoKXt0aGlzLmNvbnN0cnVjdG9yPXR9dC5wcm90b3R5cGU9ZT09PW51bGw/T2JqZWN0LmNyZWF0ZShlKTooaS5wcm90b3R5cGU9ZS5wcm90b3R5cGUsbmV3",
      "IGkpfX0oKSxTdD1mdW5jdGlvbihyKXtrdCh0LHIpO2Z1bmN0aW9uIHQoZSl7dmFyIGk9ci5jYWxsKHRoaXMpfHx0aGlzO3JldHVybiBlJiYodHlwZW9mIGU9",
      "PSJzdHJpbmciP2kucGFyc2VLZXkoZSk6KHQuaGFzUHJpdmF0ZUtleVByb3BlcnR5KGUpfHx0Lmhhc1B1YmxpY0tleVByb3BlcnR5KGUpKSYmaS5wYXJzZVBy",
      "b3BlcnRpZXNGcm9tKGUpKSxpfXJldHVybiB0LnByb3RvdHlwZS5wYXJzZUtleT1mdW5jdGlvbihlKXt0cnl7dmFyIGk9MCxuPTAscz0vXlxzKig/OlswLTlB",
      "LUZhLWZdWzAtOUEtRmEtZl1ccyopKyQvLGg9cy50ZXN0KGUpP0J0LmRlY29kZShlKTpzdC51bmFybW9yKGUpLG89VnQuZGVjb2RlKGgpO2lmKG8uc3ViLmxl",
      "bmd0aD09PTMmJihvPW8uc3ViWzJdLnN1YlswXSksby5zdWIubGVuZ3RoPT09OSl7aT1vLnN1YlsxXS5nZXRIZXhTdHJpbmdWYWx1ZSgpLHRoaXMubj1TKGks",
      "MTYpLG49by5zdWJbMl0uZ2V0SGV4U3RyaW5nVmFsdWUoKSx0aGlzLmU9cGFyc2VJbnQobiwxNik7dmFyIGY9by5zdWJbM10uZ2V0SGV4U3RyaW5nVmFsdWUo",
      "KTt0aGlzLmQ9UyhmLDE2KTt2YXIgdT1vLnN1Yls0XS5nZXRIZXhTdHJpbmdWYWx1ZSgpO3RoaXMucD1TKHUsMTYpO3ZhciBsPW8uc3ViWzVdLmdldEhleFN0",
      "cmluZ1ZhbHVlKCk7dGhpcy5xPVMobCwxNik7dmFyIGc9by5zdWJbNl0uZ2V0SGV4U3RyaW5nVmFsdWUoKTt0aGlzLmRtcDE9UyhnLDE2KTt2YXIgZD1vLnN1",
      "Yls3XS5nZXRIZXhTdHJpbmdWYWx1ZSgpO3RoaXMuZG1xMT1TKGQsMTYpO3ZhciB5PW8uc3ViWzhdLmdldEhleFN0cmluZ1ZhbHVlKCk7dGhpcy5jb2VmZj1T",
      "KHksMTYpfWVsc2UgaWYoby5zdWIubGVuZ3RoPT09MilpZihvLnN1YlswXS5zdWIpe3ZhciBUPW8uc3ViWzFdLGI9VC5zdWJbMF07aT1iLnN1YlswXS5nZXRI",
      "ZXhTdHJpbmdWYWx1ZSgpLHRoaXMubj1TKGksMTYpLG49Yi5zdWJbMV0uZ2V0SGV4U3RyaW5nVmFsdWUoKSx0aGlzLmU9cGFyc2VJbnQobiwxNil9ZWxzZSBp",
      "PW8uc3ViWzBdLmdldEhleFN0cmluZ1ZhbHVlKCksdGhpcy5uPVMoaSwxNiksbj1vLnN1YlsxXS5nZXRIZXhTdHJpbmdWYWx1ZSgpLHRoaXMuZT1wYXJzZUlu",
      "dChuLDE2KTtlbHNlIHJldHVybiExO3JldHVybiEwfWNhdGNoKEUpe3JldHVybiExfX0sdC5wcm90b3R5cGUuZ2V0UHJpdmF0ZUJhc2VLZXk9ZnVuY3Rpb24o",
      "KXt2YXIgZT17YXJyYXk6W25ldyBhLmFzbjEuREVSSW50ZWdlcih7aW50OjB9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0aGlzLm59KSxuZXcg",
      "YS5hc24xLkRFUkludGVnZXIoe2ludDp0aGlzLmV9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0aGlzLmR9KSxuZXcgYS5hc24xLkRFUkludGVn",
      "ZXIoe2JpZ2ludDp0aGlzLnB9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0aGlzLnF9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0",
      "aGlzLmRtcDF9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0aGlzLmRtcTF9KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2JpZ2ludDp0aGlzLmNv",
      "ZWZmfSldfSxpPW5ldyBhLmFzbjEuREVSU2VxdWVuY2UoZSk7cmV0dXJuIGkuZ2V0RW5jb2RlZEhleCgpfSx0LnByb3RvdHlwZS5nZXRQcml2YXRlQmFzZUtl",
      "eUI2ND1mdW5jdGlvbigpe3JldHVybiBXKHRoaXMuZ2V0UHJpdmF0ZUJhc2VLZXkoKSl9LHQucHJvdG90eXBlLmdldFB1YmxpY0Jhc2VLZXk9ZnVuY3Rpb24o",
      "KXt2YXIgZT1uZXcgYS5hc24xLkRFUlNlcXVlbmNlKHthcnJheTpbbmV3IGEuYXNuMS5ERVJPYmplY3RJZGVudGlmaWVyKHtvaWQ6IjEuMi44NDAuMTEzNTQ5",
      "LjEuMS4xIn0pLG5ldyBhLmFzbjEuREVSTnVsbF19KSxpPW5ldyBhLmFzbjEuREVSU2VxdWVuY2Uoe2FycmF5OltuZXcgYS5hc24xLkRFUkludGVnZXIoe2Jp",
      "Z2ludDp0aGlzLm59KSxuZXcgYS5hc24xLkRFUkludGVnZXIoe2ludDp0aGlzLmV9KV19KSxuPW5ldyBhLmFzbjEuREVSQml0U3RyaW5nKHtoZXg6IjAwIitp",
      "LmdldEVuY29kZWRIZXgoKX0pLHM9bmV3IGEuYXNuMS5ERVJTZXF1ZW5jZSh7YXJyYXk6W2Usbl19KTtyZXR1cm4gcy5nZXRFbmNvZGVkSGV4KCl9LHQucHJv",
      "dG90eXBlLmdldFB1YmxpY0Jhc2VLZXlCNjQ9ZnVuY3Rpb24oKXtyZXR1cm4gVyh0aGlzLmdldFB1YmxpY0Jhc2VLZXkoKSl9LHQud29yZHdyYXA9ZnVuY3Rp",
      "b24oZSxpKXtpZihpPWl8fDY0LCFlKXJldHVybiBlO3ZhciBuPSIoLnsxLCIraSsifSkoICt8JFxuPyl8KC57MSwiK2krIn0pIjtyZXR1cm4gZS5tYXRjaChS",
      "ZWdFeHAobiwiZyIpKS5qb2luKCJcbiIpfSx0LnByb3RvdHlwZS5nZXRQcml2YXRlS2V5PWZ1bmN0aW9uKCl7dmFyIGU9Ii0tLS0tQkVHSU4gUlNBIFBSSVZB",
      "VEUgS0VZLS0tLS1cbiI7cmV0dXJuIGUrPXQud29yZHdyYXAodGhpcy5nZXRQcml2YXRlQmFzZUtleUI2NCgpKSsiXG4iLGUrPSItLS0tLUVORCBSU0EgUFJJ",
      "VkFURSBLRVktLS0tLSIsZX0sdC5wcm90b3R5cGUuZ2V0UHVibGljS2V5PWZ1bmN0aW9uKCl7dmFyIGU9Ii0tLS0tQkVHSU4gUFVCTElDIEtFWS0tLS0tXG4i",
      "O3JldHVybiBlKz10LndvcmR3cmFwKHRoaXMuZ2V0UHVibGljQmFzZUtleUI2NCgpKSsiXG4iLGUrPSItLS0tLUVORCBQVUJMSUMgS0VZLS0tLS0iLGV9LHQu",
      "aGFzUHVibGljS2V5UHJvcGVydHk9ZnVuY3Rpb24oZSl7cmV0dXJuIGU9ZXx8e30sZS5oYXNPd25Qcm9wZXJ0eSgibiIpJiZlLmhhc093blByb3BlcnR5KCJl",
      "Iil9LHQuaGFzUHJpdmF0ZUtleVByb3BlcnR5PWZ1bmN0aW9uKGUpe3JldHVybiBlPWV8fHt9LGUuaGFzT3duUHJvcGVydHkoIm4iKSYmZS5oYXNPd25Qcm9w",
      "ZXJ0eSgiZSIpJiZlLmhhc093blByb3BlcnR5KCJkIikmJmUuaGFzT3duUHJvcGVydHkoInAiKSYmZS5oYXNPd25Qcm9wZXJ0eSgicSIpJiZlLmhhc093blBy",
      "b3BlcnR5KCJkbXAxIikmJmUuaGFzT3duUHJvcGVydHkoImRtcTEiKSYmZS5oYXNPd25Qcm9wZXJ0eSgiY29lZmYiKX0sdC5wcm90b3R5cGUucGFyc2VQcm9w",
      "ZXJ0aWVzRnJvbT1mdW5jdGlvbihlKXt0aGlzLm49ZS5uLHRoaXMuZT1lLmUsZS5oYXNPd25Qcm9wZXJ0eSgiZCIpJiYodGhpcy5kPWUuZCx0aGlzLnA9ZS5w",
      "LHRoaXMucT1lLnEsdGhpcy5kbXAxPWUuZG1wMSx0aGlzLmRtcTE9ZS5kbXExLHRoaXMuY29lZmY9ZS5jb2VmZil9LHR9KEx0KSx6dD17fSxudCxadD10eXBl",
      "b2YgcHJvY2VzczwidSI/KG50PXp0KT09PW51bGx8fG50PT09dm9pZCAwP3ZvaWQgMDpudC5ucG1fcGFja2FnZV92ZXJzaW9uOnZvaWQgMCxHdD1mdW5jdGlv",
      "bigpe2Z1bmN0aW9uIHIodCl7dD09PXZvaWQgMCYmKHQ9e30pLHQ9dHx8e30sdGhpcy5kZWZhdWx0X2tleV9zaXplPXQuZGVmYXVsdF9rZXlfc2l6ZT9wYXJz",
      "ZUludCh0LmRlZmF1bHRfa2V5X3NpemUsMTApOjEwMjQsdGhpcy5kZWZhdWx0X3B1YmxpY19leHBvbmVudD10LmRlZmF1bHRfcHVibGljX2V4cG9uZW50fHwi",
      "MDEwMDAxIix0aGlzLmxvZz10LmxvZ3x8ITEsdGhpcy5rZXk9bnVsbH1yZXR1cm4gci5wcm90b3R5cGUuc2V0S2V5PWZ1bmN0aW9uKHQpe3RoaXMubG9nJiZ0",
      "aGlzLmtleSYmY29uc29sZS53YXJuKCJBIGtleSB3YXMgYWxyZWFkeSBzZXQsIG92ZXJyaWRpbmcgZXhpc3RpbmcuIiksdGhpcy5rZXk9bmV3IFN0KHQpfSxy",
      "LnByb3RvdHlwZS5zZXRQcml2YXRlS2V5PWZ1bmN0aW9uKHQpe3RoaXMuc2V0S2V5KHQpfSxyLnByb3RvdHlwZS5zZXRQdWJsaWNLZXk9ZnVuY3Rpb24odCl7",
      "dGhpcy5zZXRLZXkodCl9LHIucHJvdG90eXBlLmRlY3J5cHQ9ZnVuY3Rpb24odCl7dHJ5e3JldHVybiB0aGlzLmdldEtleSgpLmRlY3J5cHQobHQodCkpfWNh",
      "dGNoKGUpe3JldHVybiExfX0sci5wcm90b3R5cGUuZW5jcnlwdD1mdW5jdGlvbih0KXt0cnl7cmV0dXJuIFcodGhpcy5nZXRLZXkoKS5lbmNyeXB0KHQpKX1j",
      "YXRjaChlKXtyZXR1cm4hMX19LHIucHJvdG90eXBlLnNpZ249ZnVuY3Rpb24odCxlLGkpe3RyeXtyZXR1cm4gVyh0aGlzLmdldEtleSgpLnNpZ24odCxlLGkp",
      "KX1jYXRjaChuKXtyZXR1cm4hMX19LHIucHJvdG90eXBlLnZlcmlmeT1mdW5jdGlvbih0LGUsaSl7dHJ5e3JldHVybiB0aGlzLmdldEtleSgpLnZlcmlmeSh0",
      "LGx0KGUpLGkpfWNhdGNoKG4pe3JldHVybiExfX0sci5wcm90b3R5cGUuZ2V0S2V5PWZ1bmN0aW9uKHQpe2lmKCF0aGlzLmtleSl7aWYodGhpcy5rZXk9bmV3",
      "IFN0LHQmJnt9LnRvU3RyaW5nLmNhbGwodCk9PT0iW29iamVjdCBGdW5jdGlvbl0iKXt0aGlzLmtleS5nZW5lcmF0ZUFzeW5jKHRoaXMuZGVmYXVsdF9rZXlf",
      "c2l6ZSx0aGlzLmRlZmF1bHRfcHVibGljX2V4cG9uZW50LHQpO3JldHVybn10aGlzLmtleS5nZW5lcmF0ZSh0aGlzLmRlZmF1bHRfa2V5X3NpemUsdGhpcy5k",
      "ZWZhdWx0X3B1YmxpY19leHBvbmVudCl9cmV0dXJuIHRoaXMua2V5fSxyLnByb3RvdHlwZS5nZXRQcml2YXRlS2V5PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMu",
      "Z2V0S2V5KCkuZ2V0UHJpdmF0ZUtleSgpfSxyLnByb3RvdHlwZS5nZXRQcml2YXRlS2V5QjY0PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuZ2V0S2V5KCkuZ2V0",
      "UHJpdmF0ZUJhc2VLZXlCNjQoKX0sci5wcm90b3R5cGUuZ2V0UHVibGljS2V5PWZ1bmN0aW9uKCl7cmV0dXJuIHRoaXMuZ2V0S2V5KCkuZ2V0UHVibGljS2V5",
      "KCl9LHIucHJvdG90eXBlLmdldFB1YmxpY0tleUI2ND1mdW5jdGlvbigpe3JldHVybiB0aGlzLmdldEtleSgpLmdldFB1YmxpY0Jhc2VLZXlCNjQoKX0sci52",
      "ZXJzaW9uPVp0LHJ9KCk7ZXhwb3J0e0d0IGFzIEp9Owo="
    ].join("");

    function printHelp() {
      console.log(`用法:
      node login-password-encrypt-standalone.mjs [options]

    选项:
      --public-key <value>        直接传公钥内容，可传 checkup 返回的 base64，或 PEM 单行内容
      --public-key-file <path>    从文件读取公钥
      --identifier <value>        账号
      --password <value>          密码
      --organ-id <value>          学校/组织 ID，可选
      --sso-stamp <value>         可选，会保留在最终提交体里
      --only-cryptogram           只输出 cryptogram
      --help                      显示帮助

    交互模式:
      不传参数时，脚本会逐项询问。
      交互输入公钥时：
      1. 可以直接粘贴 checkup 返回的 base64 公钥
      2. 如果你手里是 PEM 文件路径，输入 @/path/to/public.pem
    `);
    }

    function parseArgs(rawArgs) {
      const options = {};
      for (let i = 0; i < rawArgs.length; i += 1) {
        const arg = rawArgs[i];
        switch (arg) {
          case "--public-key":
            options.encryptionKey = rawArgs[++i];
            break;
          case "--public-key-file":
            options.publicKeyFile = rawArgs[++i];
            break;
          case "--identifier":
            options.identifier = rawArgs[++i];
            break;
          case "--password":
            options.password = rawArgs[++i];
            break;
          case "--organ-id":
            options.organId = rawArgs[++i];
            break;
          case "--sso-stamp":
            options.ssoStamp = rawArgs[++i];
            break;
          case "--only-cryptogram":
            options.onlyCryptogram = true;
            break;
          case "--help":
          case "-h":
            options.help = true;
            break;
          default:
            throw new Error(`未知参数: ${arg}`);
        }
      }
      return options;
    }

    function installBrowserLikeWindow() {
      const noop = () => {};
      if (typeof globalThis.window === "undefined") {
        globalThis.window = {};
      }
      if (!globalThis.window.crypto) {
        globalThis.window.crypto = webcrypto;
      }
      if (!globalThis.window.addEventListener) {
        globalThis.window.addEventListener = noop;
      }
      if (!globalThis.window.removeEventListener) {
        globalThis.window.removeEventListener = noop;
      }
      if (!globalThis.window.attachEvent) {
        globalThis.window.attachEvent = noop;
      }
      if (!globalThis.window.detachEvent) {
        globalThis.window.detachEvent = noop;
      }
    }

    async function loadJSEncrypt() {
      installBrowserLikeWindow();
      const moduleUrl = `data:text/javascript;base64,${EMBEDDED_VENDOR_MODULE_BASE64}`;
      const mod = await import(moduleUrl);
      return mod.J;
    }

    async function resolvePublicKey(options, rl) {
      if (options.publicKeyFile) {
        return readFile(resolve(process.cwd(), options.publicKeyFile), "utf8");
      }
      if (options.encryptionKey) {
        return options.encryptionKey;
      }
      if (!rl) {
        throw new Error("缺少公钥，请传 --public-key、--public-key-file，或使用交互模式");
      }
      const answer = (await rl.question(
        "公钥（可直接粘贴 base64；如果要从文件读，输入 @/path/to/public.pem）: ",
      )).trim();
      if (answer.startsWith("@")) {
        return readFile(resolve(process.cwd(), answer.slice(1)), "utf8");
      }
      return answer;
    }

    function buildRawPasswordPayload(inputData) {
      if (inputData.organId) {
        return JSON.stringify({
          organId: inputData.organId,
          identifier: inputData.identifier,
          password: inputData.password,
        });
      }
      return JSON.stringify({
        identifier: inputData.identifier,
        password: inputData.password,
      });
    }

    function submitByPassword(inputData, JSEncrypt) {
      inputData.mode = "Password";
      const raw = buildRawPasswordPayload(inputData);
      const rsa = new JSEncrypt();
      rsa.setPublicKey(inputData.encryptionKey);

      const submitData = JSON.parse(JSON.stringify(inputData));
      submitData.cryptogram = rsa.encrypt(raw);
      submitData.password = void 0;
      submitData.identifier = void 0;
      submitData.organId = void 0;

      if (!submitData.cryptogram) {
        throw new Error("加密失败，请检查公钥格式或明文长度是否超过 RSA 上限");
      }

      return {
        raw,
        submitData,
      };
    }

    async function askRequired(rl, value, promptText, errorText) {
      if (value) {
        return value;
      }
      if (!rl) {
        throw new Error(errorText);
      }
      return (await rl.question(promptText)).trim();
    }

    async function collectInput(cliOptions, promptOptionalFields) {
      const canPrompt = input.isTTY && output.isTTY;
      const rl = canPrompt ? createInterface({ input, output }) : null;
      try {
        const encryptionKey = (await resolvePublicKey(cliOptions, rl)).trim();
        const identifier = await askRequired(
          rl,
          cliOptions.identifier,
          "账号 identifier: ",
          "缺少账号，请传 --identifier，或使用交互模式",
        );
        const password = await askRequired(
          rl,
          cliOptions.password,
          "密码 password: ",
          "缺少密码，请传 --password，或使用交互模式",
        );
        const organId = cliOptions.organId ?? (
          promptOptionalFields && rl
            ? (await rl.question("学校/组织 ID（没有就直接回车）: ")).trim()
            : ""
        );
        const ssoStamp = cliOptions.ssoStamp ?? (
          promptOptionalFields && rl
            ? (await rl.question("ssoStamp（没有就直接回车）: ")).trim()
            : ""
        );

        return {
          encryptionKey,
          identifier,
          password,
          organId: organId || void 0,
          ssoStamp: ssoStamp || void 0,
        };
      } finally {
        if (rl) {
          rl.close();
        }
      }
    }

    async function main() {
      const cliOptions = parseArgs(argv.slice(2));
      if (cliOptions.help) {
        printHelp();
        return;
      }

      const inputData = await collectInput(cliOptions, argv.slice(2).length === 0);
      const JSEncrypt = await loadJSEncrypt();
      const result = submitByPassword(inputData, JSEncrypt);

      if (cliOptions.onlyCryptogram) {
        console.log(result.submitData.cryptogram);
        return;
      }

      console.log("raw:");
      console.log(result.raw);
      console.log("");
      console.log("cryptogram:");
      console.log(result.submitData.cryptogram);
      console.log("");
      console.log("submit payload:");
      console.log(JSON.stringify(result.submitData, null, 2));
    }

    const isDirectRun = process.argv[1] && resolve(process.argv[1]) === __filename;

    if (isDirectRun) {
      main().catch((error) => {
        console.error(error instanceof Error ? error.message : String(error));
        process.exitCode = 1;
      });
    }

    export { buildRawPasswordPayload, submitByPassword, loadJSEncrypt };
    HEREDOC
  end
end

# a = AuthSaver.new
# pp a.get_public_key_with_password_login()
