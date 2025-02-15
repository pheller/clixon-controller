#!/usr/bin/env bash
#
# Simple non-python service checking shared object create and delete
#
# see https://github.com/SUNET/snc-services/issues/12
#
# Assume a testA(1) --> testA(2) and a testB and a non-service 0
# where
# testA(1):  Ax, Ay, ABx, ABy
# testA(2)2: Ay, Az, ABy, ABz
# testB:     ABx, ABy, ABz, Bx
#
# Algoritm: Clear actions
#
# Operations shown below, all others keep:
# +------------------------------------------------+
# |                       0x                       |
# +----------------+---------------+---------------+
# |     A0x        |      A0y      |      A0z      |
# +----------------+---------------+---------------+
# |     Ax         |      Ay       |      Az       |
# |    (delete)    |               |     (add)     |
# +----------------+---------------+---------------+
# |     ABx        |      ABy      |      ABz      |
# +----------------+---------------+---------------+
# |                       Bx                       |
# +------------------------------------------------+
set -eu

# Magic line must be first in script (see README.md)
s="$_" ; . ./lib.sh || if [ "$s" = $0 ]; then exit 0; else return 0; fi

if [ $nr -lt 2 ]; then
    echo "Test requires nr=$nr to be greater than 1"
    if [ "$s" = $0 ]; then exit 0; else return 0; fi
fi

dir=/var/tmp/$0
if [ ! -d $dir ]; then
    mkdir $dir
fi
CFG=$dir/controller.xml
fyang=$dir/myyang.yang

cat<<EOF > $CFG
<clixon-config xmlns="http://clicon.org/config">
  <CLICON_CONFIGFILE>/usr/local/etc/controller.xml</CLICON_CONFIGFILE>
  <CLICON_FEATURE>ietf-netconf:startup</CLICON_FEATURE>
  <CLICON_FEATURE>clixon-restconf:allow-auth-none</CLICON_FEATURE>
  <CLICON_CONFIG_EXTEND>clixon-controller-config</CLICON_CONFIG_EXTEND>
  <CONTROLLER_ACTION_COMMAND xmlns="http://clicon.org/controller-config">/usr/local/bin/services_action -f $CFG -D 0 -ls</CONTROLLER_ACTION_COMMAND> <!-- Debug: -D 3 -l s -->
  <CLICON_BACKEND_USER>clicon</CLICON_BACKEND_USER>
  <CLICON_SOCK_GROUP>clicon</CLICON_SOCK_GROUP>
  <CLICON_YANG_DIR>/usr/local/share/clixon</CLICON_YANG_DIR>
  <CLICON_YANG_MAIN_DIR>$dir</CLICON_YANG_MAIN_DIR>
  <CLICON_CLI_MODE>operation</CLICON_CLI_MODE>
  <CLICON_CLI_DIR>/usr/local/lib/controller/cli</CLICON_CLI_DIR>
  <CLICON_CLISPEC_DIR>/usr/local/lib/controller/clispec</CLICON_CLISPEC_DIR>
  <CLICON_BACKEND_DIR>/usr/local/lib/controller/backend</CLICON_BACKEND_DIR>
  <CLICON_SOCK>/usr/local/var/controller.sock</CLICON_SOCK>
  <CLICON_BACKEND_PIDFILE>/usr/local/var/controller.pidfile</CLICON_BACKEND_PIDFILE>
  <CLICON_XMLDB_DIR>$dir</CLICON_XMLDB_DIR>
  <CLICON_STARTUP_MODE>init</CLICON_STARTUP_MODE>
  <CLICON_STREAM_DISCOVERY_RFC5277>true</CLICON_STREAM_DISCOVERY_RFC5277>
  <CLICON_RESTCONF_USER>www-data</CLICON_RESTCONF_USER>
  <CLICON_RESTCONF_PRIVILEGES>drop_perm</CLICON_RESTCONF_PRIVILEGES>
  <CLICON_RESTCONF_INSTALLDIR>/usr/local/sbin</CLICON_RESTCONF_INSTALLDIR>
  <CLICON_VALIDATE_STATE_XML>true</CLICON_VALIDATE_STATE_XML>
  <CLICON_CLI_HELPSTRING_TRUNCATE>true</CLICON_CLI_HELPSTRING_TRUNCATE>
  <CLICON_CLI_HELPSTRING_LINES>1</CLICON_CLI_HELPSTRING_LINES>
  <CLICON_YANG_SCHEMA_MOUNT>true</CLICON_YANG_SCHEMA_MOUNT>
  <autocli>
     <module-default>true</module-default>
     <list-keyword-default>kw-nokey</list-keyword-default>
     <treeref-state-default>true</treeref-state-default>
     <grouping-treeref>true</grouping-treeref>
     <rule>
       <name>include controller</name>
       <module-name>clixon-controller</module-name>
       <operation>enable</operation>
     </rule>
     <rule>
       <name>include example</name>
       <module-name>clixon-example</module-name>
       <operation>enable</operation>
     </rule>
     <rule>
       <name>include junos</name>
       <module-name>junos-conf-root</module-name>
       <operation>enable</operation>
     </rule>
     <rule>
       <name>include arista system</name>
       <module-name>openconfig-system</module-name>
       <operation>enable</operation>
     </rule>
     <rule>
       <name>include arista interfaces</name>
       <module-name>openconfig-interfaces</module-name>
       <operation>enable</operation>
     </rule>
     <!-- there are many more arista/openconfig top-level modules -->
  </autocli>
