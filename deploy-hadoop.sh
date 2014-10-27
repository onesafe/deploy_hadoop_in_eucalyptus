#!/bin/bash

# script for deploying Hadoop on an existing virtual cluster of VMs
# input: the public and LAN IP addresses of the VMs
# output: successful or not;
function print_usage {
    echo "Usage: -n NODES_PATH -p IP_PATH -k KEY_PATH -l SALSA_HADOOP_LINK -h"
    echo "       -n: Path to the 'nodes' file, which is supposed to contain the VMs' LAN IP addresses."
    echo "       -p: Path to the file containing VMs' IP addresses. Lines of this file should correspond to lines of the 'nodes' file by VMs."
    echo "       -k: Path to the private key file that will be used to ssh to each VM."
	echo "       -h: Print help"
}

# initialize arguments
NODES_PATH="nodes.txt"
IP_PATH="publicIps.txt"
KEY_PATH=""

# parse arguments
args=`getopt n:p:k:l:h $*`
if test $? != 0
then
    print_usage
    exit 1
fi
set -- $args
for i
do
    case "$i" in
        -n) shift;
	    NODES_PATH=$1
            shift;;

        -p) shift;
	    IP_PATH=$1
            shift;;

	-k) shift;
		KEY_PATH=$1
		shift;;

        -h) shift;
	    print_usage
	    exit 0
    esac
done

echo "Generating the 'hosts' file containing the LAN IP addresses and hostnames of all VMs..."
touch hosts
touch masters
touch slaves
touch authorized_keys
let COUNT=0
while read LINE
do
	if [ $COUNT -eq 0 ]; then
		NEWLINE="$LINE master"
		echo $LINE > masters
		echo $NEWLINE > hosts
	else
		NEWLINE="$LINE slave$COUNT"
		echo $NEWLINE >> hosts
		echo $LINE >> slaves
	fi
	let COUNT="$COUNT+1"
done < $NODES_PATH

if [ $? -ne 0 ]; then
	echo "Error when processing $NODES_PATH and generating file hosts."
	exit $?
fi

paste -d" " $IP_PATH hosts > ipHosts.txt

if [ $? -ne 0 ]; then
	echo "Error when generating file ipHosts.txt."
	exit $?
fi

echo "Configuring Hadoop on all VMs..."
WHOLE=""
FIRST=true
while read LINE
do
	echo $LINE
	if $FIRST; then
		WHOLE=$LINE
		FIRST=false
	else
		WHOLE="$WHOLE	$LINE"
	fi
done < ipHosts.txt

echo "WHOLE = " $WHOLE

