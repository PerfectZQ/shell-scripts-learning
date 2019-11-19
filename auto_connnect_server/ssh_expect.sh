#!/usr/bin/expect -f

set login_ip [ lindex "$argv" 0 ]
set password [ lindex "$argv" 1 ]
set verification [ lindex "$argv" 2 ]
set username [ lindex "$argv" 3 ]
set board_host [ lindex "$argv" 4 ]
set timeout 10

spawn ssh "$username"@"$board_host"

expect {
    "Verification*" {
        send_user "\n$verification"
        send "$verification\r"
        exp_continue
    }
    "Password*" {
        send_user "\n$password"
        send "$password\r"
        exp_continue
    }
    "*Please enter your Login Ip*" {
        send_user "\n$login_ip"
        send "$login_ip\r"
        exp_continue
    }
    "\[$username@*\]\$" {
        send_user "\n kinit"
        # awk -v 引入外部环境变量
        # send "文本"到另一个 shell 中在取变量需要加转义符号 \$9，否则就在当前 shell 中取变量值了
        send "ls -l | grep $username*keytab | awk -v ldap=$username '{print \$9,ldap}' | xargs kinit -kt\r"
    }
}

send_user "\nenter interact...\n"
# 执行完后保持交互状态，控制权交给控制台，否则会完成退出
interact