</clixon-config>
EOF

cat <<EOF > $fyang
module myyang {
    yang-version 1.1;
    namespace "urn:example:test";
    prefix test;
    import ietf-inet-types {
      prefix inet;
    }
    import clixon-controller {
      prefix ctrl;
    }
    revision 2023-03-22{
	description "Initial prototype";
    }
    augment "/ctrl:services" {
	list testA {
	    key name;
	    leaf name {
		description "Not used";
		type string;
	    }
	    description "Test service A";
	    leaf-list params{
	       type string;
	   } 
	}
    }
    augment "/ctrl:services" {
	list testB {
	    key name;
	    leaf name {
		type string;
	    }
	    description "Test service B";
	    leaf-list params{
	       type string;
	    }
	}
    }
}
EOF

# Disable services process if you run a separate services_action process for debugging
cat <<EOF > $dir/startup_db
<config>
  <processes xmlns="http://clicon.org/controller">
    <services>
      <enabled>false</enabled> // true
    </services>
  </processes>
</config>
EOF

# Reset devices with initial config
. ./reset-devices.sh

if $BE; then
    echo "Kill old backend $CFG"
    sudo clixon_backend -f $CFG -z

    echo "Start new backend -s init -f $CFG -D $DBG"
    sudo clixon_backend -s init -f $CFG -D $DBG
fi

# Check backend is running
wait_backend

# Reset controller
. ./reset-controller.sh

DEV2="<device>
           <name>clixon-example2</name>
	   <config>
	     <table xmlns=\"urn:example:clixon\">
	       <parameter>
		 <name>0x</name>
	       </parameter>
	       <parameter>
		 <name>A0x</name>
	       </parameter>
	       <parameter>
		 <name>A0y</name>
	       </parameter>
	       <parameter>
		 <name>A0z</name>
	       </parameter>
	     </table>
	   </config>
	 </device>"

new "edit testA(1)"
ret=$(${clixon_netconf} -0 -f $CFG <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
   <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
   </capabilities>
</hello>]]>]]>
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
     xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
     message-id="42">
  <edit-config>
    <target><candidate/></target>
    <default-operation>none</default-operation>
    <config>
       <services xmlns="http://clicon.org/controller">
	  <testA xmlns="urn:example:test" nc:operation="replace">
	     <name>foo</name>
	     <params>A0x</params>
	     <params>A0y</params>
	     <params>Ax</params>
	     <params>Ay</params>
	     <params>ABx</params>
	     <params>ABy</params>
	 </testA>
	  <testB xmlns="urn:example:test" nc:operation="replace">
	     <name>foo</name>
	     <params>A0x</params>
	     <params>A0y</params>
	     <params>ABx</params>
	     <params>ABy</params>
	     <params>ABz</params>
	     <params>Bx</params>
	 </testB>
      </services>
      <devices xmlns="http://clicon.org/controller">
         <device>
           <name>clixon-example1</name>
           <config>
             <table xmlns="urn:example:clixon">
               <parameter>
                 <name>0x</name>
               </parameter>
               <parameter>
                 <name>A0x</name>
               </parameter>
               <parameter>
                 <name>A0y</name>
               </parameter>
               <parameter>
                 <name>A0z</name>
               </parameter>
             </table>
           </config>
         </device>
         $DEV2
      </devices>
    </config>
  </edit-config>
</rpc>]]>]]>
EOF
      )

echo "$ret"
match=$(echo "$ret" | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected"
    exit 1
fi

sleep $sleep
new "commit push"
set +e

expectpart "$(${clixon_cli} -m configure -1f $CFG commit push 2>&1)" 0 OK --not-- Error

new "edit testA(2)"
ret=$(${clixon_netconf} -0 -f $CFG <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
   <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
   </capabilities>
</hello>]]>]]>
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
     xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
     message-id="42">
  <edit-config>
    <target><candidate/></target>
    <default-operation>none</default-operation>
    <config>
       <services xmlns="http://clicon.org/controller">
	  <testA xmlns="urn:example:test" nc:operation="replace">
	     <name>foo</name>
	     <params>A0y</params>
	     <params>A0z</params>
	     <params>Ay</params>
	     <params>Az</params>
	     <params>ABy</params>
	     <params>ABz</params>
	 </testA>
      </services>
    </config>
  </edit-config>