#configure /etc/sysconfig/network, mapred-site.xml, core-site.xml, /etc/hosts, masters, slaves
#get authorizen_keys from echo nodes 
let COUNT=1
LINE=`echo "$WHOLE" | cut -f$COUNT`
export MASTER_IP=`echo $LINE | cut -d' ' -f1`
export PRIVATE_IP=`echo $LINE | cut -d' ' -f2`
echo "MASTER_IP = " $MASTER_IP
while [ "$LINE" != "" ]
do
	echo "$LINE"
	IP=`echo $LINE | cut -d' ' -f1`
	HOSTNAME=`echo $LINE | cut -d' ' -f3`
	
	echo "Configuring $IP..."
	echo "Set up hostname $HOSTNAME..."
	ssh -i $KEY_PATH root@$IP hostname $HOSTNAME
	ssh -i $KEY_PATH root@$IP sed -i 's/HOSTNAME=.*/HOSTNAME='"$HOSTNAME"'/g' /etc/sysconfig/network
	ssh -i $KEY_PATH root@$IP ls -l /usr/local/hadoop/conf/core-site.xml /usr/local/hadoop/conf/mapred-site.xml
	ssh -i $KEY_PATH root@$IP sed -i 's/hadoop:9000/'"$PRIVATE_IP"':9000/g' /usr/local/hadoop/conf/core-site.xml
	ssh -i $KEY_PATH root@$IP sed -i 's/hadoop:9001/'"$PRIVATE_IP"':9001/g' /usr/local/hadoop/conf/mapred-site.xml

	Exist=`ssh -i $KEY_PATH root@$IP  grep $HOSTNAME /root/.ssh/id_rsa.pub | wc -l`
	if [ $Exist -eq 1 ]; then	
		ssh -i $KEY_PATH root@$IP "cd /root/.ssh; rm -f known_hosts;"
	else
		ssh -i $KEY_PATH root@$IP "cd /root/.ssh; rm -f id_rsa.pub id_rsa known_hosts; ssh-keygen -t rsa"
	fi

	scp -i $KEY_PATH hosts root@$IP:/etc/hosts
	scp -i $KEY_PATH masters root@$IP:/usr/local/hadoop/conf/masters
	scp -i $KEY_PATH slaves root@$IP:/usr/local/hadoop/conf/slaves

	ssh -i $KEY_PATH root@$IP "cd /root/.ssh; ls authorized_keys.bak || cp  authorized_keys authorized_keys.bak"
	scp -i $KEY_PATH root@$IP:/root/.ssh/authorized_keys.bak tmp_keys
	cat tmp_keys
	cat tmp_keys >> authorized_keys
	echo -e "" >> authorized_keys
	scp -i $KEY_PATH root@$IP:/root/.ssh/id_rsa.pub tmp_keys
	cat tmp_keys
        cat tmp_keys >> authorized_keys
	echo -e "" >> authorized_keys
	sort -u authorized_keys > authorized_keys.tmp

	ssh -i $KEY_PATH root@$IP df -h

	let COUNT="$COUNT+1"
	LINE=`echo "$WHOLE" | cut -f$COUNT`
done
let COUNT="$COUNT-2"
echo "COUNT= " $COUNT

if [ $? -ne 0 ]; then
	echo "Error when downloading Hadoop on all VMs."
	exit $?
fi


#loop once again, configure hadoop conf hdfs-site.xml, ssh no-password login
let iCOUNT=1
LINE=`echo "$WHOLE" | cut -f$iCOUNT`
while [ "$LINE" != "" ]
do
        echo "$LINE"
	PRIVATE_IP=`echo $LINE | cut -d' ' -f2`
	IP=`echo $LINE | cut -d' ' -f1`
	ssh -i $KEY_PATH root@$IP sed -i 's/2/'"$COUNT"'/g' /usr/local/hadoop/conf/hdfs-site.xml	

	scp -i $KEY_PATH authorized_keys.tmp  root@$IP:/root/.ssh/authorized_keys 
	ssh -i $KEY_PATH root@$IP "/etc/init.d/sshd restart; sleep 3"
	echo -e "-------------------------------------------------------------------"
	echo -e "" 
	echo -e "             WARNING  *******************  WARINING                "
	echo -e "          Please input yes to first login $PRIVATE_IP" 
	echo -e "     And exit to finish deploy hadoop when you login  $PRIVATE_IP"
	echo -e ""
	echo -e "-------------------------------------------------------------------" 
	ssh -i $KEY_PATH -t -t  root@$MASTER_IP  "ssh   $PRIVATE_IP "

        let iCOUNT="$iCOUNT+1"
        LINE=`echo "$WHOLE" | cut -f$iCOUNT`
done

#rm some temp file
cat authorized_keys.tmp
rm -f authorized_keys
rm -f authorized_keys.tmp
rm -f tmp_keys
rm -f slaves

#start hadoop
ssh -i $KEY_PATH root@$MASTER_IP "cd /usr/local/hadoop/bin; pwd; source /etc/profile; cd /home/wyp; rm -rf tmp;  hadoop namenode -format; start-all.sh "


#check hadoop is running well
let iCOUNT=1
LINE=`echo "$WHOLE" | cut -f$iCOUNT`
while [ "$LINE" != "" ]
do
        echo "$LINE"
        IP=`echo $LINE | cut -d' ' -f1`
        ssh -i $KEY_PATH root@$IP "source /etc/profile; jps"
        let iCOUNT="$iCOUNT+1"
        LINE=`echo "$WHOLE" | cut -f$iCOUNT`
done
