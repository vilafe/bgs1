# Подготовка

Схема:
<p align="center">
  <img src="https://github.com/vilafe/bgs1/blob/master/fotos/scheme.png" />
</p>

The Ubuntu Server 22.04 LTS was chosen for the stand deployment.
The servers have python 3.8.10 installed.

<p align="center">
  <img src="https://github.com/vilafe/bgs1/blob/master/fotos/1.png" />
</p>


Stages

1. Создание двух виртуальных машин (ВМ):

<p align="center">
  <img src="https://github.com/vilafe/bgs1/blob/master/fotos/2.png" />
</p>

2. Начальная сетевая конфигурация ВМ

Ubuntu_pSQL_1:
<p align="center">
  <img src="https://github.com/vilafe/bgs1/blob/master/fotos/3.png" />
</p>

Ubuntu_pSQL_2:
<p align="center">
  <img src="https://github.com/vilafe/bgs1/blob/master/fotos/4.png" />
</p>

# Connect to Ubuntu_pSQL_1
```
ssh root@ubuntu_psql_1.vila.local << EOF
apt-get update
apt-get install -y curl gnupg2
echo "deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/pgdg.list
curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
```

# Установка пакетов
Пакеты сетевых инструментов и `postgresql`
```
apt-get install -y postgresql-10
```

# Create Database
```
sed -i 's/local   all             postgres                                peer/local   all             postgres                                trust/' /etc/postgresql/10/main/pg_hba.conf
service postgresql restart
#################################################
#   CREATE 				DATABASE		        #
#################################################
psql -U postgres -c "CREATE DATABASE master;"
psql   -d master  -c "CREATE TABLE master (name varchar(80), surname varchar(80));"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('Wylian', 'Souza');"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('German','Kazenas');"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('Polina', 'Muratova');"
```	
# Create user replica for replication
```
psql -U postgres -c "CREATE USER replica REPLICATION LOGIN CONNECTION LIMIT 2 ENCRYPTED PASSWORD 'lab_password';"
cp /etc/postgresql/10/main/pg_hba.conf /etc/postgresql/10/main/pg_hba{`date +%s`}.bkp
sed  -i '/host    replication/d' /etc/postgresql/10/main/pg_hba.conf
echo "host    replication     replica             192.168.216.0/24                 trust" | tee -a /etc/postgresql/10/main/pg_hba.conf

cp /etc/postgresql/10/main/postgresql.conf /etc/postgresql/10/main/postgresql{`date +%s`}.bkp

if grep -Fxq "listen_addresses = '*'" /etc/postgresql/10/main/postgresql.conf
    then echo "Strig exist"
else
    echo "listen_addresses = '*'" | tee -a /etc/postgresql/10/main/postgresql.conf
fi
if grep -Fxq "hot_standby = on" /etc/postgresql/10/main/postgresql.conf
    then echo "Strig exist"
else
    echo "hot_standby = on" | tee -a /etc/postgresql/10/main/postgresql.conf
fi
if grep -Fxq "wal_level = replica" /etc/postgresql/10/main/postgresql.conf
    then echo "Strig exist"
else
    echo "wal_level = replica" | tee -a /etc/postgresql/10/main/postgresql.conf
fi
if grep -Fxq "max_wal_senders = 10" /etc/postgresql/10/main/postgresql.conf
    then echo "Strig exist"
else
    echo "max_wal_senders = 10" | tee -a /etc/postgresql/10/main/postgresql.conf
fi
if grep -Fxq "wal_keep_segments = 32" /etc/postgresql/10/main/postgresql.conf
    then echo "Strig exist"
else
    echo "wal_keep_segments = 32" | tee -a /etc/postgresql/10/main/postgresql.conf
fi
service postgresql restart

EOF
echo "Install on  sql1 is done!"
```
# Connect to Ubuntu_pSQL_2
```
ssh root@ubuntu_psqll_2.vila.local << EOF
apt-get update
apt-get install -y curl gnupg2
echo "deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/pgdg.list
service postgresql restart
curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-10
sed -i 's/local   all             postgres                                peer/local   all             postgres                                trust/' /etc/postgresql/10/main/pg_hba.conf
cp /etc/postgresql/10/main/pg_hba.conf /etc/postgresql/10/main/pg_hba{`date +%s`}.bkp
sed  -i '/host    replication/d' /etc/postgresql/10/main/pg_hba.conf

echo "host    replication     replica             192.168.216.0/24                 trust" | tee -a /etc/postgresql/10/main/pg_hba.conf

service postgresql stop
rm -R /var/lib/postgresql/10/main/
su - postgres -c "pg_basebackup -P -R -X stream -c fast -h 192.168.216.210 -U replica -D /var/lib/postgresql/10/main/"
echo "trigger_file = '/tmp/to_master'" | tee -a /var/lib/postgresql/10/main/recovery.conf
service postgresql start
```
```
mkdir /home/skript
cat > /home/skript/agent.sh << AUF
#!/bin/bash
while :
do
if pg_isready -h ubuntu_psql_1.vila.local; then
  echo "200 OK NE GOVORY, POLUCHAY 501, 503"
  rm /tmp/to_master
elif test -f /tmp/to_master_approve; then
  touch /tmp/to_master
else echo "MASTER DOES NOT EXIST, BUT ARBITOR DO NOT APPRUVE"
fi;
sleep 0.01
done
AUF

touch /etc/systemd/system/agent.service
cat > /etc/systemd/system/agent.service << AUF
[Unit]
Description = Agent on ubuntu_psql_2.vila.local
[Service]
RemainAfterExit=true
ExecStart=/bin/sh /home/skript/agent.sh
Type=simple
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
AUF

chmod +x /etc/systemd/system/agent.service

systemctl enable agent
systemctl restart agent


EOF
echo "Install on  sql2 is done!"
```

# make agent service
```
mkdir /home/skript
cat > /home/skript/agent.sh << AUF
#!/bin/bash
while :
do
if pg_isready -h ubuntu_psql_1.vila.local; then
  echo "200 OK NE GOVORY, POLUCHAY 501, 503"
  ssh root@ubuntu_psql_2.vila.local "rm /tmp/to_master_approve"
  ssh root@ubuntu_psql_2.vila.local "iptables -D OUTPUT -d 192.168.216.210 -j DROP"
else
  ssh root@ubuntu_psql_2.vila.local "touch /tmp/to_master_approve"
  ssh root@ubuntu_psql_2.vila.local "iptables -A OUTPUT -d 192.168.216.210 -j DROP"
fi;
sleep 0.01
done
AUF


touch /etc/systemd/system/agent.service
cat > /etc/systemd/system/agent.service << AUF
[Unit]
Description = Agent on agent.lab.local
[Service]
RemainAfterExit=true
ExecStart=/bin/sh /home/skript/agent.sh
Type=simple
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
AUF

chmod +x /etc/systemd/system/agent.service

systemctl enable agent
systemctl restart agent
```

# Writing scripts
The `verify1.py` script verifies the operation of the database servers in the cluster and is installed on both servers in the cluster. The script's task is to detect the lack of communication with the Primary node and promote itself to Primary, as well as replicate data from the Primary node to StandBy.

# Connect to cluster
To simulate an external connection to the cluster, the script "main.py" was created

# PostreSQL failover cluster Load testing 
Load testing was implemented using the script load_test.py
- The script consists of several steps:
> Sending primary SQL `INSERT` queries; Shut down the PostgreSQL cluster's Primary server while sending SQL queries; Change the PostgreSQL cluster server's StandBy role to Primary; Send SQL queries to the new Primary server; preempt to reactivate the primary server if it becomes active again.