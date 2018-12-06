#!/usr/bin/env ksh
PATH=/usr/local/bin:${PATH}
IFS_DEFAULT="${IFS}"

#################################################################################

#################################################################################
#
#  Variable Definition
# ---------------------
#
APP_NAME=$(basename $0)
APP_DIR=$(dirname $0)
APP_VER="1.0.1"
APP_WEB="http://www.sergiotocalini.com.ar/"
TIMESTAMP=`date '+%s'`

IPSEC_CONF="/etc/ipsec.conf"
CACHE_DIR="${APP_DIR}/tmp"
CACHE_TTL=1                                      # IN MINUTES
#
#################################################################################

#################################################################################
#
#  Load Oracle Environment
# -------------------------
#
[ -f ${APP_DIR}/${APP_NAME%.*}.conf ] && . ${APP_DIR}/${APP_NAME%.*}.conf

#
#################################################################################

#################################################################################
#
#  Function Definition
# ---------------------
#
usage() {
    echo "Usage: ${APP_NAME%.*} [Options]"
    echo ""
    echo "Options:"
    echo "  -a            Arguments to the section."
    echo "  -h            Displays this help message."
    echo "  -j            Jsonify output."
    echo "  -s            Select the section (service, account, etc. )."
    echo "  -v            Show the script version."
    echo ""
    echo "Please send any bug reports to sergiotocalini@gmail.com"
    exit 1
}

version() {
    echo "${APP_NAME%.*} ${APP_VER}"
    exit 1
}

zabbix_not_support() {
    echo "ZBX_NOTSUPPORTED"
    exit 1
}

refresh_cache() {
    params=( "${@}" )
    ttl="${CACHE_TTL}"

    name=`printf '%s/' "${params[@]}" 2>/dev/null`
    [[ -z ${name} ]] && name="config/"
    
    filename="${CACHE_DIR}/${name%?}.json"
    basename=`dirname ${filename}`
    [[ -d "${basename}" ]] || mkdir -p "${basename}"
    [[ -f "${filename}" ]] || touch -d "$(( ${ttl}+1 )) minutes ago" "${filename}"

    if [[ $(( `stat -c '%Y' "${filename}" 2>/dev/null`+60*${ttl} )) -le ${TIMESTAMP} ]]; then
	if [[ ${name} == "config/" ]]; then
            includes=`grep -E "^include .*" "${IPSEC_CONF}"`
            if [[ -n ${includes} ]]; then
               content=`grep -vE "^include .*" "${IPSEC_CONF}"`
               while read line; do
                  subcontent=`cat "$( echo "${line}" | awk '{print $2}')"`
                  content=`echo "${content}" ; echo "${subcontent}"`
               done < <(echo "${includes}")
            else
               content=`cat "${IPSEC_CONF}"`
            fi
            connections=`echo "${content}" | grep -E "^conn .*" | grep -vE "conn (%)" | awk '{print $2}'`
            raw="{ "
            while read conn_name; do
               raw+="\"${conn_name}\": { "
               while read line; do
                  key=`echo "${line}" | awk -F'=' '{print $1}'`
                  val=`echo "${line}" | awk -F'=' '{print $2}'`
                  raw+="\"${key}\":\"${val}\","
               done < <(echo "${content}" | sed -n "/^conn ${conn_name}/,/^(conn|config) .*/p" | grep -vE "^$|^#|^conn.*")
               raw="${raw%?}},"
            done < <(echo "${connections}")
            raw="${raw%?}}"
	elif [[ ${name} =~ (stats/.*/) ]]; then
            details=`sudo ipsec statusall "${params[1]}" | grep bytes_i`
            if [[ -n ${details} ]]; then
               bytes_in=`echo "${details}" | awk -F" " {'print $3'}`
               bytes_out=`echo "${details}" | awk -F" " {'print $9'}`
               pkts_in=`echo "${details}" | awk -F" " {'print $5'} | sed s/\(//`
               pkts_out=`echo "${details}" | awk -F" " {'print $11'} | sed s/\(//`
               raw="{"
               raw+="\"name\": \"${params[1]}\", \"stats\": {"
               raw+="\"bytes\": {\"in\": \"${bytes_in}\", \"out\": \"${bytes_out}\"},"
               raw+="\"pkts\": {\"in\": \"${pkts_in}\", \"out\": \"${pkts_out}\"} }"
               raw+="}"
            fi
	fi
	[[ -z ${raw} ]] || echo "${raw}" | jq . 2>/dev/null > "${filename}"
    fi
    echo "${filename}"
}


