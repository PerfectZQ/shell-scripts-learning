#!/bin/bash

# ====================================================================================================================================================
# ========= Created By zhang_qiang_neu in 2018-5-23
# ====================================================================================================================================================
# ========= 说明：用于一键部署 es 集群，目前在 centos6.8 和 centos 7.2上做过测试，其他系统可能需要调整下一脚本
# ========= 依赖：依赖于 scp_to_hosts.sh 和 ssh_configure.sh 执行之前需要将其放在与本脚本相同的路径下
# ========= 默认安装路径: /home/es
# ========= 默认将创建用户: es
# ========= 创建用户的密码: elasticsearch
# ========= 使用方式：直接将 elasticsearch-6.2.4.tar.gz 压缩包放在当前节点上，修改 Options 中的 root_passwd、es_passwd 和 es_hosts 执行下面的启动脚本即可
# ========= 启动脚本：sh elasticsearch_6.2.4_install.sh /root/elasticsearch-6.2.4.tar.gz
# ====================================================================================================================================================

# ==========================================================================================================
# =============== Options ====================== Options ===================== Options =====================
# ==========================================================================================================

# root 用户密码
root_passwd='crm_86520800'
# es 用户默认密码
es_passwd='elasticsearch'

# 赋值号 = 左右不可以有空格！
# 获取字符串变量str的长度 ${#$str}
if [ ${1:$(( ${#1}-1 )):${#1}} == "/" ]; then
    es_tar_path=${1:0:$(( ${#1}-1 ))}
else
    es_tar_path=$1
fi

es_hosts="192.168.10.146 192.168.10.147 192.168.10.148 192.168.10.149"
# es_hosts="10.4.125.172"

# ==========================================================================================================
# ====================================== ElasticSearch Properties ==========================================
# ==========================================================================================================

# 注意 awk {print $NF} 必须用 `'`，用 `"` 结果不对。 结果： elasticsearch-6.2.4
# $NF 代表最后一个字段
# cut -f -3 截取前三个 field，与 cut -f 1,2,3 等价
# cut -f 3- 是从第三个 filed 开始截取，包含第三个 field
es_name=$(echo "$es_tar_path" | awk -F "/" '{print $NF}' | cut -d "." -f -3)
# es 安装路径
es_home="/home/es/$es_name"

# 集群名称
# 如果检测变量为空，则赋默认值
[ -z "$cluster_name" ]
if [ "$?" -eq 0 ]; then
    cluster_name="my-elasticsearh"
fi
# 数据存放路径
path_data="/home/es/$es_name/data"
# 日志存放路径
path_logs="/home/es/$es_name/logs"
# 内存分配模式
bootstrap_memory_lock="false"
bootstrap_system_call_filter="false"
# http 服务端口
[ -z "$http_port" ]
if [ "$?" -eq 0 ]; then
    http_port="9200"
fi
# 当删除索引时，必须指定索引名称，禁止使用通配符或者_all
action_destructive_requires_name="true"
# 集群 hosts
# sed 扩展正则表达式都特么不支持 \d，我也是醉了!!!
# 10.4.125.172 10.4.125.173 10.4.125.174 10.4.125.175 => ["10.4.125.172", "10.4.125.173", "10.4.125.174", "10.4.125.175"]
discovery_zen_ping_unicast_hosts='['`echo $es_hosts | sed -r 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/"\1"/g' | sed 's/ /, /g'`']'


# ===================================================================================================================================
# ================= function ========================== function ============================== function ============================
# ===================================================================================================================================

# $1: host
function check_and_create_user(){
    echo "服务器 $1 检测并创建 es 用户与 sudo 权限"
    # -w 表示精确查找
    ssh $1 "cat /etc/passwd | grep -w es > /dev/null"
    # 单引号中的特殊字符都不生效，因此只有双引号当中才可以使用 $var
    if [ "$?" == "1" ]; then
        echo "在 $1 中没有找到名为 es 的用户..."
        echo "为 $1 创建 es 用户组..."
        ssh $1 "groupadd es"
        echo "为 $1 创建 es 用户..."
        ssh $1 "useradd es -g es"
        echo "为 $1 修改 es 密码..."
        # 重定向里面给变量赋值需要注意！例如 test="111" ，echo $test 结果为空，echo \$test 才能得到正确结果
        # 重定向中的定义的变量，在使用的时候需要转义，用 `\$var`才能正确取到
        # 而对于当前 bash 中的变量，在重定向中使用的时候，不需要转义，使用`$var`即可。
        /usr/bin/expect <<-EOF
        set timeout 60
        spawn ssh $1 "passwd es"
        expect {
            "*密码：" { 
                send "$es_passwd\r"; exp_continue 
            }
            timeout { 
                send_user "\n$1 匹配等待60s超时\n"
                exit 1
            }
            eof { 
                send_user "\n$1 密码设置成功，用户密码为：$es_passwd\n"
                exit 0
            }
        }
EOF
    else
        echo "$1 es 用户已经存在"
    fi

    # 检测 es 是否有 sudo 权限
    echo "检测 $1 es 用户 sudo 权限..."
    ssh $1 "egrep -w 'es.*$' /etc/sudoers"
    if [ "$?" == "1" ]; then
        echo "为 $1 es 用户分配 sudo 权限..."
        # insert_line=`nl -b a /etc/sudoers | egrep  "^.*NOPASSWD: ALL" | awk '{print \$1}'`
        ssh es@$1 <<-EOF
        line=\$(nl -b a /etc/sudoers | egrep  "#.*NOPASSWD: ALL" | awk '{print \$1}')
        sed -in \$line'a es  ALL=(ALL)  NOPASSWD: ALL' /etc/sudoers
EOF
        echo "$1 sudo 权限分配完成"
    else
        echo "$1 es 用户已经拥有 sudo 权限"
    fi 

}

function check_and_install_elasticsearch(){

    echo "检测并安装 $es_name"

    # > 代表标准输出， & 代表错误输出
    cd /home/es/$es_name >& /dev/null
    if [ "$?" == "1" ]; then
        echo "没有找到 elasticsearch 安装目录: $es_home !"
        echo "准备解压 elasticsearch 到 /root ..."
        tar -zxvf $es_tar_path -C /root > /dev/null
        echo "解压完成"
        return 0
    else
        echo "$es_name 已存在"
        return 1
    fi
}

# $1: host
function modify_es_conf(){
    
    echo "准备修改 $1 es 配置文件..."

    # sed [options] script [input_file...]
    # sed [option]: -i 就地修改文件，不会输出到屏幕。注意文件备份！
    # sed [option]: -n 使用安静模式。默认将所有来自stdin的内容输出到屏幕，而安静模式只显示sed特殊处理的行
    # sed [option]: -r 启用扩展正则表达式。默认是只支持基础正则表达式，启用之后就支持使用 `+`,`?`...了
    # sed script 语法：'[n1[,n2]] function'，务必使用单引号！其中n1,n2 一般用来选择要进行操作的行，例如 10,20 function 是对第10~20行进行操作
    # sed script function: a 在选中行的下一行插入内容，如 sed '1a pretty girl'，在第一行的下一行插入字符串 "pretty girl"
    # sed script function: i 在选中行的上一行插入内容，如 sed '1i pretty girl'，在第一行的上一行插入字符串 "pretty girl"
    # sed script function: d 删除所选行，如 sed '2,5d'，删掉第2~5行的内容
    # sed script function: c 替换，如 sed '2,3c line1 \ \nline2'，替换第2~3行的内容，`\`和换行符`\n`都是必须要有的！
    # sed script function: s 替换，可以搭配正则表达式进行替换，如 sed 's/old/new/g'，若末尾不写`g`，则只替换第一个被匹配到的项。分隔符`/`也可以用`#`替代
    # sed script function: p 将选择的内容打印出来，通常配合 option -n 使用

    # grep [options] pattern [file...]
    # grep [option]: -E 启用扩展正则表达式，与 egrep 等价(别名关系)
    # grep [option]: -r 递归目录下的所有文件
    # grep [option]: -l 输出所有包含匹配项的文件名

    # sed -i 's/原字符串/新字符串/g' `grep "cluster.name" -rl $es_home/config/`

    # sed -r 中的 () 需要转义，否则他会当成字符来处理 egrep 不需要

    ssh es@$1 "sed -ir 's#\#\(path\.data:\).*\$#\1 "$path_data"#g' "$es_home"/config/elasticsearch.yml"
    
    ssh es@$1 "sed -ir 's#\#\(path\.logs:\).*\$#\1 "$path_logs"#g' "$es_home"/config/elasticsearch.yml"

    ssh es@$1 "sed -ir 's/#\(cluster\.name:\).*\$/\1 "$cluster_name"/g' "$es_home"/config/elasticsearch.yml"

    hostname=`ssh es@$1 "hostname"`

    ssh es@$1 "sed -ir 's/#\(node\.name:\).*\$/\1 node-"$hostname"/g' "$es_home"/config/elasticsearch.yml"
    
    ssh es@$1 "sed -ir 's/#\(bootstrap\.memory_lock:\).*\$/\1 "$bootstrap_memory_lock"/g' "$es_home"/config/elasticsearch.yml"
    
    # nl 为文件添加行号
    # -b a 为所有行添加行号，包括空行
    # line=`nl -b a $es_home/config/elasticsearch.yml | grep '#bootstrap\.memory_lock' | awk '{print $1}'`
    ssh es@$1 "grep -w 'bootstrap.system_call_filter' $es_home/config/elasticsearch.yml"
    if [ "$?" -eq 1 ]; then
        # 为了让 nl 命令查找的文件在远程机器上，需要将$()，进行转义，即使用 \$()，或者使用 \`\`
        ssh es@$1 <<-EOF
        line=\$(nl -b a $es_home/config/elasticsearch.yml | grep 'bootstrap\.memory_lock' | awk '{print \$1}')
        sed -i \$line'a bootstrap.system_call_filter: "$bootstrap_system_call_filter"' $es_home/config/elasticsearch.yml
EOF
    fi

    ssh es@$1 "sed -ir 's/#\(http\.port:\).*\$/\1 "$http_port"/g' "$es_home"/config/elasticsearch.yml"
    
    ssh es@$1 "sed -ir 's/#\(network\.host:\).*\$/\1 "$1"/g' "$es_home"/config/elasticsearch.yml"
    
    ssh es@$1 "sed -ir 's/#\(action\.destructive_requires_name:\).*\$/\1 "$action_destructive_requires_name"/g' "$es_home"/config/elasticsearch.yml"

    # discovery.zen.ping.unicast.hosts:
    ssh es@$1 "sed -ir 's/#\(discovery\.zen\.ping\.unicast\.hosts:\).*\$/\1 "$discovery_zen_ping_unicast_hosts"/g' "$es_home"/config/elasticsearch.yml"
    echo "修改完成"
}

# 必须用 root 用户修改
# $1: host
function modify_system_config(){
    echo "检测服务器 $1 操作系统配置..."
    ssh $1 <<-EOF
    egrep -w 'es.*soft.*nofile.*$' /etc/security/limits.conf > /dev/null
    if [ "\$?" -ne 0 ]; then
        echo "修改操作系统配置..."

        echo "es soft nofile 65536" >> /etc/security/limits.conf
        echo "es hard nofile 131072" >> /etc/security/limits.conf
        echo "es soft nproc 4096" >> /etc/security/limits.conf
        echo "es hard nproc 4096" >> /etc/security/limits.conf

        sed -ir 's/\(\*.*soft.*nproc\).*$/\1 4096/g' /etc/security/limits.d/90-nproc.conf

        echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        sysctl -p > /dev/null
        
        echo "修改完成"
    else
        echo "不需要修改系统配置！"
    fi
EOF
}

# $1: host
function check_and_start_elasticsearch(){
    echo "$1 检查并启动 elasticsearch 实例..."
    ssh $1 "ps aux | grep -v grep | grep -w $es_home > /dev/null"
    if [ "$?" == "1" ]; then
        echo "服务器:$1，没有找到正在运行的 $es_name ..."
        echo "服务器:$1，启动 $es_name...."
        ssh es@$1 "/home/es/$es_name/bin/elasticsearch -d"
    else
        echo "服务器:$1，已经存在启动的 $es_name"
        return 2
    fi
}

# $1: host
function check_and_close_firewall(){
    echo "检测服务器 $1 防火墙状态.."
    # 重定向中的特殊字符需要转义，如`$`，如果不转义，那么会取当前bash中的变量，而不是重定向环境中的变量！
    ssh $1 <<-EOF
    service iptables status > /dev/null
    if [ "\$?" == "0" ]; then
        echo "检测到 $1 防火墙是开启状态，关闭防火墙..."
        service iptables stop
    fi
    systemctl status firewalld > /dev/null
    if [ "\$?" == "0" ]; then
        echo "检测到 $1 防火墙是开启状态，关闭防火墙..."
        systemctl stop firewalld
    fi

    echo "$1 防火墙已关闭"
EOF
}



# ===================================================================================================================================
# ==================== Main ========================== Main =================================== Main ================================
# ===================================================================================================================================


# 获取当前目录 
# `` (反引号)与 $() 都是用来做命令替换用的，将命令返回的结果赋值给变量，或作为其他命令的参数。
# `` 在嵌套使用的时候需要转义(如果嵌套在$()中不需要)，且与''(单引号)容易混淆。
# $()比较直观且支持嵌套，但不是所有的shell都识别，可移植性差。
# `dirname $0` 获取当前执行的脚本的父目录
workdir=$(cd `dirname $0`; pwd)

# 解压 elasticsearch 到 /root
check_and_install_elasticsearch

# 配置 root 到 各节点root 用户的免密登陆
sh $workdir/ssh_configure.sh -h "$es_hosts" -p "$root_passwd"

if [ "$?" -eq 0 ]; then
    echo "配置 root 到 各节点 root 用户的免密登陆成功！"
else
    echo "配置 root 到 各节点 root 用户的免密登陆失败！"
    exit
fi

for server in $es_hosts
do
    # 检测并创建 es 用户，分配 sudo 权限
    check_and_create_user $server
    # 检查防火墙
    check_and_close_firewall $server
done

chown -R es:es /root/$es_name

# 配置 root 到 es 用户的免密登陆
sh $workdir/ssh_configure.sh -h "`echo $es_hosts | sed -r 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/es@\1/g'`" -p 'elasticsearch'

if [ "$?" -eq 0 ]; then
    echo "配置 root 到 各节点 es 用户的免密登陆成功！"
else
    echo "配置 root 到 各节点 es 用户的免密登陆失败！"
    exit
fi


# 将 es 发送到各个节点
echo "将 es 发送到各个节点 ..."
sh $workdir/scp_to_hosts.sh --source-files /root/$es_name --target-paths `echo $es_hosts | sed -r 's#([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)#es@\1:/home/es#g'` >/dev/null
if [ "$?" -eq 0 ]; then
    echo "发送完毕 ..."
else
    exit
fi 

for server in $es_hosts
do     
    # 修改系统配置
    modify_system_config $server
    # 修改 es 配置文件
    modify_es_conf $server
    # 启动
    check_and_start_elasticsearch $server
done

sleep 30s

for server in $es_hosts
do  
    curl -XGET  "http://$server:$http_port" | grep -w "You Know, for Search" > /dev/null
    if [ $? -eq 0 ]; then
        echo "$server $es_name 启动成功！"
    else
        echo "$server $es_name 启动失败，查看 $server $path_logs/$cluster_name.log 获取异常原因"
    fi
done

