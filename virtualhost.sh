#!/bin/sh
#================================================================================
# virtualhost.sh
#
# A fancy little script to setup a new virtualhost in Ubuntu based upon the  
# excellent virtualhost (V1.04) script by Patrick Gibson <patrick@patrickg.com> for OS X.
#
# This script has been tested on Ubuntu 7.10 (Gutsy Gibbon) with Apache2(!) and 
# probably works on Debian as well, but this has not been tested (yet). If you use 
# this script on other Linux distributions and can confirm it to work I would like to hear
# from you. Just send an email to Bjorn Wijers <burobjorn@burobjorn.nl> with more info
#
# USAGE:
# 
# CREATE A VIRTUAL HOST:
# sudo ./virtualhost <name>
# where <name> is the one-word name you'd like to use. (e.g. mysite)
#   
# Note that if "virtualhost.sh" is not in your PATH, you will have to write
# out the full path to where you've placed: eg. /usr/bin/virtualhost.sh <name>
# 
# REMOVE A VIRTUAL HOST:
# sudo ./virtualhost --delete <site>
#
# where <site> is the site name you used when you first created the host. 
#

# Don't change this!
version="ubuntu>13-1.0"
#

# No point going any farther if we're not running correctly...
if [ `whoami` != 'root' ]; then
  echo "virtualhost.sh requires super-user privileges to work."
  echo "Enter your password to continue..."
  sudo "$0" $* || exit 1
  exit 0
fi

if [ "$SUDO_USER" = "root" ]; then
  /bin/echo "You must start this under your regular user account (not root) using sudo."
  /bin/echo "Rerun using: sudo $0 $*"
  exit 1
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# If you are using this script on a production machine with a static IP address,
# and you wish to setup a "live" virtualhost, you can change the following IP
# address to the IP address of your machine.
#
IP_ADDRESS="127.0.0.1"

#
# By default, this script places files in /home/[you]/Sites. If you would like
# to change this, like to how Apache on Ubuntu does things by default, uncomment the
# following line:
#
#DOC_ROOT_PREFIX="/var/www"

# Configure the apache-related paths
#
APACHE_CONFIG_FILENAME="apache2.conf"
APACHE_CONFIG="/etc/apache2"
APACHECTL="/usr/sbin/apache2ctl"

# Set the virtual host configuration directory
APACHE_VIRTUAL_HOSTS_ENABLED="sites-enabled"
APACHE_VIRTUAL_HOSTS_AVAILABLE="sites-available"

# Set the browser to use, in GNOME you can use gnome-open to use the system default browser, but I prefer to call Firefox directly
DEFAULT_BROWSER="/usr/bin/firefox -new-tab" 

# By default, use the site folders that get created will be 0wn3d by this group
OWNER_GROUP="www-data"

# If you are running this script on a platform other than Mac OS X, your home
# partition is going to be different. If so, change it here.
HOME_PARTITION="/home"

# to be nagged about "fixing" your DocumentRoot, set this to "yes".
SKIP_DOCUMENT_ROOT_CHECK="no"

# If Apache works on a different port than the default 80, set it here
APACHE_PORT="80"

# Set to "yes" if you don't have a browser (headless) or don't want the site
# to be launched in your browser after the virtualhost is setup.
#SKIP_BROWSER="yes"

# You can now store your configuration directions in a ~/.virtualhost.sh.conf
# file so that you can download new versions of the script without having to
# redo your own settings.
if [ -e ~/.virtualhost.sh.conf ]; then
  . ~/.virtualhost.sh.conf
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# Based on FreeBSD's /etc/rc.subr
checkyesno()
{
  case $1 in
    #       "yes", "true", "on", or "1"
    [Yy][Ee][Ss]|[Tt][Rr][Uu][Ee]|[Oo][Nn]|[Yy]|1)
    return 0
    ;;

    #       "no", "false", "off", or "0"
    [Nn][Oo]|[Ff][Aa][Ll][Ss][Ee]|[Oo][Ff][Ff]|[Nn]|0)
    return 1
    ;;

    *)
    return 1
    ;;
  esac
}


#======= DO NOT EDIT BELOW THIS lINE UNLESS YOU KNOW WHAT YOU ARE DOING ======== 


if [ -z $USER -o $USER = "root" ]; then
  if [ ! -z $SUDO_USER ]; then
    USER=$SUDO_USER
  else
    USER=""

    /bin/echo "ALERT! Your root shell did not provide your username."

    while : ; do
      if [ -z $USER ]; then
        while : ; do
          /bin/echo -n "Please enter *your* username: "
          read USER
          if [ -d $HOME_PARTITION/$USER ]; then
            break
          else
            /bin/echo "$USER is not a valid username."
          fi
        done
      else
        break
      fi
    done
  fi
fi

