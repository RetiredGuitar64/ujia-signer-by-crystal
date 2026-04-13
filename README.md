# ujia-crystal

用于自动辅助Ujia平台学习的工具

## Features
- 全自动学习：每两秒自动查看一次学习状态
- 多账号学习
- 支持多种学习方式：普通学习直接秒，密码学习会根据常数`DEADLINE`的设置，决定在结束前几秒再学习
- 支持定时学习（注意，需要自己修改`DEADLINE`后重新编译）
- Web实时查看学习状态
- 账号自动认证

## Installation
#### Dependencies
> 目前仅支持Linux部署，其他平台请自行使用crystal语言环境编译
1. 确保Nodejs可用
   ```bash
   node --version
   ```
2. 确保 **Crystal** 语言环境正常，**shards** 包管理正常
3. 确保 本机/服务器 的端口`18888`打开
#### Install
1. 克隆仓库  
   ```bash
   git clone https://github.com/RetiredGuitar64/ujia-signer-by-crystal.git
   ```
2. 获取账号token
   运行命令：
   ```bash
   crystal run temp_auth.cr
   ```
   按照提示输入手机号和密码，等待token获取
     
   > 这一步只要能获取到token就可以

   token应当为48位字符，并且请确认token校验通过后再使用
3. 编译可执行文件
   ```bash
   shards build --release
   ```
   可执行文件会输出至项目目录的`bin`文件夹中
4. 将可执行文件移动至想要运行的机器，可以是公网服务器或linux本机
5. 创建账号配置文件（必须）
   在可执行文件的同目录下，创建文件 `accounts.txt`

   > 文件名不能错

   并写入账号配置，账号为一行一个，格式如下
   ```txt
   账号名称 | 刚刚获取到的token
   ```
   举例：
   ```txt
   Bob | XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
   ```
   - 支持写入多个账号，但是需要是同一个班级
6. 直接`./可执行文件`运行主程序

#### 注意
> 不使用的时候不要让程序一直跑，放假了就关掉，避免服务端监测到流量异常
> 默认会秒杀普通学习，密码学习默认会在剩下10s的时候开始学习
> 批量学习默认开启

#### Web 显示学习状态
- 默认端口`18888`，直接访问 `your_ip:18888` 即可实时查看学习状态
- 若为普通学习，会显示密码为 `200`
- 若为密码学习，会直接显示密码
  
## Contributors

- [RetiredGuitar64](https://github.com/RetiredGuitar64) - creator and maintainer
