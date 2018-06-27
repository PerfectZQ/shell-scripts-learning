#!/bin/bash

# ==========================================================================
# ======== Configure ssh login without password ============================
# ======== Created by ZhangQiang on 2018-5-24 ==============================
# ==========================================================================


usage='Usage: args [--source-files : 源文件(夹)地址] [--target-paths : 目标地址] \n
        --source-files [neu@hostname:]/path/file1 [[neu@hostname:]/path/file2 [neu@hostname:]/path/file3 ...] \n
        --target-paths [neu@hostname:]/path [[neu@hostname:]/path [neu@hostname:]/path ...]'

# 注意：判断符号 [ ] 两端必须要有空格来分隔！
if [ "$#" -eq 0 ]; then
    echo -e $usage
    exit 1
fi

# 保证 --source-files 和 --target-paths 都有合法参数
check_source_option=0
check_target_option=0

while [ "$#" -gt 0 ]
do
    case $1 in
      "--source-files") # 源文件 
       shift
       # linux shell  `.`匹配 1到多个任意字符，`*`匹配 0到多个任意字符
       echo "$1" | grep "^--." >& /dev/null
       while [ "$?" -ne 0 ]
       do
          # $(( )) `$`,`(`,`(` 之间不能有空格，`+` 也是
          check_source_option=$(( $check_source_option+1 ))
          source_files="$source_files $1"
          shift
          if [ "$#" -eq 0 ]; then
              break
          fi
          echo "$1" | grep "^--." >& /dev/null
       done
      ;;
      "--target-paths") # 目标路径
       shift
       echo "$1" | grep "^--." >& /dev/null
       while [ "$?" -ne 0 ]
       do
          check_target_option=$(( $check_target_option+1 ))
          target_paths="$target_paths $1"
          shift
          if [ "$#" -eq 0 ]; then
              break
          fi
          echo "$1" | grep "^--." >& /dev/null
       done
      ;;
      *) # 非法参数
      echo "Invalid option : $1"
      echo $usage
      exit 1
      ;;
    esac
done 

if [ $check_source_option -lt 1 ]; then
    echo "缺少参数 --source-files，或未指定参数值"
    exit 1
elif [ $check_target_option -lt 1 ]; then
    echo "缺少参数 --target-paths，或未指定参数值"
    exit 1
fi

for target_path in $target_paths
do
    scp -rp $source_files $target_path
    if [ "$?" -ne 0 ]; then
        echo "$target_path scp 传送失败"
        exit 2
    fi
done

exit 0

# echo "cp $@ /opt/neu/spark-2.2.0-bin-hadoop2.6/jars/"
# cp "$@" /opt/neu/spark-2.2.0-bin-hadoop2.6/jars/

# ips=("s12180" "s12181" "s12191" "s12192")

# for ((i = 0; i < ${#ips[@]}; i++)); do     
#     echo "scp to ${ips[$i]}..."
#     scp "$@" neu@"${ips[$i]}":/opt/neu/spark-2.2.0-bin-hadoop2.6/jars/
# done


