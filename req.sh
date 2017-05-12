#!/bin/bash

domainname=$(dig www.landro.io. CNAME +short)
domainname=${domainname%?}
# Send SNI servername to make arukas beta happy 
(cat req.http ; sleep 2) | openssl s_client -quiet -crlf -servername "$domainname" -connect www.landro.io:443 | head -n 20