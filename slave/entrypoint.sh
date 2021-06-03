#!/bin/bash
set -e

# Sleep 5 seconds, before Master starts
sleep 5

if [ ! -d '/var/lib/mysql/mysql' -a "${1%_safe}" = 'mysqld' ]; then
	if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
		echo >&2 'error: database is uninitialized and MYSQL_ROOT_PASSWORD not set'
		echo >&2 '  Did you forget to add -e MYSQL_ROOT_PASSWORD=... ?'
		exit 1
	fi
	
	mysql_install_db --user=mysql --datadir=/var/lib/mysql
	
	# These statements _must_ be on individual lines, and _must_ end with
	# semicolons (no line breaks or comments are permitted).
	# TODO proper SQL escaping on ALL the things D:
	TEMP_FILE='/tmp/mysql-first-time.sql'
	
	Master_Position=$(eval "mysql --host master -uroot -ptest -e 'show master status \G' | grep Position | sed -n -e 's/^.*: //p'")
	Master_File=$(eval "mysql --host master -uroot -ptest -e 'show master status \G'     | grep File     | sed -n -e 's/^.*: //p'")

	cat > "$TEMP_FILE" <<-EOSQL
		DELETE FROM mysql.user ;
		CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
		GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
		STOP SLAVE;
		CHANGE MASTER TO master_host='master', master_user='root', master_password='test', master_log_file='$Master_File', master_log_pos=$Master_Position ;
		START SLAVE;
	EOSQL
	
	if [ "$MYSQL_DATABASE" ]; then
		echo "CREATE DATABASE IF NOT EXISTS $MYSQL_DATABASE ;" >> "$TEMP_FILE"
	fi
	
	if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
		echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" >> "$TEMP_FILE"
		
		if [ "$MYSQL_DATABASE" ]; then
			echo "GRANT ALL ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'%' ;" >> "$TEMP_FILE"
		fi
	fi
	
	echo 'FLUSH PRIVILEGES ;' >> "$TEMP_FILE"
	
	set -- "$@" --init-file="$TEMP_FILE"
fi

chown -R mysql:mysql /var/lib/mysql
exec "$@"