if [ -z $DOC_ROOT_PREFIX ]; then
  DOC_ROOT_PREFIX="${HOME_PARTITION}/$USER/Sites"
fi

usage()
{
  cat << __EOT
Usage: sudo virtualhost.sh <name>
       sudo virtualhost.sh --delete <name>
   where <name> is the one-word name you'd like to use. (e.g. mysite)

   Note that if "virtualhost.sh" is not in your PATH, you will have to write
   out the full path to it: eg. /Users/$USER/Desktop/virtualhost.sh <name>

__EOT
  exit 1
}

if [ -z $1 ]; then
  usage
else
	if [ $1 = "--delete" ]; then
		if [ -z $2 ]; then
			usage
		else
			VIRTUALHOST=$2
			DELETE=0
		fi		
	else
		VIRTUALHOST=$1
	fi
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Delete the virtualhost if that's the requested action
#
if [ ! -z $DELETE ]; then
  /bin/echo -n "- Deleting virtualhost, $VIRTUALHOST... Continue? [Y/n]: "

	read continue
	
	case $continue in
	n*|N*) exit
	esac

	if grep -q -E "$VIRTUALHOST$" /etc/hosts ; then
		echo "  - Removing $VIRTUALHOST from /etc/hosts..."
		echo -n "  * Backing up current /etc/hosts as /etc/hosts.original..."
		cp /etc/hosts /etc/hosts.original	
		sed "/$IP_ADDRESS\t$VIRTUALHOST/d" /etc/hosts > /etc/hosts2
		mv -f /etc/hosts2 /etc/hosts
		echo "done"
		
		if [ -e "$APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED/$VIRTUALHOST".conf ]; then
			DOCUMENT_ROOT=`grep DocumentRoot $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED/$VIRTUALHOST | awk '{print $2}'`

			if [ -d $DOCUMENT_ROOT ]; then
				echo -n "  + Found DocumentRoot $DOCUMENT_ROOT. Delete this folder? [y/N]: "

				read resp
			
				case $resp in
				y*|Y*)
					echo -n "  - Deleting folder... "
					if rm -rf $DOCUMENT_ROOT ; then
						echo "done"
					else
						echo "Could not delete $DOCUMENT_ROOT"
					fi
				;;
				esac
				
				echo -n "  - Deleting virtualhost file... ($APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED/$VIRTUALHOST) and ($APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE/$VIRTUALHOST) "
				/usr/sbin/a2dissite $VIRTUALHOST 1>/dev/null 2>/dev/null
				rm "$APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE/$VIRTUALHOST".conf
				echo "done"

				echo -n "+ Restarting Apache... "
				## /usr/sbin/apachectl graceful 1>/dev/null 2>/dev/null
				$APACHECTL graceful 1>/dev/null 2>/dev/null
				echo "done"
			fi
		fi
	else
		echo "- Virtualhost $VIRTUALHOST does not currently exist. Aborting..."
	fi

	exit
fi


FIRSTNAME=`finger | awk '{print $2}' | tail -n 1`
cat << __EOT
Hi $FIRSTNAME! Welcome to virtualhost.sh. This script will guide you through setting
up a name-based virtualhost. 

__EOT

echo -n "Do you wish to continue? [Y/n]: "

read continue

case $continue in
n*|N*) exit
esac


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Make sure $APACHE_CONFIG/$APACHE_CONFIG_FILENAME is ready for virtual hosting...
#
# If it's not, we will:
#
# a) Backup the original to $APACHE_CONFIG/$APACHE_CONFIG_FILENAME.original
# b) Add a NameVirtualHost 127.0.0.1 line
# c) Create $APACHE_CONFIG/virtualhosts/ (virtualhost definition files reside here)
# d) Add a line to include all files in $APACHE_CONFIG/virtualhosts/
# e) Create a _localhost file for the default "localhost" virtualhost
#

if ! checkyesno ${SKIP_DOCUMENT_ROOT_CHECK} ; then
	if ! grep -q -e "^DocumentRoot \"$DOC_ROOT_PREFIX\"" $APACHE_CONFIG/$APACHE_CONFIG_FILENAME ; then
		echo "The DocumentRoot in $APACHE_CONFIG_FILENAME does not point where it should."
		echo -n "Do you want to set it to $DOC_ROOT_PREFIX? [Y/n]: "	
		read DOCUMENT_ROOT
		case $DOCUMENT_ROOT in
		n*|N*)
			echo "Okay, just re-run this script if you change your mind."
		;;
		*)
			cat << __EOT | ed $APACHE_CONFIG/$APACHE_CONFIG_FILENAME 1>/dev/null 2>/dev/null
/^DocumentRoot
i
#
.
j
+
i
DocumentRoot "$DOC_ROOT_PREFIX"
.
w
q
__EOT
    ;;
    esac
  fi
