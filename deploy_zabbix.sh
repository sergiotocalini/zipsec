#!/usr/bin/env ksh
SOURCE_DIR=$(dirname $0)
ZABBIX_DIR=/etc/zabbix
PREFIX_DIR="${ZABBIX_DIR}/scripts/agentd/zipsec"

IPSEC_CONF="${1:-/etc/ipsec.conf}"
CACHE_DIR="${4:-${PREFIX_DIR}/tmp}"
CACHE_TTL="${5:-5}"

mkdir -p "${PREFIX_DIR}"

SCRIPT_CONFIG="${PREFIX_DIR}/zipsec.conf"
if [[ -f "${SCRIPT_CONFIG}" ]]; then
    SCRIPT_CONFIG="${SCRIPT_CONFIG}.new"
fi

cp -rpv "${SOURCE_DIR}/zipsec/zipsec.sh"             "${PREFIX_DIR}/"
cp -rpv "${SOURCE_DIR}/zipsec/zipsec.conf.d"         "${PREFIX_DIR}/"
cp -rpv "${SOURCE_DIR}/zipsec/zipsec.conf.example"   "${SCRIPT_CONFIG}"
cp -rpv "${SOURCE_DIR}/zipsec/zabbix_agentd.conf"    "${ZABBIX_DIR}/zabbix_agentd.d/zipsec.conf"

regex_array[0]="s|IPSEC_CONF=.*|IPSEC_CONF=\"${IPSEC_CONF}\"|g"
regex_array[1]="s|CACHE_DIR=.*|CACHE_DIR=\"${CACHE_DIR}\"|g"
regex_array[2]="s|CACHE_TTL=.*|CACHE_TTL=\"${CACHE_TTL}\"|g"
for index in ${!regex_array[*]}; do
    sed -i "${regex_array[${index}]}" ${SCRIPT_CONFIG}
done
