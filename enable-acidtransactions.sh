#! /bin/bash

HIVE_CUSTOM_LIBS=/usr/lib/customhivelibs
ACTIVEAMBARIHOST=headnodehost
AMBARICONFIGS_SH=/var/lib/ambari-server/resources/scripts/configs.py
PORT=8080

# Import the helper method module.
wget -O /tmp/HDInsightUtilities-v01.sh -q https://hdiconfigactions.blob.core.windows.net/linuxconfigactionmodulev01/HDInsightUtilities-v01.sh && source /tmp/HDInsightUtilities-v01.sh && rm -f /tmp/HDInsightUtilities-v01.sh
########################################
usage() {
    echo ""
    echo "Usage: sudo bash setupcustomhivelibs.sh <HIVE_LIBS_WASB_DIR>";
    echo "       [HIVE_LIBS_WASB_DIR]: Mandatory WASB directory where Hive additional jars are stored. This directory has to be accessible from the cluster. e.g. wasb://hivecontainer@mystorage.blob.core.windows.net/jars/"
    exit 132;
}

checkHostNameAndSetClusterName() {
    fullHostName=$(hostname -f)
    echo "fullHostName=$fullHostName"
    if [ `test_is_zookeepernode` == 1 ]; then
        echo  "Setting up Hive libraries only needs to run on headnode and workernode, exiting ..."
        exit 0
    fi
    CLUSTERNAME=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nprint ClusterManifestParser.parse_local_manifest().deployment.cluster_name" | python)
    if [ $? -ne 0 ]; then
        echo "[ERROR] Cannot determine cluster name. Exiting!"
        exit 133
    fi
    echo "Cluster Name=$CLUSTERNAME"
}

validateUsernameAndPassword() {
    coreSiteContent=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=get --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=core-site)
    if [[ $coreSiteContent == *"[ERROR]"* && $coreSiteContent == *"Bad credentials"* ]]; then
        echo "[ERROR] Username and password are invalid. Cannot connect to Ambari Server. Exiting!"
        exit 134
    fi
}

updateAmbariConfigs() {
    echo "Updating Ambari configurations"

    updateResult=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=set --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=hive-site -k "hive.support.concurrency" -v "true")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update hive-site. Exiting!"
        echo $updateResult
        exit 135
    fi 

    updateResult=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=set --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=hive-site -k "hive.compactor.initiator.on" -v "true")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update hive-site. Exiting!"
        echo $updateResult
        exit 135
    fi 

    updateResult=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=set --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=hive-site -k "hive.compactor.worker.threads" -v "1")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update hive-site. Exiting!"
        echo $updateResult
        exit 135
    fi 

    updateResult=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=set --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=hive-site -k "hive.txn.manager" -v "org.apache.hadoop.hive.ql.lockmgr.DbTxnManager")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update hive-site. Exiting!"
        echo $updateResult
        exit 135
    fi 

    updateResult=$(python $AMBARICONFIGS_SH --user=$USERID --password=$PASSWD --action=set --host=$ACTIVEAMBARIHOST --cluster=$CLUSTERNAME --config-type=hive-env -k "hive_txn_acid" -v "on")
    
    if [[ $updateResult != *"Tag:version"* ]] && [[ $updateResult == *"[ERROR]"* ]]; then
        echo "[ERROR] Failed to update hive-env. Exiting!"
        echo $updateResult
        exit 135
    fi
}

stopServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to stop service"
        exit 137
    fi
    SERVICENAME=$1
    echo "Stopping $SERVICENAME"
    curl -u $USERID:$PASSWD -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Stop Service for enabling Acid transactions"}, "Body": {"ServiceInfo": {"state": "INSTALLED"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME
}

startServiceViaRest() {
    if [ -z "$1" ]; then
        echo "Need service name to start service"
        exit 138
    fi
    sleep 5
    SERVICENAME=$1
    echo "Starting $SERVICENAME using a background process."
    nohup bash -c "sleep 90; curl -u $USERID:'$PASSWD' -i -H 'X-Requested-By: ambari' -X PUT -d '{\"RequestInfo\": {\"context\" :\"Start Service for enabling Acid transactions\"}, \"Body\": {\"ServiceInfo\": {\"state\": \"STARTED\"}}}' http://$ACTIVEAMBARIHOST:$PORT/api/v1/clusters/$CLUSTERNAME/services/$SERVICENAME" > /tmp/Start$SERVICENAME.out 2> /tmp/Start$SERVICENAME.err < /dev/null &
}

############### Start of script #########################
if [ "$(id -u)" != "0" ]; then
    echo "[ERROR] The script has to be run as root."
    usage
fi

USERID=$(echo -e "import hdinsight_common.Constants as Constants\nprint Constants.AMBARI_WATCHDOG_USERNAME" | python)

echo "USERID=$USERID"

PASSWD=$(echo -e "import hdinsight_common.ClusterManifestParser as ClusterManifestParser\nimport hdinsight_common.Constants as Constants\nimport base64\nbase64pwd = ClusterManifestParser.parse_local_manifest().ambari_users.usersmap[Constants.AMBARI_WATCHDOG_USERNAME].password\nprint base64.b64decode(base64pwd)" | python)

checkHostNameAndSetClusterName
validateUsernameAndPassword

echo "Updating Ambari configs and restarting services from primary headnode"
PRIMARYHEADNODE=`get_primary_headnode`
PRIMARY_HN_NUM=`get_primary_headnode_number`

#Check if values retrieved are empty, if yes, exit with error
if [[ -z $PRIMARYHEADNODE ]]; then
	echo "Could not determine primary headnode."
	exit 141
fi

if [[ -z "$PRIMARY_HN_NUM" ]]; then
	echo "Could not determine primary headnode number."
	exit 142
fi

fullHostName=$(hostname -f)
echo "fullHostName=$fullHostName. Lower case: ${fullHostName,,}"
echo "primary headnode=$PRIMARYHEADNODE. Lower case: ${PRIMARYHEADNODE,,}"

# if running on the primary head node then enable Acid transactions via Ambari 
if [ "${fullHostName,,}" == "${PRIMARYHEADNODE,,}" ]; then
    updateAmbariConfigs
    stopServiceViaRest HIVE
    stopServiceViaRest OOZIE
    startServiceViaRest HIVE
    startServiceViaRest OOZIE
fi

