#!/bin/bash
# /usr/local/bin/voltha.sh
# TODO: Validate User ID 
# 		Cleanup temp folder
# 		Add Testing Capability for PONSIM
#		Add Log Interface

CURRENT_USER=`whoami`

if [[ "$CURRENT_USER" != "opencord" ]]; then
	echo "Process must be run by opencord"
	exit 1
fi


cd /cord/incubator/voltha
. env.sh

function v_start()
{
	if [ -f /usr/local/bin/voltha/voltha.lock ]; then
		echo "VOLTHA is already running"
		exit 1
	fi
	echo  "VOLTHA: Starting Consul Service"
	docker-compose -f compose/docker-compose-system-test.yml up -d consul

	echo "VOLTHA: Setting Consul IP"
	CONSUL_IP=`docker inspect compose_consul_1 | \
			jq -r '.[0].NetworkSettings.Networks.compose_default.IPAddress'` && echo $CONSUL_IP

	export CONSUL_IP

	echo "VOLTHA: Starting up Containers"
	docker-compose -f compose/docker-compose-system-test.yml up -d
	docker-compose -f compose/docker-compose-auth-test.yml up -d onos
	touch  /usr/local/bin/voltha/voltha.lock
}

function v_getlinks() 
{
	CHAMELEON_PORT=`docker inspect compose_chameleon_1 | \
		jq -r '.[0].NetworkSettings.Ports["8881/tcp"][0].HostPort'`
	
		
	echo "Consul: http://localhost:8500/ui/"
	echo "Swagger: http://localhost:$CHAMELEON_PORT/#/VolthaLocalService"
	echo "Graphana: http://localhost/grafana  user: admin password: admin"
	echo "ONOS: http://localhost:8181/onos/ui  user: onos password: rocks"
}

function v_stop()
{
	echo  "VOLTHA: Stopping Service"
	docker-compose -f compose/docker-compose-system-test.yml stop
	docker-compose -f compose/docker-compose-system-test.yml rm -f
	
	docker-compose -f compose/docker-compose-auth-test.yml stop
	docker-compose -f compose/docker-compose-auth-test.yml rm -f
	
	#TODO Make sure everything is gone
	rm /usr/local/bin/voltha/voltha.lock
}

function v_status()
{
	echo "Docker Process State"
	docker-compose -f compose/docker-compose-system-test.yml ps
	docker-compose -f compose/docker-compose-auth-test.yml ps
	
	echo "Getting Chameleon Port"
	CHAMELEON_PORT=`docker inspect compose_chameleon_1 | \
		jq -r '.[0].NetworkSettings.Ports["8881/tcp"][0].HostPort'`
	echo "Chameleon Port: $CHAMELEON_PORT"
	VOLTHAURL="http://localhost:$CHAMELEON_PORT/api/v1/local"
	echo "VOLTHA URL: $VOLTHAURL"
	echo "Checking Health"
	curl -s $VOLTHAURL/health | jq '.'
	echo "Checking Adapters"
	curl -s $VOLTHAURL/adapters | jq '.'
}

function v_kafkacat() 
{	
	KAFKA_PORT=`docker inspect compose_kafka_1 | \
		jq -r '.[0].NetworkSettings.Ports["9092/tcp"][0]["HostPort"]'`
	echo "Kafka Port: $KAFKA_PORT"
	echo "Kafka Queues:"
	kafkacat -b localhost:$KAFKA_PORT -L	
	echo "Kafka Heartbeats"
	kafkacat -e -b localhost:$KAFKA_PORT -C -t voltha.heartbeat \
		-f 'Topic %t [%p] at offset %o: key %k: %s\n'
	echo "Kafka KPIs"
	kafkacat -e -b localhost:$KAFKA_PORT -C -t voltha.kpis \
		-f 'Topic %t [%p] at offset %o: key %k: %s\n'
}

function v_test() 
{
	if [ -f /usr/local/bin/voltha/ponsim.pid ]; then
		echo "Test is already running"
		exit 0
	fi
	sudo su
	cd /cord/incubator/voltha
	. env.sh
	./ponsim/main.py -q -o 4 &
	echo ps -efa |grep "python ./ponsim/main.py" | awk '{ print $2 }' > /usr/local/bin/voltha/ponsim.pid
	
	echo "Bridge Control Response"
	brctl show ponmgmt
	echo "Setting up test"
	cat /usr/local/bin/voltha/test.txt |./cli/main.py -L
	su - opencord
	exit 0
}

function v_stoptest()
{
	echo "Stopping Test"
	
	sudo kill -9 `ps -efa |grep "python ./ponsim/main.py" | awk '{ print $2 }'` 2>/dev/null
	if [ -f /usr/local/bin/voltha/ponsim.pid ]; then
		rm /usr/local/bin/voltha/ponsim.pid
	fi
	PID_COUNT=`ps -efa |grep "python ./ponsim/main.py" | awk '{ print $2 }' | wc -l`
	if [ $PID_COUNT -eq 1 ]; then
		echo "Successfully stopped the test"
	else
		echo "Failed to stop test"
	fi
	exit 0
}

function v_installservice() 
{ 
	echo "Not implemented"
	exit 0
	
	sudo cp /usr/local/bin/voltha/voltha.service /etc/systemd/system/
	sudo systemctl daemon-reload
	sudo systemctl enable voltha.service
	sudo systemctl start voltha
}

function v_clean()
{
	rm -rdf /tmp/fluentd /usr/local/bin/voltha/voltha.lock /usr/local/bin/voltha/ponsim.pid
}

function v_onos()
{
	sshpass -p karaf ssh -o StrictHostKeyChecking=no -p 8101 karaf@localhost
}


case  "$1"  in
	start)
			v_start
			v_getlinks
			;;
	stop)
			v_stop
			;;
	reload)
			v_stop
			sleep  1
			v_start
			;;
	test)
			v_test
			;;
	stoptest)
			v_stoptest
			;;
	installservice)
			v_installservice
			;;
	clean)
			v_stoptest
			sleep 1
			v_stop
			sleep 1
			v_clean
			;;
	status)
			v_status
			;;
	kafkacat)
			v_kafkacat
			;;
	onos)
			v_onos
			;;
	getlinks)
			v_getlinks
			;;
	*)
			cat /usr/local/bin/voltha/voltha.man
			exit  1
			;;
esac

exit  0

