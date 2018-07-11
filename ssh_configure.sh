#!/bin/bash

# ==========================================================================
# ======== Configure ssh login without password ============================
# ======== Created by ZhangQiang on 2018-5-24 ==============================
# ======== Usage: args [-h "host1 [host2 host3]"] [-p "password"] ==========
# ==========================================================================


# ===================================================================================================================================
# ==================== function ========================= function ================================= function =======================
# ===================================================================================================================================

# ssh-keygen
# 超时时间，单位秒，默认10s，-1代表永不超时
# 如果不使用 expect -c 则需要将脚本文件第一行改成 #!/bin/bash/expect
function ssh_key_gen(){
# <<EOF 或者 <<-EOF 之间不可以有空格，他们是一体的
# <<-EOF ，如果重定向的操作符是 <<-，那么分界符(EOF)所在行的开头部分的制表符(Tab)都将被去除 
# 重定向中的特殊字符需要转义，如`$`，如果不转义，那么会取当前bash中的变量，而不是重定向环境中的变量！
# expect 中的 eof 中的语句会在当前返回的信息不再期望有输入，且expect没有匹配项能匹配成功时执行，但如果之前遇到 exit 语句就会提前退出，不会执行 eof 方法。
# expect 中的 timeout 中的语句会在当前返回的信息期望有输入执行，且expect中的匹配项在指定时间内没有匹配成功时执行。
# exp_continue 是再次匹配输入
# expect 匹配必须执行 exit 退出
/usr/bin/expect <<-EOF
    set timeout 60
    spawn ssh-keygen -t rsa -P ""
    expect {
        "*save the key*" { 
            send "\r"; exp_continue 
        }
        "Overwrite (y/n)?" { 
            send "n\r" 
            send_user "\nssh-key已经存在，不需要再重新生成\n"
            exit 2
        }
        timeout { 
            send_user \n"匹配等待60s超时\n"
            exit 1
        }
        eof { 
            send_user "\nssh-keygen 生成成功\n"
            exit 0
        }
    }
EOF
# 结尾的EOF必须顶格写，前后不要有多余的空格或制表符！
}

# 将公钥写入目标节点的 ~/.ssh/authorized_keys
# 传参 $1:目标节点IP，$2:目标节点密码
# 注意 ~ 在 expect 无法找到当前用户的主目录，用 $HOME
function ssh_copy_id_to_target(){
    expect -c "
    set timeout 60;
    spawn ssh-copy-id -i $HOME/.ssh/id_rsa.pub $1;
    expect {
        *Permission*denied* { send_user \"\n服务器 $1：密码错误，验证失败\n\"; exit 2; }
        *(yes/no)?* { send yes\r; exp_continue; }
        *password:* { send $2\r; send_user \"\n为服务器 $1：配置免密登陆\"; exp_continue; }
        timeout { send_user \"\n服务器 $1：60s超时\n\n\"; exit 3; }
        eof { send_user \"\n服务器 $1：执行完毕\n\n\"; exit 0; }
    }
    "
}

# ===================================================================================================================================
# ==================== Main ========================== Main =================================== Main ================================
# ===================================================================================================================================


# $# 代表脚本输出参数的个数
# [ 左右必须要有一个空格
if [ "$#" -eq 0 ]; then
    echo 'Usage: args [ -h "host1 [host2 host3]" ] [ -p "password" ]'
    exit 1
fi

# 脚本接受两个参数 -h, -p
# 第一个`:`代表在 getopts 工作于silent mode，在此模式下，如果用户输入参数不满足OPTSTRING时，不会输出 illegal option 类似的信息，不写代表 verbose mode。
# 参数后面的`:`代表这个参数后面还需要跟一个参数才合法
# $OPTIND 记录了 getopts 要处理的下一个参数的索引，如 $3
# $OPTARG 代表当前参数`:`后面的 value
while getopts :h:p: option
do 
    case "$option" in
        h)
            target_servers=$OPTARG
        ;;
        p)
            password=$OPTARG
        ;;
        \?)
            echo 'Usage: args [ -h "host1 [host2 host3]" ] [ -p "password" ]'
            exit 1
        ;;
    esac
done

# 生成 ssh-key
ssh_key_gen
# 若ssh-key 已经存在，则将公钥发送到目标节点
if [ "$?" -ne "1" ]; then
    for server in $target_servers
    do
        ssh_copy_id_to_target $server $password
        status="$?"
        # 超时
        if [ "$status" -eq 3 ]; then
            continue
        # 错误
        elif [ "$status" -ne 0 ]; then
            exit 1
        fi
    done
    exit 0
fi 

exit 1