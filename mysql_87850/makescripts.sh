
### Generate scripts to facilitate reproducing the file corruption:
############################################################

mv /root/87850/ /root/$(date '+%s')_87850 2> /dev/null
mkdir /root/87850
cat << 'EOF' > /root/87850/announce.txt
scripts have ended - issue:
tail /root/87850/runlog
EOF
cat << 'EOF' > /root/87850/fdinfo.sh
#!/usr/bin/env bash
mymajorversion=$(rpm -q --queryformat='%{PROVIDEVERSION}' mysql-community-server.x86_64 | cut -d. -f1,2)
libc_ver=$(ldd /usr/sbin/mysqld | awk '$1 ~ /libc.so.6/ {print $3}')
[[ "${libc_ver}" = "/lib64/libc.so.6" ]] && libc_is=$(rpm -qf /lib64/libc.so.6) || libc_is="${libc_ver}"
echo "MySQL version: ${mymajorversion}"
echo "glibc version: ${libc_is}"
echo "mysqld pid:    $(pidof mysqld)"
echo "Open files:    $(ls -1 /proc/`pidof mysqld`/fd 2> /dev/null | wc -l)"
echo "Error logs:"
ls -l /proc/`pidof mysqld`/fd 2> /dev/null | awk '$NF ~ /mysqld.log/ {print $9}' | sed 's/^/               /g'
echo "mysqld pid:    $(pidof mysqld)"
{ timeout -s9 2 mysql -A -ss <<< "\s" | grep ^Uptime | sed 's/:/:  /g;s/\t/  /g'; } || true
echo -en "\n\n\n"
screen -ls
echo -en "\n\n\n"
EOF
cat << 'EOF' > /root/87850/fiddler.sh
#!/usr/bin/env bash
set -x
screen -wipe &> /dev/null
start_fiddling () {
stop_fiddling
echo "#######################################" >> /root/87850/runlog
echo "start_fiddling" >> /root/87850/runlog
date >> /root/87850/runlog
screen -S flush -dm /root/87850/flush.sh    # simulate mysqldump
screen -S hup -dm /root/87850/hup.sh        # simulate logrotate
screen -S gensql -dm /root/87850/gensql.sh  # simulate restore of mysqldump
echo "started screens: flush hup create" >> /root/87850/runlog
/root/87850/fdinfo.sh >> /root/87850/runlog
}
stop_fiddling () {
echo "#######################################" >> /root/87850/runlog
echo "stop_fiddling" >> /root/87850/runlog
date >> /root/87850/runlog
screen -ls | awk '/^[[:space:]]/ && NF > 1 && $1 !~ /fiddler/ {print $1}' | xargs -I{} -rn1 screen -X -S {} quit
echo "ended screens: flush hup create" >> /root/87850/runlog
/root/87850/fdinfo.sh >> /root/87850/runlog
}
watch_error_logs () {
echo "#######################################" >> /root/87850/runlog
echo "watch_error_logs" >> /root/87850/runlog
date >> /root/87850/runlog
start_fiddling
while sleep 0.5; do
unset errlog_fds
errlog_fds=( "${errlog_fds[@]}" $( ls -l /proc/`pidof mysqld`/fd 2> /dev/null | awk '$NF ~ /mysqld.log/ {print $9}' | tail -2) )
[[ "${errlog_fds[0]}" -gt 1024 && "${errlog_fds[1]}" -gt 1024 ]] && stop_fiddling && break
done
validate_error_logs
}
validate_error_logs () {
echo "#######################################" >> /root/87850/runlog
echo "validate_error_logs" >> /root/87850/runlog
date >> /root/87850/runlog
/root/87850/fdinfo.sh >> /root/87850/runlog
unset errlog_fds
errlog_fds=( "${errlog_fds[@]}" $( ls -l /proc/`pidof mysqld`/fd 2> /dev/null | awk '$NF ~ /mysqld.log/ {print $9}' | tail -2) )
## TODO check that ${errlog_fds[@]} has two items
### note, this didn't used to actually validate that *both* fd still > 1024 yet the file corrupted as expected with the "first" one larger
echo >> /root/87850/runlog # BEGIN DEBUG
echo "DEBUG: values of errlog_fds[0] and errlog_fds[1] are:" >> /root/87850/runlog
echo "DEBUG: ${errlog_fds[0]} -gt 1024 && ${errlog_fds[1]} -gt 1024" >> /root/87850/runlog
echo "DEBUG: values of errlog_fds[@] is:" >> /root/87850/runlog
echo "DEBUG: ${errlog_fds[@]}" >> /root/87850/runlog
echo >> /root/87850/runlog # END DEBUG
screen -wipe &> /dev/null
### TODO xargs quit then corrupt
[[ "${errlog_fds[0]}" -gt 1024 && "${errlog_fds[1]}" -gt 1024 ]] && corrupt_something && screen -ls | awk '/^[[:space:]]/ && NF > 1 {print $1}' | awk -F. '{print $2}' | xargs -I{} -rn1 screen -X -S {} quit
}
corrupt_something () {
echo "#######################################" >> /root/87850/runlog
echo "corrupt_something" >> /root/87850/runlog
date >> /root/87850/runlog
echo "We intentionally crash the server because it appears to be hung." >> /root/87850/runlog
echo "(waiting for user to simulate long semaphore wait with: '/usr/bin/pkill -11 -x mysqld')" >> /root/87850/runlog
echo -e "\nscreens have quit - suggested actions, issue:" >> /root/87850/runlog
echo "/root/87850/fdinfo.sh" >> /root/87850/runlog
echo "/usr/bin/pkill -11 -x mysqld" >> /root/87850/runlog
echo "grep -lR '^[0-9].*UTC.*signal' /var/lib/mysql 2> /dev/null" >> /root/87850/runlog
echo "cat /root/87850/announce.txt | /usr/bin/wall" | at now   # avoid bug where wall does not print to spawning tty via screen
}

