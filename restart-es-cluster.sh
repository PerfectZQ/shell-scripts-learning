#!/bin/bash

# ======================================================================================================================================
# ========= Created By ZhangQiang in 2018-5-23
# ======================================================================================================================================
# ========= 说明：用于重启 es 集群，目前在 centos6.8 和 centos 7.2上做过测试，其他系统可能需要调整下一脚本
# ========= 使用方式： 修改 Options 中的 es_hosts 执行下面的启动脚本即可
# ========= 启动脚本： sh restart-es-cluster.sh
# ======================================================================================================================================

es_hosts="10.4.125.172 10.4.125.173 10.4.125.174 10.4.125.175"
es_home=/home/es/elasticsearch-6.2.4/
http_port=9200

for server in $es_hosts
do  
    ssh es@$server<<-EOF
    ps aux | grep -i elasticsearch | grep -v grep | awk '{print \$2}' | xargs kill -9
    ps aux | grep -v grep | grep -i elasticsearch
    if [ "\$?" == "1" ]; then
        echo "服务器:$server，没有找到正在运行的 es 实例 ..."
        echo "服务器:$server，启动 es 实例 ...."
        $es_home/bin/elasticsearch -d
    else
        echo "服务器:$server，已经存在启动的 es 实例"
        return 2
    fi
EOF
done


sleep 30s

for server in $es_hosts
do  
    curl -XGET  "http://$server:$http_port" | grep -w "You Know, for Search" > /dev/null
    if [ $? -eq 0 ]; then
        echo "$server $es_name 启动成功！"
    else
        echo "$server $es_name 启动失败，查看 $server /home/es/elasticsearch-6.2.4/logs/my-elasticsearh.log 获取异常原因"
    fi
done