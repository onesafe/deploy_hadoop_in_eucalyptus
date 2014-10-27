#!/bin/bash

# script for starting a certain number of VM instances with EC2 client
# input: number of VMs requested, type of VMs, VM image ID, name of key to inject into the VMs
# output: successful or not; if sccessful, two files will be generated -- one containing the public IP addresses
#         of the VMs, and another one containing the LAN addresses of the VMs.
function print_usage {
    echo "Usage: -n NUM_OF_NODES -t NODE_TYPE -i IMAGE_ID -k KEY_NAME -h"
    echo "       -n: Number of VM instance nodes to start"
    echo "       -t: VM instance type"
    echo "       -i: VM image ID"
    echo "       -k: Name of the key that will be injected to the VM instances for remote access"
    echo "       -h: Print help"
}

# initialize arguments
NODES=""
NODE_TYPE=""
IMAGE_ID=""
KEY_NAME=""

# parse arguments
args=`getopt n:t:i:k:h $*`
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
	    NODES=$1
            shift;;

        -t) shift;
	    NODE_TYPE=$1
            shift;;

        -i) shift;
	    IMAGE_ID=$1
            shift;;

        -k) shift;
	    KEY_NAME=$1
	    	shift;;

        -h) shift;
	    print_usage
	    exit 0
    esac
done

if [ "$NODES" = "" ]; then
	print_usage
    exit 1
fi

echo "About to run the EC2 instances..."
euca-run-instances -k $KEY_NAME -n $NODES -t $NODE_TYPE $IMAGE_ID 2>&1 > tmpOut.txt

COUNT_PENDING=`tail -$NODES tmpOut.txt | grep pending | wc -l`
if [ "$COUNT_PENDING" != "$NODES" ]; then
	echo "Failed when calling euca-run-instances. Standard Error and Output:"
	cat tmpOut.txt
	exit 1
fi

while true
do
	echo "Wait for another minute to check the VM status..."
	sleep 60
	COUNT_RUNNING=`euca-describe-instances | grep running | wc -l`
	echo "COUNT_RUNNING=" $COUNT_RUNNING "NODES=" $NODES
	if [ $COUNT_RUNNING -eq $NODES ]; then
		echo "COUNT_RUNNING=" $COUNT_RUNNING "NODES=" $NODES
		break
	fi
done

euca-describe-instances | grep running > tmpOut.txt

cut -f2 tmpOut.txt > instanceIds.txt
cut -f4 tmpOut.txt > publicIps.txt
cut -f5 tmpOut.txt > nodes.txt
echo "All VMs are running. Information written to instanceIds.txt, publicIps.txt, and nodes.txt."

