#!/bin/bash


UP_OR_DOWN=${1}

if [ "$#" -lt 1 ]; then
  echo "USAGE:"
  echo "- first argument: 'up' or 'down'"
  exit 1
fi

if [ "${UP_OR_DOWN}" != "up" ] && [ "${UP_OR_DOWN}" != "down" ]; then
  echo "ERROR: first argument should be either 'up' or 'down'."
  exit 1
fi

if [ "${UP_OR_DOWN}" == "down" ]; then
  echo "Stopping containers and cleaning up..."
  docker-compose down -v

  echo "Deleting run_* scripts..."
  rm -f run_bash_* run_mysql_* run_inspect_* run_logs_*
 
  echo "Deleteing data volumes" 
  rm -rf ./data/*

  exit 0
fi


#start containers
docker-compose up -d

#verify master is up 
until docker exec mysql-master sh -c 'export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -u root -e ";"'
do
    echo "Waiting for master database connection..."
    sleep 4
done

echo "ready for setup"
EXEC_MASTER="docker exec mysql-master mariadb -uroot -pr00t-p4ssw0rd -e "

#grab information for replication setup 
MS_STATUS=`docker exec mysql-master sh -c 'export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $5}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $6}'`

#create replication user 
priv_stmt='CREATE USER "orcUser"@"%" IDENTIFIED BY "orcPass1234#"; GRANT ALL ON *.* to "orcUser"@"%";'
docker exec mysql-master sh -c "export MYSQL_PWD='r00t-p4ssw0rd'; mariadb -u root -e '$priv_stmt'"

#create percona toolkit user:
toolkit_stmt='CREATE USER "toolkit"@"%" IDENTIFIED BY "Toolkit!"; GRANT SELECT on *.* TO "toolkit"@"%";'
docker exec mysql-master sh -c "export MYSQL_PWD='r00t-p4ssw0rd'; mariadb -u root -e '$toolkit_stmt'"

#create proxysql monitor user
proxysql_stmt='CREATE USER "monitor"@"%" IDENTIFIED BY "monitor"; GRANT USAGE, REPLICATION CLIENT ON *.* TO "monitor"@"%";'
docker exec mysql-master sh -c "export MYSQL_PWD='r00t-p4ssw0rd'; mariadb -u root -e '$proxysql_stmt'"



#check at least 1 replica is up 
until docker exec mysql-replica1 sh -c 'export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -u root -e ";"'
do
    echo "Waiting for master database connection..."
    sleep 4
done

#create the command for setting up replication
start_slave_stmt="CHANGE MASTER TO MASTER_HOST='mysql-master',MASTER_USER='orcUser',MASTER_PASSWORD='orcPass1234#',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"

start_slave_cmd='export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'

#setup replication
echo "replica1"
docker exec mysql-replica1 sh -c "$start_slave_cmd"
echo "replica2"
docker exec mysql-replica2 sh -c "$start_slave_cmd"

#verify replication is working 
docker exec mysql-replica1 sh -c "export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -e 'SHOW SLAVE STATUS \G'"
docker exec mysql-replica2 sh -c "export MYSQL_PWD="r00t-p4ssw0rd"; mariadb -e 'SHOW SLAVE STATUS \G'"

#create orchestrator database to handle cluster information
${EXEC_MASTER} "CREATE DATABASE meta;" 2>&1 | grep -v "Using a password"
${EXEC_MASTER} "CREATE TABLE IF NOT EXISTS meta.cluster (anchor TINYINT NOT NULL, cluster_name VARCHAR(128) \
CHARSET ascii NOT NULL DEFAULT '', cluster_domain VARCHAR(128) CHARSET ascii NOT NULL DEFAULT '',\
 repl_user VARCHAR(128) CHARSET ascii NOT NULL DEFAULT '', repl_pass VARCHAR(128) CHARSET ascii NOT NULL DEFAULT '',\
PRIMARY KEY (anchor))" 2>&1 | grep -v "Using a password"
${EXEC_MASTER} "INSERT INTO meta.cluster VALUES (1, 'pocFran', 'pocFran', 'test', 'test1234#')" 2>&1 | grep -v "Using a password"

echo "---> Running Orchestrator discovery on MySQL master node"

#discover the cluster to orchestrator 
docker exec -e ORCHESTRATOR_API="http://localhost:3000/api"  orchestrator /usr/local/orchestrator/orchestrator -c discover -i mysql-master:3306 -config /etc/orchestrator/orchestrator.conf.json
