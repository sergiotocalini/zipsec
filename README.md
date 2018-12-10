# zipsec
Zabbix Agent - IPSec

# Dependencies
## Packages
* ksh
* jq
* nc (optional with extra monitoring config)

__**Debian/Ubuntu**__

```
#~ sudo apt install ksh jq nc
#~
```
__**Red Hat**__
```
#~ sudo yum install ksh jq nc
#~
```
# Deploy
Default variables:

NAME|VALUE
----|-----
IPSEC_CONF|/etc/ipsec.conf
CACHE_DIR|<empty>
CACHE_TTL|<empty>

*Note: this variables has to be saved in the config file (zipsec.conf) in the same directory than the script.*

## Zabbix
```
#~ git clone https://github.com/sergiotocalini/zipsec.git
#~ sudo ./zipsec/deploy_zabbix.sh "<IPSEC_CONF>" "<CACHE_DIR>" "<CACHE_TTL>"
#~ sudo systemctl restart zabbix-agent
``` 
*Note: the installation has to be executed on the zabbix agent host and you have to import the template on the zabbix web. The default installation directory is /etc/zabbix/scripts/agentd/zipsec*

# Configuration
We can specified some extra commands to detect if the connection is alive.
For example:
```
~# cat /etc/zabbix/scripts/agentd/zipsec/zipsec.conf.d/example.json.save
{
  "name": "example",
  "monitoring": {
    "commands": [
      "nc -zv -w 1 -s 192.168.0.1 10.0.20.100 80 443",
      "nc -zv -w 1 -s 192.168.0.2 10.0.30.100 80 443"
    ]
  }
}
~# 
```
