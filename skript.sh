#!/bin/bash
#Connect to SQL2
ssh root@sql1.lab.local << EOF
apt-get update
apt-get install -y curl gnupg2
echo "deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt/ stretch-pgdg main" > /etc/apt/sources.list.d/pgdg.list
curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-10
sed -i 's/local   all             postgres                                peer/local   all             postgres                                trust/' /etc/postgresql/10/main/pg_hba.conf
service postgresql restart
#################################################
#   CREATE 				DATABASE		        #
#################################################
psql -U postgres -c "CREATE DATABASE master;"
psql   -d master  -c "CREATE TABLE master (name varchar(80), surname varchar(80));"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('Roman', 'Masyagutov');"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('Konstantin','Ruzavin');"
psql -U postgres -d master  -c "INSERT INTO master (name, surname) VALUES ('Ira', 'Bilyavshuk');"

#Create user replica for replication
psql -U postgres -c "CREATE USER replica REPLICATION LOGIN CONNECTION LIMIT 2 ENCRYPTED PASSWORD '123456pass';"
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



#Connect to SQL2
ssh root@sql2.lab.local << EOF
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


#make agent
mkdir /home/skript
cat > /home/skript/agent.sh << AUF
#!/bin/bash
while :
do
if pg_isready -h sql1.lab.local; then
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
Description = Agent on sql2.lab.local
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



#make agent service
mkdir /home/skript
cat > /home/skript/agent.sh << AUF
#!/bin/bash
while :
do
if pg_isready -h sql1.lab.local; then
  echo "200 OK NE GOVORY, POLUCHAY 501, 503"
  ssh root@sql2.lab.local "rm /tmp/to_master_approve"
  ssh root@sql2.lab.local "iptables -D OUTPUT -d 192.168.216.210 -j DROP"
else
  ssh root@sql2.lab.local "touch /tmp/to_master_approve"
  ssh root@sql2.lab.local "iptables -A OUTPUT -d 192.168.216.210 -j DROP"
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
