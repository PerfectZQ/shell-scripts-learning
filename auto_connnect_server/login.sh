#!/bin/bash

cur_dir=$(cd `dirname $0`; pwd)
password="******"
login_ip="192.168.10.1"
username="zhangqiang"
board_host="bj.board.XXX.com"

echo "Please enter verification code from google authenticator."
read -s verification

"$cur_dir"/ssh_expect.sh $login_ip $password "$verification" $username $board_host