fi

if ! grep -q -E "^NameVirtualHost \*:$APACHE_PORT" $APACHE_CONFIG/$APACHE_CONFIG_FILENAME ; then

	echo "$APACHE_CONFIG_FILENAME not ready for virtual hosting. Fixing..."
	cp $APACHE_CONFIG/$APACHE_CONFIG_FILENAME $APACHE_CONFIG/$APACHE_CONFIG_FILENAME.original
	echo "NameVirtualHost *:$APACHE_PORT" >> $APACHE_CONFIG/$APACHE_CONFIG_FILENAME
	
	if [ ! -d $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE ]; then
		mkdir $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE
		cat << __EOT > $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE/_localhost
<VirtualHost $IP_ADDRESS:$APACHE_PORT>
  DocumentRoot $DOC_ROOT_PREFIX
  ServerName localhost

  <Directory $DOC_ROOT_PREFIX>
    Options All
    AllowOverride All
	Require local
  </Directory>
</VirtualHost>
__EOT
		if [ ! -d $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED ]; then
			mkdir $APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED
		fi	
	fi

	echo "Include /$APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_ENABLED"  >> $APACHE_CONFIG/$APACHE_CONFIG_FILENAME
fi


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# If the virtualhost is not already defined in /etc/hosts, define it...
#
if grep -q -E "^$VIRTUALHOST" /etc/hosts ; then

	echo "- $VIRTUALHOST already exists."
	echo -n "Do you want to replace this configuration? [Y/n] "
	read resp

	case $resp in
	n*|N*)	exit
	;;
	esac

else
	if [ $IP_ADDRESS != "127.0.0.1" ]; then
		cat << _EOT
We would now normally add an entry in your /etc/hosts so that
you can access this virtualhost using a name rather than a number.
However, since you have set the virtualhost to something other than
127.0.0.1, this may not be necessary. (ie. there may already be a DNS
record pointing to this IP)

_EOT
		echo -n "Do you want to add this anyway? [y/N] "
		read add_net_info

		case $add_net_info in
		y*|Y*)	exit
		;;
		esac
	fi
	echo 
	echo "Creating a virtualhost for $VIRTUALHOST..."
	echo -n "+ Adding $VIRTUALHOST to /etc/host... "
	echo "$IP_ADDRESS\t$VIRTUALHOST" >> /etc/hosts  
	echo "done"
fi


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Ask the user where they would like to put the files for this virtual host
#
echo -n "+ Checking for $DOC_ROOT_PREFIX/$VIRTUALHOST... "

if [ ! -d $DOC_ROOT_PREFIX/$VIRTUALHOST ]; then
	echo "not found"
else
	echo "found"
fi
	
echo -n "  - Use $DOC_ROOT_PREFIX/$VIRTUALHOST as the virtualhost folder? [Y/n] "

read resp

case $resp in

  n*|N*)
    while : ; do
      if [ -z "$FOLDER" ]; then
        /bin/echo -n "  - Enter new folder name (located in $DOC_ROOT_PREFIX): "
        read FOLDER
      else
        break
      fi
    done
  ;;

  *) 
	if [ -d $DOC_ROOT_PREFIX/$VIRTUALHOST/public ]; then
      /bin/echo -n "  - Found a public folder suggesting a Rails/Rack project. Use as DocumentRoot? [Y/n] "
      read response

      if checkyesno ${response} ; then
        FOLDER=$VIRTUALHOST/public
      else
        FOLDER=$VIRTUALHOST
      fi
    elif [ -d $DOC_ROOT_PREFIX/$VIRTUALHOST/web ]; then
      /bin/echo -n "  - Found a web folder suggesting a Symfony project. Use as DocumentRoot? [Y/n] "
      read response
      
      if checkyesno ${response} ; then
        FOLDER=$VIRTUALHOST/web
      else
        FOLDER=$VIRTUALHOST
      fi
    else
      FOLDER=$VIRTUALHOST
    fi
  ;;
esac

