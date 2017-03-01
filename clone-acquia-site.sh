#!/bin/bash
#
# For docs, type:
#   bash clone-acquia-mc-site.sh -h
# TODOs:
# * Allow local memcache/other cache_inc (right now it's overridden and disabled)
# * Allow cookie_domain and base_url to remain (this script disables them)
# * Refactor apache reload to stop and then start (in case there's not a reload command?)
# * DOES NOT WORK WITH:
#   * Sites with table prefixes
# * enabling logging email to file using devel?
# * Add $_ENV['AH_SITE_ENVIRONMENT'] = 'local'; ??

# Get the path to this script
clone_command_folder="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -r $clone_command_folder/config.sh ]
then
  cat <<EOF
No $clone_command_folder/config.sh file found!
* You should copy the included $clone_command_folder/config.sh.default file into
a config.sh file.
* Then, you must edit this file to match your environment.
EOF
  exit 1
else
  source $clone_command_folder/config.sh
fi

# Include common functions
source $clone_command_folder/functions.sh

# Defaults
#site_folder=default #Site folder you are targetting.
table_prefix=""
skip_data_tables=2t283762uhqweuyqweouyqwoeuy # Random never-ever-matching tablename
YES=""
# Constants
# See http://linuxtidbits.wordpress.com/2008/08/11/output-color-on-bash-scripts/
COLOR_RED=$(tput setaf 1) #"\[\033[0;31m\]"
COLOR_YELLOW=$(tput setaf 3) #"\[\033[0;33m\]"
COLOR_GREEN=$(tput setaf 2) #"\[\033[0;32m\]"
COLOR_GRAY=$(tput setaf 7) #"\[\033[2;37m\]"
COLOR_NONE=$(tput sgr0) #"\[\033[0m\]"


# BEGIN!
# Detect if we are in an existing site's folder:
if [ -f ../../clone-site-args.txt ]
then
  echo "${COLOR_YELLOW}Previous site found!"
  awk '/^[A-Za-z]/ { print "  " $0 }' ../../clone-site-args.txt
  echo "$COLOR_NONE"
  # Source that shit
  source ../../clone-site-args.txt
fi

# Get options
# http://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options/7680682#7680682
while test $# -gt 0
do
  case $1 in

  # Normal option processing
    -h | --help)
      HELP=1
      ;;
    -y)
      YES="-y"
      ;;
  # Special cases
    --)
      break
      ;;
  # Long options
    --help)
      HELP=1
      ;;
    --stages=*)
      STAGE=$1
      ;;
    --mc)
      STAGE=$1
      ;;
    --dc)
      STAGE=$1
      ;;
    --ac)
      STAGE=$1
      ;;
    --ace)
      STAGE=$1
      ;;
    --network)
      STAGE=$1
      ;;
    --skip-db)
      echo "  ${COLOR_YELLOW}Skipping database download/creation${COLOR_NONE}"
      skip_db=1
      ;;
    --skip-repo)
      echo "  ${COLOR_YELLOW}Skipping repository checkout${COLOR_NONE}"
      skip_repo=1
      ;;
    --skip-convert-myisam)
      echo "  ${COLOR_YELLOW}Skipping InnoDB -> MyISAM conversion${COLOR_NONE}"
      innodb_to_myisam=0
      ;;
    --myisam-latin-charset)
      echo "  ${COLOR_YELLOW}Enabled latin1 conversion during InnoDB -> MyISAM conversion${COLOR_NONE}"
      myisam_latin_charset=1
      ;;
    --uri=*)
      uri=`echo $1 |cut -f2- -d=`
      echo " Using uri $uri"
      ;;
    --site-folder=*)
      site_folder=`echo $1 |cut -f2- -d=`
      echo "  Using site folder $site_folder"
      ;;
    --ac-db-name=*)
      ac_db_name=`echo $1 |cut -f2- -d=`
      echo "  Using remote Database $ac_db_name"
      ;;
    --local-hostname=*)
      local_hostname=`echo $1 |cut -f2- -d=`
      echo "  Using localhostname $local_hostname"
      ;;
    --local-dbname=*)
      local_dbname=`echo $1 |cut -f2- -d=`
      echo "  Using localdbname $local_dbname"
      ;;
    --local-dbfile=*)
      tmp=`echo $1 |cut -f2- -d=`
      local_dbfile=`realpath $tmp`
      if [ $? -gt 0 ]
      then
        echo "${COLOR_RED}ERROR: Can't find $tmp{COLOR_NONE}"
        exit 1
      else
        echo "  Using localdbfile $local_dbfile"
      fi
      ;;
    --table-prefix=*)
      table_prefix=`echo $1 |cut -f2- -d=`
      echo "  Using table-prefix $table_prefix"
      ;;
    --skip-data-tables=*)
      skip_data_tables=`echo $1 |cut -f2- -d=`
      echo "  Skipping data import of tables matching $skip_data_tables"
      ;;
    --delete)
      delete_site=1;
      ;;
    --*)
      # error unknown (long) option $1
      echo "  ${COLOR_RED}Warning: Unknown option $1${COLOR_NONE}"
      ;;
    -?)
      # error unknown (short) option $1
      ;;

  # MORE FUN STUFF HERE:
  # Split apart combined short options
  #  -*)
  #    split=$1
  #    shift
  #    set -- $(echo "$split" | cut -c 2- | sed 's/./-& /g') "$@"
  #    continue
  #    ;;

  # Done with options, the sitename comes last.
    @*)
      SITENAME=$1
      ;;
  esac

  shift
