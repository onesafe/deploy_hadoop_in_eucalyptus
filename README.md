deploy_hadoop_in_eucalyptus
===========================


该shell脚本用于在eucalyptus云平台中部署hadoop

开启虚拟机，个数为3个，其中第一个为master，另外两个为slave

个数可自己设定，如果为4，则第一个为master，另外三个为slave

m1.medium为虚拟机的类型，emi-27E541EE为上传到eucalyptus的linux镜像，wyp-keypair是秘钥

./start-instances.sh -n 3 -t m1.medium  -i emi-27E541EE  -k wyp-keypair 

./deploy-hadoop.sh -n nodes.txt -p publicIps.txt -k wyp-keypair.private

运行后查看jps各个进程都正确，将nodes.txt内容拷贝到本地/etc/hosts中

此时可以通过浏览器master:50030和master:50070来访问hadoop
