#!/bin/bash
# aria2 autoupload.sh by p3terx, adapt heroku-ariang by xinxin8816 and kwok1am.

## 文件过滤 file filter ##

# 限制最低上传大小，仅 bt 多文件下载时有效，用于过滤无用文件。低于此大小的文件将被删除，不会上传。
# limit the minimum upload size, which is only valid when downloading multiple bt files, and is used to filter useless files. files below this size will be deleted and will not be uploaded.
#min_size=10m

# 保留文件类型，仅 bt 多文件下载时有效，用于过滤无用文件。其它文件将被删除，不会上传。
# keep the file type, only effective when downloading multiple bt files, used to filter useless files. other files will be deleted and will not be uploaded.
#include_file='mp4,mkv,rmvb,mov'

# 排除文件类型，仅 bt 多文件下载时有效，用于过滤无用文件。排除的文件将被删除，不会上传。
# exclude file types, valid only when downloading multiple bt files, used to filter useless files. excluded files will be deleted and will not be uploaded.
#exclude_file='html,url,lnk,txt,jpg,png'

## 高级设置 advanced settings ##

# rclone 配置文件路径
# rclone configuration file path
# export rclone_config=/content/rclone.conf

# rclone 并行上传文件数，仅对单个任务有效。
# rclone the number of files uploaded in parallel is only valid for a single task.
#export rclone_transfers=4

# rclone 块的大小，默认5m，理论上是越大上传速度越快，同时占用内存也越多。如果设置得太大，可能会导致进程中断。
# rclone the size of the block, the default is 5m. theoretically, the larger the upload speed, the faster it will occupy more memory. if the setting is too large, the process may be interrupted.
export rclone_cache_chunk_size=3m

# rclone 块可以在本地磁盘上占用的总大小，默认10g。
# rclone the total size that the block can occupy on the local disk, the default is 10g.
#export rclone_cache_chunk_total_size=10g

# rclone 上传失败重试次数，默认 3
# rclone upload failed retry count, the default is 3
#export rclone_retries=3

# rclone 上传失败重试等待时间，默认禁用，单位 s, m, h
# rclone upload failure retry wait time, the default is disabled, unit s, m, h
export rclone_retries_sleep=30s

# rclone 异常退出重试次数
# rclone abnormal exit retry count
retry_num=3

#============================================================

source /content/tool/aria2c_upload/aria2c_upload.config # 加载变量
# rclone_destination='lmq-sryp:aria2c'
# download_path='/content/download'
file_path=$3                                          # aria2传递给脚本的文件路径。bt下载有多个文件时该值为文件夹内第一个文件，如/root/download/a/b/1.mp4
remove_download_path=${file_path#${download_path}/}   # 路径转换，去掉开头的下载路径。
top_path=${download_path}/${remove_download_path%%/*} # 路径转换，bt下载文件夹时为顶层文件夹路径，普通单文件下载时与文件路径相同。
info="[info]"
error="[error]"
warring="[warring]"

task_info() {
    echo -e "
-------------------------- [task info] --------------------------
download path: ${download_path}
file path: ${file_path}
upload path: ${upload_path}
remote path a: ${remote_path}
remote path b: ${remote_path_2}
-------------------------- [task info] --------------------------
"
}

clean_up() {
    [[ -n ${min_size} || -n ${include_file} || -n ${exclude_file} ]] && echo -e "${info} clean up excluded files ..."
    [[ -n ${min_size} ]] && fclone delete -v "${upload_path}" --max-size ${min_size}
    [[ -n ${include_file} ]] && fclone delete -v "${upload_path}" --exclude "*.{${include_file}}"
    [[ -n ${exclude_file} ]] && fclone delete -v "${upload_path}" --include "*.{${exclude_file}}"
}

upload_file() {
    retry=0
	echo "$(($(cat /content/numupload)+1))" > /content/numupload # plus 1
    while [ ${retry} -le ${retry_num} ]; do
        [ ${retry} != 0 ] && (
            echo
            echo -e "$(date +"%m/%d %h:%m:%s") ${error} ${upload_path} upload failed! retry ${retry}/${retry_num} ..."
            echo
        )
        fclone copy -v "${upload_path}" "${remote_path}"
        rclone_exit_code=$?
		rclone_exit_code_2=0
		if [ -n "${rclone_destination_2}" ]; then
			fclone copy -v "${upload_path}" "${remote_path_2}"
			rclone_exit_code_2=$?
		fi
        if [ ${rclone_exit_code} -eq 0 ] && [ ${rclone_exit_code_2} -eq 0 ]; then
            [ -e "${dot_aria2_file}" ] && rm -vf "${dot_aria2_file}"
            fclone rmdirs -v "${download_path}" --leave-root
            echo -e "$(date +"%m/%d %h:%m:%s") ${info} upload done: ${upload_path}"
			fclone delete -v "${upload_path}"
            break
        else
            retry=$((${retry} + 1))
            [ ${retry} -gt ${retry_num} ] && (
                echo
                echo -e "$(date +"%m/%d %h:%m:%s") ${error} upload failed: ${upload_path}"
                echo
            )
            sleep 3
        fi
    done
	echo "$(($(cat /content/numupload)-1))" > /content/numupload # minus 1
}

upload() {
    echo -e "$(date +"%m/%d %h:%m:%s") ${info} start upload..."
    task_info
    upload_file
}

if [ -z $2 ]; then
    echo && echo -e "${error} this script can only be used by passing parameters through aria2."
    echo && echo -e "${warring} 直接运行此脚本可能导致无法开机！"
    exit 1
elif [ $2 -eq 0 ]; then
    exit 0
fi

if [ -e "${file_path}.aria2" ]; then
    dot_aria2_file="${file_path}.aria2"
elif [ -e "${top_path}.aria2" ]; then
    dot_aria2_file="${top_path}.aria2"
fi

if [ "${top_path}" = "${file_path}" ] && [ $2 -eq 1 ]; then # 普通单文件下载，移动文件到设定的网盘文件夹。
    upload_path="${file_path}"
    remote_path="${rclone_destination}/"
    remote_path_2="${rclone_destination_2}/"
    upload
    exit 0
elif [ "${top_path}" != "${file_path}" ] && [ $2 -gt 1 ]; then # bt下载（文件夹内文件数大于1），移动整个文件夹到设定的网盘文件夹。
    upload_path="${top_path}"
    remote_path="${rclone_destination}/${remove_download_path%%/*}"
	remote_path_2="${rclone_destination_2}/${remove_download_path%%/*}"
    clean_up
    upload
    exit 0
elif [ "${top_path}" != "${file_path}" ] && [ $2 -eq 1 ]; then # 第三方度盘工具下载（子文件夹或多级目录等情况下的单文件下载）、bt下载（文件夹内文件数等于1），移动文件到设定的网盘文件夹下的相同路径文件夹。
    upload_path="${file_path}"
    remote_path="${rclone_destination}/${remove_download_path%/*}"
	remote_path_2="${rclone_destination_2}/${remove_download_path%/*}"
    upload
    exit 0
fi

echo -e "${error} unknown error."
task_info
exit 1
