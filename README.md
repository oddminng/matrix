# README

## 准备编译软件

编译需要安装 git、gcc、autoconf 。如果编译 Lua 需要安装 readline-dev。

## 安装 Skynet

```bash
git clone https://github.com/cloudwu/skynet.git     #下载Skynet源码，本服务端使用 1.4.0 版本，如果有升级或版本变动请使用对应版本。
cd skynet                                           #进入skynet目录
make linux                                          #编译
```

## 安装 lua-cjson

```bash
cd luaclib_src                                      #进入luaclib_src目录
git clone https://github.com/mpx/lua-cjson          #下载第三方库lua-cjson的源码
cd lua-cjson                                        #进入lua-cjson的源码目录make#编译，成功后会多出名为cjson.so的文件
cp cjson.so ../../luaclib/                          #将cjson.so复制到存放C模块的luaclib目录中
```

## 安装 protobuf

```bash
apt install protobuf-c-cpmplier protobuf-compiler   #安装 protobuf
protoc --version                                    #测试是否安装成功
```

## 安装 Lua

```bash
wget https://www.lua.org/ftp/lua-5.4.3.tar.gz       #下载 Lua 5.4.3 的源码
tar zxf lua-5.4.3.tar.gz                            #解压
cd lua-5.4.3                                        #进入源码目录
make linux                                          #编译
make install                                        #安装
```

## 安装 pbc

```bash
cd luaclib_src                                      #进入项目工程luaclib_src目录
git clone https://github.com/cloudwu/pbc            #下载第三方库pbc的源码
cd pbc/binding/lua                                  #进入pbc的binding目录，它包含Skynet可用的C库源码
make                                                #编译，成功后会在同目录下生成库文件protobuf.so
cp protobuf.so ../../../../luaclib/                 #将protobuf.so复制到存放C模块的lualib目录中
cp protobuf.lua ../../../../lualib/                 #将protobuf.lua复制到存放Lua模块的lualib目录中
```

## 编译 proto 文件

```bash
protoc --descriptor_set_out login.pb login.proto
```

Good Luck~