service() {
    params=( ${@} )
    
    if [[ ${params[0]} =~ (uptime|listen) ]]; then
	pid=`sudo lsof -Pi :${regex_match[6]:-${regex_match[2]}} -sTCP:LISTEN -t 2>/dev/null`
	rcode="${?}"
	if [[ -n ${pid} ]]; then
	    if [[ ${params[0]} == 'uptime' ]]; then
		res=`sudo ps -p ${pid} -o etimes -h 2>/dev/null | awk '{$1=$1};1'`
	    elif [[ ${params[0]} == 'listen' ]]; then
		[[ ${rcode} == 0 && -n ${pid} ]] && res=1
	    fi
	fi
    elif [[ ${params[0]} == 'version' ]]; then
	res=$( server 'info' 'entry[0].content.version' )
    elif [[ ${params[0]} == 'status' ]]; then
        res=$( server 'info' 'entry[0].content.version' )
        if ! [[ -z ${res} || ${res} == "0" ]]; then
            res="1"
        fi
    elif [[ ${params[0]} == 'connections' ]]; then
        filename=$( refresh_cache config )
	res=`jq . ${filename}`
    fi
    echo "${res:-0}"
    return 0
}

stats() {
    params=( ${@} )
    filename=$( refresh_cache stats ${params[0]} )
    [[ -n ${filename} ]] || zabbix_not_support 

    prop=`printf '.%s' "${params[@]:1}" 2>/dev/null`
    res=`jq -r ".stats${prop}" ${filename} 2>/dev/null`
    echo "${res//null}"
    return 0
}

status() {
    params=( ${@} )
    
    for json in ${APP_DIR}/${APP_NAME%.*}.conf.d/*.json; do
       attr_name=`jq -r ".name" ${json} 2>/dev/null`
       [[ ${params[0]} == ${attr_name} ]] || continue
       mon_hosts=`jq ".monitoring.hosts.[] | [.src, .dst, .port.[]] | join(\"|\")" ${json} 2>/dev/null`
       [[ -n ${mon_hosts} ]] && break
    done

    if [[ -n ${mon_hosts} ]]; then
       while read line; do
          nc_opt=( "-z -w 1" )
          src=`echo ${line} | awk -F'|' '{print $1}'`
          dst=`echo ${line} | awk -F'|' '{print $2}'`
          port=`echo ${line} | awk -F'|' '{print $3}'`
          [[ -n ${src//null} ]] && opt[${#nc_opt[@]}]="-s ${src}"
          nc ${nc_opt} ${dst} ${port}
          [[ ${?} == 0 ]] && res=1 && break
       done < <(echo "${mon_hosts}")
    else

    fi

    echo "${res//null:-0}"
    return 0
}
#
#################################################################################

#################################################################################
while getopts "s::a:sj:uphvt:" OPTION; do
    case ${OPTION} in
	h)
	    usage
	    ;;
	s)
	    SECTION="${OPTARG}"
	    ;;
        j)
            JSON=1
            IFS=":" JSON_ATTR=( ${OPTARG} )
	    IFS="${IFS_DEFAULT}"
            ;;
	a)
	    param="${OPTARG//p=}"
	    [[ -n ${param} ]] && ARGS[${#ARGS[*]}]="${param}"
	    ;;
	v)
	    version
	    ;;
        \?)
            exit 1
            ;;
    esac
done

if [[ "${SECTION}" == "service" ]]; then
    rval=$( service "${ARGS[@]}" )  
elif [[ "${SECTION}" == "status" ]]; then
    rval=$( status "${ARGS[@]}" )
elif [[ "${SECTION}" == "stats" ]]; then
    rval=$( stats "${ARGS[@]}" )
else
    zabbix_not_support
fi
rcode="${?}"

if [[ ${JSON} -eq 1 ]]; then
    echo '{'
    echo '   "data":['
    count=1
    while read line; do
	if [[ ${line} != '' ]]; then
            IFS="|" values=(${line})
            output='{ '
            for val_index in ${!values[*]}; do
		output+='"'{#${JSON_ATTR[${val_index}]:-${val_index}}}'":"'${values[${val_index}]}'"'
		if (( ${val_index}+1 < ${#values[*]} )); then
                    output="${output}, "
		fi
            done
            output+=' }'
	    if (( ${count} < `echo ${rval}|wc -l` )); then
		output="${output},"
            fi
            echo "      ${output}"
	fi
        let "count=count+1"
    done < <(echo "${rval}")
    echo '   ]'
    echo '}'
else
    echo "${rval:-0}"
fi

exit ${rcode}
