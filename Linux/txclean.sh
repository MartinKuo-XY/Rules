#!/bin/bash 

# 删除腾讯云/云监控相关目录
rm -rf /usr/local/sa 
rm -rf /usr/local/agenttools 
rm -rf /usr/local/qcloud 

# 定义需要杀掉的进程列表
process=(sap100 secu-tcs-agent sgagent64 barad_agent agent agentPlugInD pvdriver ) 

# 循环杀进程
for i in ${process[@]} 
do
    # 查找并强制杀掉进程
    for A in $(ps aux |grep $i |grep -v grep |awk '{print $2}') 
    do
        kill -9 $A 
    done 
done 

# --- 修改开始 ---
# 使用 systemctl 替代 chkconfig (兼容现代Linux)
# 2>/dev/null 表示如果有错误(比如服务不存在)则不显示报错
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop postfix 2>/dev/null
    systemctl disable postfix 2>/dev/null
else
    # 如果系统真的很老，没有systemctl，尝试用旧命令
    service postfix stop 2>/dev/null
    chkconfig --level 35 postfix off 2>/dev/null
fi
# --- 修改结束 ---

# 清空 root 的计划任务
echo '' > /var/spool/cron/root 

# 重置 rc.local
echo '#!/bin/bash' > /etc/rc.local
# 确保 rc.local 有执行权限 (这是一个好习惯)
chmod +x /etc/rc.local
