#!/bin/bash 

# Variables
ELK_HOST=$1     # Sample "elk.sample.com:9200"
INDICES=$2      # Sample "filebeat-7.1.1-"
ALIAS=$3        # Sample "filebeat-7.1.1"
LOGFILE=/<path>/elk-reindex.`date +%Y%m%d%H%M%S`.log

# Main
LIST_INDICES=$(curl --silent "http://${ELK_HOST}/_cat/indices/${INDICES}?h=index" | sort -r)

# Reindex proccess
for INDEX in ${LIST_INDICES} ; do

    TOTAL_DOCS_START=$(curl --silent "http://${ELK_HOST}/_cat/indices/${INDEX}?h=docs.count")
    echo "Start: `date +%Y%m%d%H%M%S`"      >> ${LOGFILE}
    echo "Re-indexing indice: ${INDEX}"     >> ${LOGFILE}
    echo "Total docs: ${TOTAL_DOCS_START}"    >> ${LOGFILE}

    curl -XPOST "http://${ELK_HOST}/_reindex?wait_for_completion=true&pretty=true" -H "Content-Type: application/json" -d "{
        \"conflicts\": \"proceed\",
        \"source\": {
          \"index\": \"${INDEX}\"
        },
        \"dest\": {
         \"index\": \"${INDEX}-reindexed\"
        }
    }"

    while true ; do
        TOTAL_DOCS_END=$(curl --silent "http://${ELK_HOST}/_cat/indices/${INDEX}-reindexed?h=docs.count")   
        if [ ${TOTAL_DOCS_END} -ne ${TOTAL_DOCS_START} ] ; then
            echo "`date +%Y%m%d%H%M%S` - Waiting proccessing..."    > Waiting-Proccessing
            sleep 120
        else
            break
        fi
    done

    ALIASES_UPDATE=`curl -XPOST "http://${ELK_HOST}/_aliases" -H "Content-Type: application/json" -d "{
        \"actions\" : [
            { 
               \"add\" : { 
                  \"index\" : \"${INDEX}-reindexed\", 
                  \"alias\" : \"${ALIAS}\" 
                } 
            }
        ]
    }"`

    # Update the write alias
    if [ `echo ${ALIASES_UPDATE} | cut -d":" -f2 | cut -d"}" -f1` = "true" ] ; then
        echo "OK - Aliases update execution API: ${INDEX}-reindexed"      >> ${LOGFILE}
        ALIASES_UPDATE=0
    else
        echo "ERRO - Aliases update execution API: ${INDEX}-reindexed"    >> ${LOGFILE}
        exit 5
    fi

    # Retry executing the policy for an index
    ILM_RETRY=$(curl -XPOST "http://${ELK_HOST}/${INDEX}-reindexed/_ilm/retry" -H "Content-Type: application/json")

    if [ `echo ${ILM_RETRY} | cut -d":" -f2 | cut -d"}" -f1` = "true" ] ; then
        echo "OK - Retry policy execution API: ${INDEX}-reindexed"      >> ${LOGFILE}
        ILM_RETRY=0
    else
        echo "ERRO - Retry policy execution API: ${INDEX}-reindexed"    >> ${LOGFILE}
        exit 10
    fi

    echo "End: `date +%Y%m%d%H%M%S`"        >> ${LOGFILE}
    echo "Re-indexing indice: ${INDEX}"     >> ${LOGFILE}
    echo "Total docs: ${TOTAL_DOCS_END}"    >> ${LOGFILE}
    echo "--------------------------------" >> ${LOGFILE}

done
