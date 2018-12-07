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
		active=0
		raw+="\"${conn_name}\": { "
		while read line; do
                    key=`echo "${line}" | awk -F'=' '{print $1}'`
                    val=`echo "${line}" | awk -F'=' '{print $2}'`
                    raw+="\"${key}\":\"${val}\","
                    if [[ ${key} == "left" ]]; then
			ip addr list | grep "${val}" > /dev/null 2>&1
			[[ ${?} == 0 ]] && active=1
                    fi
		done < <(echo "${content}" | sed -n "/^conn ${conn_name}/,/^(conn|config) .*/p" | grep -vE "^$|^#|^conn.*")
		raw="${raw%?}, \"active\": \"${active}\"},"
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
    if [[ ${params[0]} =~ (uptime|status) ]]; then
	pid=`ps -ef 2>/dev/null| grep "ipsec/starter" | grep -v "grep" | awk '{print $2}'`
	if [[ -n ${pid} ]]; then
	    if [[ ${params[0]} == 'uptime' ]]; then
		res=`sudo ps -p ${pid} -o etimes -h 2>/dev/null | awk '{$1=$1};1'`
	    elif [[ ${params[0]} == 'status' ]]; then
		res=1
	    fi
	fi
    elif [[ ${params[0]} == 'version' ]]; then
	res=`ipsec version 2>/dev/null | head -1 | awk -F'/' '{print $1}' | sed 's:Linux ::'`
    elif [[ ${params[0]} == 'connections' ]]; then
        filename=$( refresh_cache config )
        while read conn_name; do
            [[ -n ${conn_name} ]] || continue
            res[${#res[@]}]=$( conn_info "${conn_name}" )
        done < <(jq -r "keys[]" ${filename} 2>/dev/null)
    fi
    printf '%s\n' "${res[@]}"
    return 0
}

conn_info() {
    params=( ${@} )
    filename=$( refresh_cache config )
    [[ -n ${filename} ]] || zabbix_not_support

    res="${params[0]}"
    if [[ ${#params[@]} > 1 ]]; then
	props=`printf '.%s,' "${params[@]:1}" 2>/dev/null`
    else
	props=".name,.active,.type,.auto,.lifetime,.left,.leftsubnet,.right,.rightsubnet,"
    fi
    res+=`jq -r ".\"${params[0]}\" | [ ${props%?} ] | join(\"|\")" "${filename}" 2>/dev/null`
    echo "${res}"
    return 0
}

conn_stats() {
    params=( ${@} )
    filename=$( refresh_cache stats ${params[0]} )
    [[ -n ${filename} ]] || zabbix_not_support 

    prop=`printf '%s.' "${params[@]:1}" 2>/dev/null`
    [[ -n ${prop%?} ]] && prop=".stats.${prop%?}"
    res=`jq -r "${prop}" ${filename} 2>/dev/null`
    echo "${res//null}"
    return 0
}

conn_status() {
    params=( ${@} )
    
    for json in ${APP_DIR}/${APP_NAME%.*}.conf.d/*.json; do
	attr_name=`jq -r ".name" ${json} 2>/dev/null`
	[[ ${params[0]} == ${attr_name} ]] || continue
	mon_cmds=`jq -r ".monitoring.commands[]" ${json} 2>/dev/null`
	[[ -n ${mon_cmds} ]] && break
    done

    if [[ -n ${mon_cmds} ]]; then
	while read line; do
            output=`${line} 2>/dev/null`
            [[ ${?} == 0 ]] && res=1 && break
	done < <(echo "${mon_cmds}")
    fi

    if [[ ${res} != 1 ]]; then
	filename=$( refresh_cache config )
	json=`jq -r ".\"${params[0]}\"" "${filename}" 2>/dev/null`
	if [[ -n ${json} ]]; then
            right=`echo "${json}" | jq -r ".right" 2>/dev/null`
            left=`echo "${json}" | jq -r ".left" 2>/dev/null`
            if [[ -n ${right//null} && -n ${left//null} ]]; then
		output=`sudo ip xfrm state`
		echo "${output}" | grep -E "src ${left} dst ${right}" > /dev/null 2>&1
		src_dst="${?}"
		echo "${output}" | grep -E "src ${right} dst ${left}" > /dev/null 2>&1
		dst_src="${?}"
		[[ ${src_dst} == 0 && ${dst_src} == 0 ]] && res=1
            fi
	fi
    fi

    if [[ ${res} != 1 ]]; then
	ipsec statusall "${params[0]}" | grep -e "INSTALLED" > /dev/null 2>&1
	[[ ${?} == 0 ]] && res=1
    fi

    echo "${res//null/:-0}"
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
elif [[ "${SECTION}" == "conn" ]]; then
    if [[ ${ARGS[0]} == "status" ]]; then
	rval=$( conn_status "${ARGS[@]:1}" )
    elif [[ ${ARGS[0]} == "stats" ]]; then
	rval=$( conn_stats "${ARGS[@]:1}" )
    elif [[ ${ARGS[0]} == "info" ]]; then
	rval=$( conn_info "${ARGS[@]:1}" )
    fi
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
