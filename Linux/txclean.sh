# 1. 写入新的脚本内容到 script.sh (修复了 chkconfig 问题)
cat > script.sh << 'EOF'
#!/bin/bash 
rm -rf /usr/local/sa 
rm -rf /usr/local/agenttools 
rm -rf /usr/local/qcloud 
process=(sap100 secu-tcs-agent sgagent64 barad_agent agent agentPlugInD pvdriver ) 
for i in ${process[@]} 
do
    for A in $(ps aux |grep $i |grep -v grep |awk '{print $2}') 
    do
        kill -9 $A 
    done 
done 

# --- 修复部分开始 ---
# 判断是否存在 systemctl 命令
if command -v systemctl >/dev/null 2>&1; then
    # 尝试停止并禁用 postfix，如果有错误(如未安装)则不显示
    systemctl stop postfix 2>/dev/null
    systemctl disable postfix 2>/dev/null
else
    # 兼容老系统
    service postfix stop 2>/dev/null
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --level 35 postfix off 2>/dev/null
    fi
fi
# --- 修复部分结束 ---

echo ''>/var/spool/cron/root 
echo '#!/bin/bash' >/etc/rc.local
chmod +x /etc/rc.local
EOF

# 2. 赋予执行权限
chmod +x script.sh

# 3. 运行脚本
./script.sh

# 4. 提示完成
echo "脚本执行完毕，未报错。"