done

if [ ${SITENAME:-x} = x ]
then
  HELP=1
fi

if [ ${HELP:-x} = 1 ]
then
  cat <<EOF
USAGE: $0 sitename env

Clones a site locally. Usage:
  clone-acquia-mc-site.sh [options] @SITENAME.ENV
Options:
  -h or --help          : Shows this help text and exits.
  --mc  or  --dc        : Force devcloud/managed cloud site.
  --skip-repo           : Skip repo checkout
  --skip-db             : Skip DB download/creation
  --uri=http://....     : Use this URI for autodetection
  --site-folder=default : name of folder within docroot/sites/* to use. Defaults to 'default'
  --ac-db-name=sitename    : Database name to use. Use same string as from the Acquia require line:
                            require('/var/www/site-php/[sitename]/[sitedb]-settings.inc');
                         (Defaults to the same value as the sitename argument.)
  --local-hostname=...  : Local hostname to use. Defaults to "local.[env].[sitename]"
  --local-dbname=...    : Local DB name to use.  Defaults to "local.[env].[sitename].[site-folder]"
  --local-dbfile=...    : Local DB file to use. If present, it skips downloading the DB from the site.
  --table-prefix=...    : Define the table prefix used by the site.
  --skip-convert-myisam : Do *NOT* convert all DB tables to MyISAM (for perf. purposes)
  --skip-data-tables=[regex] : Skip data import of table names that match the regex
                            Example: --skip-data-tables="^(foo|bar)"  #Skip tables prefixed 'foo' or 'bar'
  --myisam-latin-charset: Additionally to innodb->myisam conversion, convert to latin1 charset.
                          ** DANGER: CAN CAUSE DATA LOSS OR OTHERWISE WEIRD BEHAVIOR **
  --delete              : DELETE a local site completely *** DANGER ***
EOF
  exit
fi

# Some calculated vars
SITENAME=`echo $SITENAME |cut -c2-`       # Trim @ from sitename
sitename=`echo $SITENAME |cut -f1 -d'.'`  # split site/env
env=`echo $SITENAME |cut -f2 -d'.'`       # split site/env
ac_db_name=${ac_db_name:-${sitename}}
hostname=${local_hostname:-local.${env}.${sitename}}
dbname=${local_dbname:-${hostname}.${ac_db_name}}
dest_dir_site=${dest_dir}/${hostname}
tmpscript=/tmp/tmp$$.sh
tmpscript2=/tmp/tmp$$.2.sh
tmpout=/tmp/tmp$$.out
tmpout2=/tmp/tmp$$.2.out
datetime=`date +"%D %T"`
phpstorm_idea_template_folder=$clone_command_folder/phpstorm-idea-template-folder
vhosts_includes_dir=$dest_dir/vhosts-config-apache #folder to place generated [hostname].conf files included from apache's vhosts config.

# Are we DELETING??
# TODO: Delete from /var/www/site-php/*.inc
if [ ${delete_site:-x} = 1 ]
then
  # Use the clone-site-args.txt settings if available
  if [ -r $dest_dir_site/clone-site-args.txt ]
  then
    #echo "Found $dest_dir_site/clone-site-args.txt ..."
    #cat $dest_dir_site/clone-site-args.txt
    #. $dest_dir_site/clone-site-args.txt
    ac_db_name=${ac_db_name:-${sitename}}
    hostname=${local_hostname:-local.${env}.${sitename}}
    dbname=${local_dbname:-${hostname}.${ac_db_name}}
    dest_dir_site=${dest_dir}/${hostname}
  fi
  echo "${COLOR_RED}==== ATTENTION: DELETING THIS SITE LOCALLY: ==============="
  echo "       Folder: $dest_dir_site"
  echo "     Database: $dbname"
  echo "  Hosts entry: $hostname"
  echo
  echo "** PRESS ANY KEY TO CONTINUE, CTRL-C TO BREAK **${COLOR_NONE}"
  read

  # /etc/hosts
  if [ `egrep -c "^(# Entry for |127.0.0.1 )$hostname" /etc/hosts` -gt 0 ]
  then
    echo "Removing hosts entry $hostname ..."
    hosts_bak=/tmp/hosts.backup.$$
    cat /etc/hosts >$hosts_bak
    echo "  Made backup at $hosts_bak"
    egrep -v "^(# Entry for |127.0.0.1 )$hostname" $hosts_bak |sudo tee /etc/hosts >/dev/null
    echo "  Wrote /etc/hosts"
  else
    echo "${COLOR_YELLOW}Warning: No entries for $hostname in /etc/hosts!${COLOR_NONE}"
  fi
  echo ""

  # Database
  if [ `echo SHOW DATABASES |mysql |grep -c $dbname` -eq 1 ]
  then
    echo "Removing DB $dbname ..."
    mysqladmin --force -u$dbuser --password=$dbpassword drop $dbname
    echo "  Done."
  else
    echo "${COLOR_YELLOW}Warning: Database $dbname does not exist!${COLOR_NONE}"
  fi
  echo ""

  # Vhosts entry
  if [ -r ${vhosts_includes_dir}/$hostname.conf ]
  then
    echo "Removing ${vhosts_includes_dir}/$hostname.conf"
    rm ${vhosts_includes_dir}/$hostname.conf
    echo "  Done."
  else
    echo "${COLOR_YELLOW}Warning: No vhosts entry ${vhosts_includes_dir}/$hostname.conf${COLOR_NONE}"
  fi
  echo ""

  # /var/www/site-php/XXX
  if [ -r /var/www/site-php/$sitename ]
  then
    echo "Removing /var/www/site-php/$sitename"
    sudo rm /var/www/site-php/$sitename
    echo "  Done."
  else
    echo "Warning: No symlink /var/www/site-php/$sitename found"
  fi
  echo ""

  # Site folder
  if [ -d $dest_dir_site ]
  then
    echo "Removing site folder at $dest_dir_site ..."
    sudo rm -rf $dest_dir_site
    echo "  Done."
  else
    echo "Warning: Could not find folder at $dest_dir_site!"
  fi
  echo ""

  echo "Finished!"
  exit 0
fi

#
# Run a few checks first
#
cd $dest_dir
if [ $? -gt 0 ]
then
  echo "${COLOR_RED}ERROR: Could not find destination folder (defined in \$dest_dir):"
  echo "   $dest_dir${COLOR_NONE}"
  exit 1
fi

# Make sure required files/paths exist
if [ ! -r /var/www/site-php ]
then
  echo "${COLOR_RED}ERROR: Could not find the required /var/www/site-php folder"
  echo "  You should create it first by running:"
  echo "  mkdir -p /var/www/site-php${COLOR_NONE}"
  exit 1
fi
if [ ! -r $vhosts_path ]
then
  echo "${COLOR_RED}ERROR: Could not find your apache vhosts configuration file (defined in \$vhosts_path):"
  echo "  $vhosts_path${COLOR_NONE}"
  exit 1
fi
if [ ! -r $vhosts_includes_dir ]
then
  echo "${COLOR_RED}ERROR: Could not find \$vhosts_includes_dir: ${vhosts_includes_dir}"
  echo "  If the path is correct, you should create it with:  mkdir -p ${vhosts_includes_dir}"
  echo "  Or, edit the path to use on the script.${COLOR_NONE}"
  exit 1
fi
if [ ! -w $vhosts_includes_dir ]
then
  echo "${COLOR_RED}ERROR: \$vhosts_includes_dir: ${vhosts_includes_dir} is not writeable.${COLOR_NONE}"
  exit 1
fi
if [ `grep -c "Include ${vhosts_includes_dir}/*" $vhosts_path` -eq 0 ]
then
  echo "${COLOR_RED}ERROR: ${vhosts_path} does not have an include line pointing to ${vhosts_includes_dir}"
  echo "   Please add this line to the file:"
  echo ""
  echo "   Include ${vhosts_includes_dir}/*${COLOR_NONE}"
  exit 1
fi
if [ ! -x $drush ]
then
  echo "${COLOR_RED}ERROR: Could not find drush at the path specified in \$drush:"
  echo "  $drush${COLOR_NONE}"
  exit 1
fi

# Check aht works
echo "" |ahtaht site:info >$tmpout 2>&1
if [ `egrep -c "Could not find sitegroup or environment|Catchable fatal error" $tmpout` -eq 1 ]
then
  echo "${COLOR_RED}ERROR: Site possibly needs --ace or --ac switch.${COLOR_NONE}"
  exit 1
fi
if [ `grep -c "Failed to establish" $tmpout` -eq 1 ]
then
  echo "
${COLOR_RED}ERROR: It looks like aht/bastion is down!${COLOR_NONE}
"
  cat $tmpout
  echo ""
  exit 1
fi

if [ ${local_dbfile:-x} != x ]
then
  if [ ! -r $local_dbfile ]
  then
    echo "${COLOR_RED}ERROR: --local-dbfile=$local_dbfile doesn't exist${COLOR_NONE}"
    echo ""
    exit 1
  else
    echo "${COLOR_GREEN}Using local db file: $local_dbfile${COLOR_NONE}"
  fi
fi

# Check that needed commands exist and are executable.
path_ok=1
#   Loop thru commands
for command in mysql
do
  which $command >/dev/null 2>&1
  if [ $? -gt 0 ]
  then
    echo "${COLOR_RED}ERROR: the '${command}' command is not in your PATH enviroment variable.${COLOR_NONE}"
    path_ok=0
  fi
done
#   Quit if any command wasn't found
if [ $path_ok -eq 0 ]
then
  echo ""
  echo "Current value of PATH:"
  echo "  $PATH"
  echo ""
  exit 1
fi

# WARN when /var/www/site-php/${sitename} already exists
if [ -r /var/www/site-php/${sitename} ]
then
  echo "${COLOR_YELLOW}WARNING: /var/www/site-php/${sitename} exists and points here:"
  ls -l /var/www/site-php/${sitename}
  echo "${COLOR_NONE}"
  #exit 1
fi


# WARN when destination repofolder already exists
if [ -r $dest_dir_site ]
then
  echo "${COLOR_YELLOW}WARNING: Destination folder $dest_dir_site already exists!"
  echo "You might want to try going an already-existing local site here:"
  echo "  http://${hostname}/${COLOR_NONE}"
fi

if [ ${site_folder:-x} = x ]
then
  # Check sitename/env exists!
  ahtaht application:sites >$tmpout
  if [ $? -gt 0 ]
  then
    echo "${COLOR_RED}ERROR: aht could not find the site/environment using: aht @${sitename}.${env}${COLOR_NONE}"
    exit 1
  fi

  # Warning if this looks like a multisite Drupal site.
  if [ `grep -c . $tmpout` -gt 1 ]
  then
    # If we have a --uri, try to get it from there.
    if [ ${uri:-x} != x ]
    then
      site_folder=`ahtaht drush8 status --uri=$uri |grep "Site path" |awk '{ print $4 }' |cut -f2 -d/`
      if [ ${site_folder:-x} != x ]
      then
        echo "NOTE: This site has various sites/* folders, but using --uri=$uri the '$site_folder' folder was detected."
      fi
    fi
    # Show interactive menu if we couldn't figure out the folder
    if [ ${uri:-x} = x -o ${site_folder:-x} = x ]
    then
      echo "WARNING: this site has various sites/* folders, but you specified none with the --site-folder=xxx option."
      echo "  ${sitename}.${env} currently has these sites:"
      cat $tmpout |awk '{ print "    " $0 }'
      echo ""
      read -p "Type a site folder from above, or just hit [Enter] to use the 'default' folder: " foo
      site_folder=${foo:-default}
    fi
  else
    site_folder=default
  fi

  echo ""
  header "Autodetecting DB name... (you can skip this by specifying the --site-folder argument)"
  uriarg="${uri:-$site_folder}"
  ahtaht drush8 status --uri=$uriarg --pipe >$tmpout 2>&1
  if [ `grep -c "Drush command terminated abnormally" $tmpout` -gt 0 ]
  then
    echo "${COLOR_RED}Could not run drush on site! Errors below:"
    cat $tmpout
    echo "${COLOR_NONE}"
    exit 1
  fi
  # Get some vars from drush status
  cat $tmpout |grep -v '^[^{} ]' |php -r '
    $result = (array)json_decode(trim(stream_get_contents(STDIN)));
    echo "internal_db_name=\"" . $result["db-name"] . "\"\n";
    echo "drupal_version=\"" . substr($result["drupal-version"], 0, 1) . "\"\n";
  ' >$tmpout2
  cat $tmpout2
  . $tmpout2
  ac_db_name=`ahtaht db:list |awk '$2 == "'$internal_db_name'" { print $1 }'`
  dbname=${local_dbname:-${hostname}.${ac_db_name}}
  echo "  AC DB: $ac_db_name (Internal name: $internal_db_name)"
  echo "  Local DBname: '$dbname'"
  # If running D8, get the hash!
  if [ ${drupal_version} = 8 ]
  then
    echo "Running DRUPAL 8"
    hash_salt=`aht $STAGE @$SITENAME drush8 ev --uri=$uriarg ' echo \Drupal\Core\Site\Settings::getHashSalt()'`
    echo "--hash_salt setting is $hash_salt";
  fi
  echo "Done!"
  echo ""
fi

# Check database does not exist
if [ `echo "SHOW DATABASES LIKE '$dbname'" | mysql -u$dbuser --password=$dbpassword |wc -l` -gt 0 -a ${skip_db:-0} = 0 ]
then
  echo "${COLOR_RED}ERROR: Database $dbname already exists. You can remove it, or use the --skip-db option."
  echo "  To remove it, run:"
  echo "  mysqladmin --force -u$dbuser --password=$dbpassword drop $dbname${COLOR_NONE}"
  exit 1
fi

#
# Start!
#
mkdir $dest_dir_site 2>/dev/null
cd $dest_dir_site

# Make a file that shows what the arguments used to call this script were.
date=`date`
cat <<EOF >clone-site-args.txt
# These are the arguments used to call the clone-acquia-mc-site.sh script
# Generated on $date
# Command: $0
SITENAME=@$SITENAME
STAGE=$STAGE
innodb_to_myisam=$innodb_to_myisam
myisam_latin_charset=$myisam_latin_charset
uri=$uri
site_folder=$site_folder
ac_db_name=$ac_db_name
local_hostname=$local_hostname
local_dbname=$local_dbname
local_dbfile=$local_dbfile
skip_data_tables=$skip_data_tables
table_prefix=$table_prefix
drupal_version=$drupal_version
hash_salt=$hash_salt
EOF

# Clone the repository
header "Code repository"
if [ ${skip_repo:-x} = x ]
then
  echo "Attempting to checkout the code repository..."
  # Note, sed https://... to fix broken aht repo --checkout
  ahtaht repo --checkout |grep -v "Site is in live development"|tr -d '\012\015' |sed -e 's/https:..https:../https:\/\//'  > $tmpscript
  # Check command successful
  if [ $? -gt 0 ]
  then
    exit 1
  fi
  # Check NOT in livedev
  #if [ `grep -c "Site is in live development" $tmpscript` -eq 1 ]
  #then
  #  echo "Error:"
  #  cat $tmpscript
  #  exit 1
  #fi
  sep="/"
  if [ `cat $tmpscript |grep -c .git` -eq 1 ]
  then
    sep=":"
  fi
  repofolder=`cat $tmpscript | cut -f2 -d'@' |awk -F${sep} '{ print $NF }' |cut -f1 -d' ' |sed -e 's/.git$//'`
  # Check repofolder does not exist
  if [ -r $repofolder ]
  then
    echo "  $repofolder exists! Skipping cloning..."
  else
    # Clone it
    echo "Cloning the code repository to $repofolder, using:"
    cat $tmpscript | awk '{ print "  " $0 }'
    sh $tmpscript
    if [ $? -gt 0 ]
    then
      echo "Error cloning code repository to $repofolder."
      exit 1
    fi
  fi
  echo "Done!"
  echo ""
else
  echo "Skipping repo clone. Looking for existing repository..."
  repofolder=`find . -maxdepth 2 -name docroot |cut -f2 -d'/'`
  if [ ${repofolder:-x} != x ]
  then
    echo "Repository found at $repofolder"
  else
    echo "ERROR: Could not find a repo folder with a 'docroot' folder within "`pwd`
    exit 1
  fi
  echo ""
fi

#
# Get DB and load it locally.
#
header "Database"
if [ ${skip_db:-x} = x ]
then
  if [ "${local_dbfile:-x}" = x ]
  then
    echo "Getting database..."
    ahtaht db:backup-get --latest --database=$ac_db_name >$tmpscript
    if [ $? -gt 0 ]
    then
      echo "ERROR: Could not find database '$ac_db_name'"
      echo "  Please specify a correct one using --ac-db-name=[dbname]"
      exit 1
    fi
    if [ `grep -c 'There were no backups found' $tmpscript` -eq 1 ]
    then
      echo "ERROR: No backup to download"
      echo "  You can create one by running:"
      echo "    aht $STAGE @${sitename}.${env} db:backup-create --database=$ac_db_name"
      echo "  After that task finishes, you can run this script again."
      exit 1
    fi
    cat $tmpscript |tr -d '\015' >$tmpscript2
    dbfilename_remote=`cat $tmpscript2 |awk '{ print $(NF-1); }'`
    dbfilename=`basename ${dbfilename_remote}`

    # The above should set $dbfilename and $tmpscript

    echo "  DB filename: $dbfilename"
    echo "  Rsync script from $tmpscript:"
    cat $tmpscript2 | awk '{ print "    " $0 }'
    echo ""

    # Sync it!!
    echo "  ryncing the DB file..."
    bash $tmpscript2
    # Confirm the file made it!
    if [ ! -r $dbfilename ]
    then
      echo "ERROR: Could not find synced DB file: $dbfilename in "`pwd`
      exit 1
    fi
    echo "Done!"
    echo ""
  else
    echo "Using local DB file: $local_dbfile"
    dbfilename=$local_dbfile
  fi

  #
  # Create a local DB
  #
  echo "Creating the database at $dbname from file $dbfilename"
  mysqladmin -u$dbuser --password=$dbpassword create $dbname 2>/dev/null
  if [ $? -gt 0 ]
  then
    echo "Error! Could not run mysqladmin create for database $dbname"
    exit 1
  fi
  # Import the database, skipping some data:
  echo "  Starting DB import..."
  gzip -d -c $dbfilename | awk -F'`' '
NR==1 {
  # http://superuser.com/questions/246784/how-to-tune-mysql-for-restoration-from-mysql-dump
  # TODO? http://www.palominodb.com/blog/2011/08/02/mydumper-myloader-fast-backup-and-restore ?
  print "SET SQL_LOG_BIN=0;"
  print "SET unique_checks=0;"
  print "SET autocommit=0;"
  print "SET foreign_key_checks=0;"
  output=1;
}
{
  start_of_line=substr($0,1,200);
  # Detect beginning of table structure definition.
  if (index(start_of_line, "-- Table structure for table")==1) {
    print "" >"/dev/stderr"
    output=1
    print "COMMIT;"
    print "SET autocommit=0;"
    current_db=$2    ## before, it was start_of_line
    printf " Processing table {" current_db "}"> "/dev/stderr"
  }
  # Switch the engine from InnoDB to MyISAM : MUCHO FAST.
  if (substr(start_of_line,1,8)==") ENGINE" && '${innodb_to_myisam:-0}' == 1) {
    if (current_db ~ /^'${table_prefix}'(locales_source|locales_target|menu_links|redirect|registry|registry_file|revision_scheduler|search_node_links|workbench_scheduler_types)/) {
      printf " ... Skipping InnoDB -> MyISAM for " current_db >"/dev/stderr"
    } else {
      gsub(/=InnoDB/, "=MyISAM", $0);
      if ('${myisam_latin_charset:-0}' == 1) {
        gsub(/CHARSET=utf8/, "CHARSET=latin1", $0);
      }
    }
  }
  # Detect beginning of table data dump.
  if (index(start_of_line, "-- Dumping data for table")==1) {
    if (current_db != $2) {
      printf "Internal problem: unexpected data, seems to come from table " $2 " whereas expected table " current_db >"/dev/stderr";
      current_db=$2
    }
    output=1
    # Skip data in some tables
    if (current_db ~ /^'${table_prefix}'(__ACQUIA_MONITORING|accesslog|audit_log|audit_log_roles|advancedqueue|batch|boost_cache|cache|cache_.*|feedback|field_data_field_accessed_categories|field_revision_field_accessed_categories|history|mail_logger|order_export.*|panels_hash_database_cache|queue|search_index|search_dataset|search_total|search_api_db.*|sessions|temp.*|watchdog|webform_sub.*)$/ || current_db ~ /'$skip_data_tables'/) {
      output=0
      printf " ... Skipping Data import (imported structure only) for " current_db >"/dev/stderr"
    }
  }
  if (output==1) {
    print
  }
}
END {
  print "COMMIT;"
}' |mysql -u$dbuser --password=$dbpassword $dbname

  if [ $? -gt 0 ]
  then
    echo "${COLOR_RED}Error! Could not import data into database $dbname"
    echo "  If you got a 'Key too long' error, try running again using these flags:"
    echo "   --myisam-latin-charset"
    echo "   --skip-convert-myisam"
    echo ""
    echo "To remove DB, use this command:"
    echo "  mysqladmin --force -u$dbuser --password=$dbpassword drop $dbname"
    echo "${COLOR_NONE}"
    exit 1
  fi

  echo "  Importing done!"

  # Scrub the users in the DB
  if [ ${drupal_version} != 8 ]
  then
    echo "  Scrubbing the users table in the DB..."
    echo "UPDATE users SET mail=CONCAT('user', uid, '@example.com') WHERE uid > 0" |mysql -u$dbuser --password=$dbpassword $dbname
    echo "  Scrubbing done!"
  fi

  echo "Done!"
  echo ""
else
  echo "Skipping DB download/import. Using database: $dbname"
  echo ""
fi


# Get some variables
docroot="${dest_dir_site}/${repofolder}/docroot"


# If this seems to be an ACSF site, move stuff around
if [ "$site_folder" = "g" ]
then
  header "Site seems to be Site Factory: creating replacement sites/default folder"
  curdir=`pwd`
  cd $docroot/sites
  git mv default default-original
  mkdir default
  cat <<EOF >default/settings.php
<?php

# This minimal settings.php was generated by clone-acquia-site.sh 
\$databases = array();
\$update_free_access = FALSE;
\$drupal_hash_salt = '';

ini_set('session.gc_probability', 1);
ini_set('session.gc_divisor', 100);
ini_set('session.gc_maxlifetime', 200000);
ini_set('session.cookie_lifetime', 2000000);

require_once "/var/www/site-php/${sitename}/${ac_db_name}-settings.inc";

EOF
  site_folder="default"
  cd $curdir
fi

sitefolderpath="${docroot}/sites/${site_folder}"
if [ ! -r $sitefolderpath ]
then
  echo "ERROR: Could not find the '${site_folder}' site folder at $sitefolderpath"
  exit 1
fi

# Configure apache
header "Configuring local Apache"

echo "add_varwwwsitephp '$dest_dir_site' '$docroot' '$dbname' '$hostname' '$site_folder' '$dbuser' '$dbpassword' '$sitename' '$ac_db_name' '$table_prefix' '$hash_salt'"
add_varwwwsitephp $dest_dir_site "$docroot" "$dbname" "$hostname" "$site_folder" "$dbuser" "$dbpassword" "$sitename" "$ac_db_name" "$table_prefix" "$hash_salt"

echo "add_vhosts $vhosts_includes_dir $dest_dir_site $docroot $hostname"
add_vhosts $vhosts_includes_dir $dest_dir_site $docroot $hostname

# Create and allow writing to new php-errors.log
echo "Creating empty .log files at ${dest_dir_site}..."
touch ${dest_dir_site}/error.log
touch ${dest_dir_site}/access.log
touch ${dest_dir_site}/php-errors.log
chmod a+w ${dest_dir_site}/*.log
ls ${dest_dir_site}/*.log | awk '{ print "  " $0 }'
echo "Done!"
echo ""

header "Add /etc/hosts entry"
add_etchosts $hostname

#
# Create files folder!
#
echo "Creating some folders..."
echo "  Creating EMPTY files folder at $sitefolderpath/files"
mkdir $sitefolderpath/files 2>/dev/null
chmod a+w $sitefolderpath/files
echo "  Creating tmp folder at /tmp/$hostname"
mkdir /tmp/$hostname 2>/dev/null
chmod a+w /tmp/$hostname
echo "Done!"
echo ""

#
# Restart apache!
#
echo "Restarting apache"
sudo $reload_apache_command
echo "Done!"
echo ""

#
# Add a sites.php entry
#
echo "Adding sites.php entry: $hostname => $site_folder"
# If file doesn't exist, create it!
if [ ! -r $docroot/sites/sites.php ]
then
  echo "<?php" >$docroot/sites/sites.php
fi
echo "## ADDED BY $0" >>$docroot/sites/sites.php
echo "\$sites['$hostname'] = '$site_folder';" >>$docroot/sites/sites.php
echo ""

#
# Test that Drush runs.
#
header "Configuring Drupal site to work (better) locally"
cd $sitefolderpath
$drush status >/dev/null 2>&1
drush_ran=0

modules_to_disable="securelogin shield domain_301_redirect new_relic_rpm password_policy simplesamlphp_auth"

if [ $? -gt 0 ]
then
  echo "  WARNING: Drush failed to run!"
else
  if [ ${drupal_version:-x} = 8 ]
  then
    echo "  Uninstalling some modules: $modules_to_disable"
    $drush pm-uninstall $YES $modules_to_disable
    echo "Running drush cr..."
    $drush cr
  else
    #
    # Issue some drush commands
    #
    echo "  Disabling some modules: $modules_to_disable"
    $drush dis $YES $modules_to_disable    
    echo ""
    echo "  Activating user 1 in case it is disabled"
    echo "UPDATE users SET status=1 WHERE uid=1" | $drush sql-cli
  fi
  echo "  Done!"
  drush_ran=1
fi
echo ""

#
# Add in a pre-made PHPStorm project
#
header "Adding PHPstorm project"
if [ -r $phpstorm_idea_template_folder ]
then
  cp -R $phpstorm_idea_template_folder $docroot/.idea
  # Change some variables in the project files
  if [ ${drupal_version:-x} = 8 ]
  then
    DRUPAL_VERSION=8
  else
    if [ `grep -c "core *= *7.x" $docroot/modules/node/node.info` -eq 1 ]
    then
      DRUPAL_VERSION=7
    else
      DRUPAL_VERSION=6
    fi
  fi
  settings_filename=${ac_db_name}-settings.inc
  #settings_filepath=$dest_dir_site/${settings_filename}
  cd $docroot/.idea
  # Replace placeholders with real values
  cat workspace.xml |sed \
    -e "s/{{DRUPAL_VERSION}}/$DRUPAL_VERSION/"\
    -e "s/{{HOSTNAME}}/$hostname/" \
    -e "s/{{VAR_WWW_PHP_SETTINGS_FILENAME}}/$settings_filename/" >$tmpout && cp $tmpout workspace.xml
  cat deployment.xml | sed -e "s%{{SITE_URL}}%$hostname%" >$tmpout && cp $tmpout deployment.xml
  # Add .gitignore for .idea
  echo ".idea/*" >>$docroot/.gitignore
  
  echo "  Done!"
  echo "  You can open the project directly in PhpStorm by running:"
  echo "    storm \"$docroot\""
  echo ""
fi

cd $docroot

# Done!
header "FINISHED!!!"
echo "Site ready!!!! \o/"
echo ""

#
# Bonus points:
# Get ULI location
#
if [ $drush_ran -eq 1 ]
then
  uli=`$drush uli --uri=$hostname`
  if [ $? -eq 0 ]
  then
    echo "You can go to the admin account here:"
    echo "  $uli"
  else
    echo "Could not get one-time login link via drush :("
  fi
fi
echo ""
echo "Site located here:"
echo "   On disk: $dest_dir_site"
echo "  Via http: http://$hostname/"
echo ""

#
# Cleanup
#
rm $tmpscript $tmpscript2 $tmpout 2>/dev/null