# Create the folder if we need to...
if [ ! -d "$DOC_ROOT_PREFIX/$FOLDER" ]; then
	echo -n "  + Creating folder $DOC_ROOT_PREFIX/$FOLDER... "
	su $USER -c "mkdir -p $DOC_ROOT_PREFIX/$FOLDER"
	/bin/echo "done"
	
	# If $FOLDER is deeper than one level, we need to fix permissions properly
	case $FOLDER in
		*/*)
			subfolder=0
		;;
	
		*)
			subfolder=1
		;;
	esac

	if [ $subfolder != 1 ]; then
		# Loop through all the subfolders, fixing permissions as we go
		#
		# Note to fellow shell-scripters: I realize that I could avoid doing
		# this by just creating the folders with `su $USER -c mkdir ...`, but
		# I didn't think of it until about five minutes after I wrote this. I
		# decided to keep with this method so that I have a reference for myself
		# of a loop that moves down a tree of folders, as it may come in handy
		# in the future for me.
		dir=$FOLDER
		while [ $dir != "." ]; do
			chown $USER:$OWNER_GROUP $DOC_ROOT_PREFIX/$dir
			dir=`dirname $dir`
		done
	else
		chown $USER:$OWNER_GROUP $DOC_ROOT_PREFIX/$FOLDER
	fi
	
	echo "done"
fi


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create a default index.html if there isn't already one there
#
if [ ! -e $DOC_ROOT_PREFIX/$FOLDER/index.html -a ! -e $DOC_ROOT_PREFIX/$FOLDER/index.php ]; then

	cat << __EOF >$DOC_ROOT_PREFIX/$FOLDER/index.html
<html>
<head>
<title>Welcome to $VIRTUALHOST</title>
<style type="text/css">
 body, div, td { font-family: "Lucida Grande"; font-size: 12px; color: #666666; }
 b { color: #333333; }
 .indent { margin-left: 10px; }
</style>
</head>
<body link="#993300" vlink="#771100" alink="#ff6600">

<table border="0" width="100%" height="95%"><tr><td align="center" valign="middle">
<div style="width: 500px; background-color: #eeeeee; border: 1px dotted #cccccc; padding: 20px; padding-top: 15px;">
 <div align="center" style="font-size: 14px; font-weight: bold;">
  Congratulations!
 </div>

 <div align="left">
  <p>If you are reading this in your web browser, then the only logical conclusion is that the <b><a href="http://$VIRTUALHOST:$APACHE_PORT/">http://$VIRTUALHOST:$APACHE_PORT/</a></b> virtualhost was setup correctly. :)</p>

  <p>You can find the configuration file for this virtual host in:<br>
  <table class="indent" border="0" cellspacing="3">
   <tr>
    <td><b>$APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE/$VIRTUALHOST.conf</b></td>
   </tr>
  </table>
  </p>

  <p>You will need to place all of your website files in:<br>
  <table class="indent" border="0" cellspacing="3">
   <tr>
    <td><b><a href="file://$DOC_ROOT_PREFIX/$FOLDER">$DOC_ROOT_PREFIX/$FOLDER</b></a></td>
   </tr>
  </table>
  </p>
  
  <p>This script is based upon the excellent virtualhost (V1.04) script by Patrick Gibson <patrick@patrickg.com> for OS X. 
  You can download the original script for OS X from Patrick's website: <b><a href="http://patrickg.com/virtualhost">http://patrickg.com/virtualhost</a></b>
  </p>
  <p>
  For the latest version of this script for Ubuntu go to <b><a href="https://github.com/ivoba/virtualhost.sh/tree/ubuntu">Github</a></b>!<br/>	
 The Ubuntu Version is based on Bjorn Wijers script. Visit Bjorn Wijers' website: <br />
  <b><a href="http://burobjorn.nl">http://burobjorn.nl</a></b><br>
	
  </p>
 </div>

</div>
</td></tr></table>

</body>
</html>
__EOF
	chown $USER:$OWNER_GROUP $DOC_ROOT_PREFIX/$FOLDER/index.html

fi	


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Create a default virtualhost file
#
echo -n "+ Creating virtualhost file... "
#"This seems to be quite a recent change in Ubuntu and caused me quite a bit of head-scratching. If you are on 12.10 then the virtual host file does not have to end in .conf but by 13.10 it does."
cat << __EOF >"$APACHE_CONFIG/$APACHE_VIRTUAL_HOSTS_AVAILABLE/$VIRTUALHOST".conf
<VirtualHost *:$APACHE_PORT>
  DocumentRoot $DOC_ROOT_PREFIX/$FOLDER
  ServerName $VIRTUALHOST

  <Directory $DOC_ROOT_PREFIX/$FOLDER>
    Options All
    AllowOverride All
    Require local
  </Directory>
</VirtualHost>
__EOF

	
# Enable the virtual host
/usr/sbin/a2ensite $VIRTUALHOST 1>/dev/null 2>/dev/null

echo "done"


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Restart apache for the changes to take effect
#
/bin/echo -n "+ Restarting Apache... "
$APACHECTL graceful 1>/dev/null 2>/dev/null
/bin/echo "done"

cat << __EOF

http://$VIRTUALHOST:$APACHE_PORT/ is setup and ready for use.

__EOF


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Launch the new URL in the browser
#
if [ -z $SKIP_BROWSER ]; then
  /bin/echo -n "Launching virtualhost... "
  sudo -u $USER -H $DEFAULT_BROWSER -new-tab "http://$VIRTUALHOST:$APACHE_PORT/"
  /bin/echo "done"
fi