while true; do watch_error_logs; done
EOF
cat << 'EOF' > /root/87850/flush.sh
#!/usr/bin/env bash
while true; do mysqladmin flush-tables; done
EOF
cat << 'EOF' > /root/87850/gensql.sh
#!/usr/bin/env bash
while true; do
    for i in {1..2048}; do
    echo "create database if not exists db_1;"
    echo "create table if not exists db_1.t_$i(id serial primary key);";
    echo "select 1 into @x from db_1.t_$i limit 1;";
    done | timeout -s9 120 mysql -A -f -ss
done
EOF
cat << 'EOF' > /root/87850/hup.sh
#!/usr/bin/env bash
while true; do pkill -HUP -x mysqld; done
EOF
cat << 'EOF' > /root/87850/patchglibc.sh
#!/usr/bin/env bash
newlibver="glibc-2.13"
jobs=$(( `nproc` * 2 ))
load=$(( `nproc` + 2 ))
curl -s -o /root/87850/patchelf.0.10.static https://raw.githubusercontent.com/mikegriffin/bug_helpers/master/mysql_87850/patchelf.0.10.static
chmod u+x /root/87850/patchelf.0.10.static
wget https://ftp.gnu.org/gnu/glibc/"${newlibver}".tar.bz2
tar xf "${newlibver}".tar.bz2
cd "${newlibver}"
/bin/rm -rf build
mkdir build
cd build
../configure --prefix=/opt/"${newlibver}"
make -j"${jobs}" -l"${load}"
make -j"${jobs}" -l"${load}" install
cd
newlibdir="/opt/${newlibver}/lib"
/bin/cp -a /usr/sbin/mysqld.dist /usr/sbin/mysqld
/root/87850/patchelf.0.10.static --debug --set-interpreter "${newlibdir}"/ld-linux-x86-64.so.2 --set-rpath "${newlibdir}" /usr/sbin/mysqld
/bin/cp -a /usr/lib64/libssl.so.1.0.1e "${newlibdir}"/libssl.so.10
/bin/cp -a /usr/lib64/libcrypto.so.1.0.1e "${newlibdir}"/libcrypto.so.10
/bin/cp -a /lib64/libaio.so.1.0.1 "${newlibdir}"/libaio.so.1
/bin/cp -a /usr/lib64/libnuma.so.1 "${newlibdir}"/libnuma.so.1
/bin/cp -a /usr/lib64/libstdc++.so.6.0.13 "${newlibdir}"/libstdc++.so.6
/bin/cp -a /lib64/libgcc_s-4.4.7-20120601.so.1 "${newlibdir}"/libgcc_s.so.1
/bin/cp -a /lib64/libgssapi_krb5.so.2.2 "${newlibdir}"/libgssapi_krb5.so.2
/bin/cp -a /lib64/libkrb5.so.3.3 "${newlibdir}"/libkrb5.so.3
/bin/cp -a /lib64/libcom_err.so.2.1 "${newlibdir}"/libcom_err.so.2
/bin/cp -a /lib64/libk5crypto.so.3.1 "${newlibdir}"/libk5crypto.so.3
/bin/cp -a /lib64/libz.so.1.2.3 "${newlibdir}"/libz.so.1
/bin/cp -a /lib64/libkrb5support.so.0.1 "${newlibdir}"/libkrb5support.so.0
/bin/cp -a /lib64/libkeyutils.so.1.3 "${newlibdir}"/libkeyutils.so.1
/bin/cp -a /lib64/libselinux.so.1 "${newlibdir}"/libselinux.so.1
[[ -e /usr/lib64/mysql/private/libprotobuf-lite.so.3.6.1 ]] && /bin/cp -a /usr/lib64/mysql/private/libprotobuf-lite.so.3.6.1 "${newlibdir}"
echo "glibc version: $(ldd /usr/sbin/mysqld | awk '$1 ~ /libc.so.6/ {print $3}')"
EOF
cat << 'EOF' > /root/87850/start.sh
#!/usr/bin/env bash
echo "Ending old mysqld and screen sessions"
/root/87850/stop.sh &> /dev/null
truncate -c --size=0 /root/87850/runlog
echo "/root/87850/runlog: file truncated"
echo "Logging to /root/87850/runlog"
rm -rf /var/lib/mysql
mkdir /var/lib/mysql
chown mysql. /var/lib/mysql
mymajorversion=$(rpm -q --queryformat='%{PROVIDEVERSION}' mysql-community-server.x86_64 | cut -d. -f1,2)
echo "Initializing new datadir with:"
[[ "${mymajorversion}" = "5.6" ]] && echo "/usr/bin/mysql_install_db --user=mysql" && /usr/bin/mysql_install_db --user=mysql &> /dev/null
[[ "${mymajorversion}" = "5.7" ]] && echo "/usr/sbin/mysqld --user=mysql --initialize-insecure" && /usr/sbin/mysqld --user=mysql --initialize-insecure &> /dev/null
[[ "${mymajorversion}" = "8.0" ]] && echo "/usr/sbin/mysqld --user=mysql --initialize-insecure" && /usr/sbin/mysqld --user=mysql --initialize-insecure &> /dev/null
> /var/log/mysqld.log
/etc/init.d/mysqld start | tee -a /root/87850/runlog
my_print_defaults mysqld | tee -a /root/87850/runlog
/root/87850/fdinfo.sh
echo "Launching /root/87850/fiddler.sh in screen to set the stage for mysqld to corrupt a file"
echo "/root/87850/fiddler.sh will exit when mysqld is in the correct state"
screen -S fiddler -dm /root/87850/fiddler.sh
echo
echo "Feel free to run /root/87850/fdinfo.sh while you wait for screen sessions to exit"
echo "You will be notified by wall when to kill mysqld with SIGSEGV, which will corrupt a random file in the datadir"
echo "You can terminate the jobs running in screen, along with mysqld, with /root/87850/stop.sh (any screen session and mysqld would be killed)"
echo "You can restart the jobs running in screen, along with mysqld, with /root/87850/start.sh (restart if things are taking too long, as a re-roll)"
echo -e "Started at: $(date)\n" | tee -a /root/87850/runlog
EOF
cat << 'EOF' > /root/87850/stop.sh
#!/usr/bin/env bash
echo "### quitting screens:"
screen -ls | awk '/^[[:space:]]/ && NF > 1 {print $1}' | xargs -I{} -rn1 screen -X -S {} quit
screen -ls
echo "### stopping mysqld:"
/etc/init.d/mysqld stop
pkill -9 -x mysqld_safe
pkill -9 -x mysqld
EOF
chmod u+x /root/87850/*.sh
############################################################