</rpc>]]>]]>
EOF
)

match=$(echo "$ret" | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected"
    exit 1
fi

new "commit diff"
ret=$(${clixon_cli} -m configure -1f $CFG commit diff)
echo "$ret"
match=$(echo $ret | grep --null -Eo '+ <name>Az</name>') || true
if [ -z "$match" ]; then
    echo "commit diff failed"
    exit 1
fi
match=$(echo $ret | grep --null -Eo '\- <name>Ax</name') || true
if [ -z "$match" ]; then
    echo "commit diff failed"
    exit 1
fi

# Delete testA completely
new "delete testA(3)"
ret=$(${clixon_netconf} -0 -f $CFG <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
   <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
   </capabilities>
</hello>]]>]]>
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
     xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
     message-id="42">
  <edit-config>
    <target><candidate/></target>
    <default-operation>none</default-operation>
    <config>
       <services xmlns="http://clicon.org/controller">
          <testA xmlns="urn:example:test" nc:operation="delete">
            <name>foo</name>
          </testA>
      </services>
    </config>
  </edit-config>
</rpc>]]>]]>
EOF
)

echo "$ret"
match=$(echo "$ret" | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected"
    exit 1
fi

sleep $sleep
new "commit push"

set +e
expectpart "$(${clixon_cli} -m configure -1f $CFG commit push 2>&1)" 0 OK --not-- Error

new "get-config check removed Ax"
NAME=clixon-example1
ret=$(${clixon_netconf} -qe0 -f $CFG <<EOF
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
message-id="42">
  <get-config>
    <source><running/></source>
    <filter type='subtree'>
      <devices xmlns="http://clicon.org/controller">
	<device>
	  <name>$NAME</name>
	  <config>
	    <table xmlns="urn:example:clixon"/>
	  </config>
	</device>
      </devices>
    </filter>
  </get-config>
</rpc>]]>]]>
EOF
       )
echo "ret:$ret"
match=$(echo $ret | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected on $NAME"
    exit 1
fi

match=$(echo $ret | grep --null -Eo "<parameter><name>Ax</name></parameter>") || true
echo "match:$match"
if [ -n "$match" ]; then
    echo "Error:Ax is not removed in $NAME as it should be"
    exit 1
fi


# Delete testB completely
new "delete testB(4)"
ret=$(${clixon_netconf} -0 -f $CFG <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<hello xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
   <capabilities>
      <capability>urn:ietf:params:netconf:base:1.0</capability>
   </capabilities>
</hello>]]>]]>
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
     xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
     message-id="42">
  <edit-config>
    <target><candidate/></target>
    <default-operation>none</default-operation>
    <config>
       <services xmlns="http://clicon.org/controller">
          <testB xmlns="urn:example:test" nc:operation="delete">
            <name>foo</name>
          </testB>
      </services>
    </config>
  </edit-config>
</rpc>]]>]]>
EOF
)

echo "$ret"
match=$(echo "$ret" | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected"
    exit 1
fi

sleep $sleep
new "commit push"
set +e
expectpart "$(${clixon_cli} -m configure -1f $CFG commit push 2>&1)" 0 OK --not-- Error

new "get-config check removed Ax"
NAME=clixon-example1
ret=$(${clixon_netconf} -qe0 -f $CFG <<EOF
<rpc xmlns="urn:ietf:params:xml:ns:netconf:base:1.0"
xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0"
message-id="42">
  <get-config>
    <source><running/></source>
    <filter type='subtree'>
      <devices xmlns="http://clicon.org/controller">
	<device>
	  <name>$NAME</name>
	  <config>
	    <table xmlns="urn:example:clixon"/>
	  </config>
	</device>
      </devices>
    </filter>
  </get-config>
</rpc>]]>]]>
EOF
       )
echo "ret:$ret"
match=$(echo $ret | grep --null -Eo "<rpc-error>") || true
if [ -n "$match" ]; then
    echo "netconf rpc-error detected on $NAME"
    exit 1
fi

match=$(echo $ret | grep --null -Eo "<parameter><name>Bx</name></parameter>") || true
echo "match:$match"
if [ -n "$match" ]; then
    echo "Error:Bx is not removed in $NAME as it should be"
    exit 1
fi

if $BE; then
    new "Kill old backend"
    sudo clixon_backend -s init -f $CFG -z
fi

echo "test-service OK"
