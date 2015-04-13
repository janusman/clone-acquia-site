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

# BEGIN!
# Get options
# http://stackoverflow.com/questions/402377/using-getopts-in-bash-shell-script-to-get-long-and-short-command-line-options/7680682#7680682
while test $# -gt 0
do
  case $1 in

  # Normal option processing
    -h | --help)
      HELP=1
      ;;

  # Special cases
    --)
      break
      ;;
  # Long options
    --help)
      HELP=1
      ;;
    --mc)
      STAGE=$1
      ;;
    --dc)
      STAGE=$1
      ;;
    --network)
      STAGE=$1
      ;;
    --skip-db)
      echo "  Skipping database download/creation"
      skip_db=1
      ;;
    --skip-repo)
      echo "  Skipping repository checkout"
      skip_repo=1
      ;;
    --skip-convert-myisam)
      echo "  Skipping InnoDB -> MyISAM conversion"
      innodb_to_myisam=0
      ;;
    --myisam-latin-charset)
      echo "  Enabled latin1 conversion during InnoDB -> MyISAM conversion"
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
      local_dbfile=`echo $1 |cut -f2- -d=`
      echo "  Using localdbfile $local_dbfile"
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
      echo "  Warning: Unknown option $1"
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
datetime=`date +"%D %T"`
phpstorm_idea_template_folder=$clone_command_folder/phpstorm-idea-template-folder
vhosts_includes_dir=$dest_dir/vhosts-config-apache #folder to place generated [hostname].conf files included from apache's vhosts config.

# Are we DELETING??
# TODO: Delete from /var/www/site-php/*.inc
if [ ${delete_site:-x} = 1 ]
then
  echo "Deleting site:"
  echo "       Folder: $dest_dir"
  echo "     Database: $dbname"
  echo "  Hosts entry: $hostname"
  echo
  echo "** PRESS ANY KEY TO CONTINUE, CTRL-C TO BREAK **"
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
    echo "Warning: No entries for $hostname in /etc/hosts!"
  fi
  echo ""
  
  # Database
  if [ `echo SHOW DATABASES |mysql |grep -c $dbname` -eq 1 ]
  then
    echo "Removing DB $dbname ..."
    mysqladmin drop $dbname
    echo "  Done."
  else
    echo "Warning: Database $dbname does not exist!"
  fi
  echo ""
  
  # Vhosts entry
  if [ -r ${vhosts_includes_dir}/$hostname.conf ]
  then
    echo "Removing ${vhosts_includes_dir}/$hostname.conf"
    rm ${vhosts_includes_dir}/$hostname.conf
    echo "  Done."
  else
    echo "Warning: No vhosts entry ${vhosts_includes_dir}/$hostname.conf"
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
  echo "ERROR: Could not find destination folder (defined in \$dest_dir):"
  echo "   $dest_dir"
  exit 1
fi

# Make sure required files/paths exist
if [ ! -r /var/www/site-php ]
then
  echo "ERROR: Could not find the required /var/www/site-php folder"
  echo "  You should create it first by running:"
  echo "  mkdir -p /var/www/site-php"
  exit 1
fi
if [ ! -r $vhosts_path ]
then
  echo "ERROR: Could not find your apache vhosts configuration file (defined in \$vhosts_path):"
  echo "  $vhosts_path"
  exit 1
fi
if [ ! -r $vhosts_includes_dir ]
then
  echo "ERROR: Could not find \$vhosts_includes_dir: ${vhosts_includes_dir}"
  echo "  If the path is correct, you should create it with:  mkdir -p ${vhosts_includes_dir}"
  echo "  Or, edit the path to use on the script."
  exit 1
fi
if [ ! -w $vhosts_includes_dir ]
then
  echo "ERROR: \$vhosts_includes_dir: ${vhosts_includes_dir} is not writeable."
  exit 1
fi
if [ `grep -c "Include ${vhosts_includes_dir}/*" $vhosts_path` -eq 0 ]
then
  echo "ERROR: ${vhosts_path} does not have an include line pointing to ${vhosts_includes_dir}"
  echo "   Please add this line to the file:"
  echo ""
  echo "   Include ${vhosts_includes_dir}/*"
  exit 1
fi
if [ ! -x $drush ]
then
  echo "ERROR: Could not find drush at the path specified in \$drush:"
  echo "  $drush"
  exit 1
fi

# Check database does not exist
if [ `echo "SHOW DATABASES LIKE '$dbname'" | mysql -u$dbuser --password=$dbpassword |wc -l` -gt 0 -a ${skip_db:-0} = 0 -a ${local_dbfile:-0} = 0 ]
then
  echo "ERROR: Database $dbname already exists. You can remove it, or use the --skip-db option."
  echo "  To remove it, run:"
  echo "  mysqladmin -u$dbuser --password=$dbpassword drop $dbname"
  exit 1
fi

if [ ${local_dbfile:-x} != x ]
then
  if [ ! -r $local_dbfile ]
  then
    echo "ERROR: --local-dbfile=$local_dbfile doesn't exist"
    echo ""
    exit 1
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
    echo "ERROR: the '${command}' command is not in your PATH enviroment variable."
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
  echo "WARNING: /var/www/site-php/${sitename} exists and points here:"
  ls -l /var/www/site-php/${sitename} 
  #exit 1
fi


# WARN when destination repofolder already exists
if [ -r $dest_dir_site ]
then
  echo "WARNING: Destination folder $dest_dir_site already exists!"
  echo "You might want to try going an already-existing local site here:"
  echo "  http://${hostname}/"
fi

if [ ${site_folder:-x} = x ]
then
  # Check sitename/env exists!
  ahtaht application:sites >$tmpout
  if [ $? -gt 0 ]
  then
    echo "ERROR: aht could not find the site/environment using: aht @${sitename}.${env}"
    exit 1
  fi

  # Warning if this looks like a multisite Drupal site.
  if [ `grep -c . $tmpout` -gt 1 ]
  then
    # If we have a --uri, try to get it from there.
    if [ ${uri:-x} != x ]
    then
      site_folder=`ahtaht drush status --uri=$uri |grep "Site path" |awk '{ print $4 }' |cut -f2 -d/`
      echo "NOTE: This site has various sites/* folders, but using --uri=$uri the '$site_folder' folder was detected."
    else
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
  echo "Autodetecting DB name..."
  uriarg="${uri:-$site_folder}"
  internal_db_name=`ahtaht drush status --uri=$uriarg | grep "Database name" |awk '{print $4}'`
  ac_db_name=`ahtaht db:list |awk '$2 == "'$internal_db_name'" { print $1 }'`
  dbname=${local_dbname:-${hostname}.${ac_db_name}}
  echo "  AC DB: $ac_db_name (Internal name: $internal_db_name)"
  echo "  Local DBname: '$dbname'"
  echo "Done!"
  echo ""
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
$0 $SITENAME
  --uri=$uri
  --STAGE=$STAGE
  --site-folder=$site_folder
  --ac-db-name=$ac_db_name
  --local-hostname=$local_hostname
  --local-dbname=$local_dbname
  --local-dbfile=$local_dbfile
  --skip-data-tables=$skip_data_tables
EOF

# Clone the repository
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
if [ ${skip_db:-x} = x ]
then
  if [ ${local_dbfile:-x} = x ]
  then
    echo "Getting database..."
    ahtaht db:backup-get --latest --database=$ac_db_name >$tmpscript
    if [ $? -gt 0 ]
    then
      echo "ERROR: Could not find database '$ac_db_name'"
      echo "  Please specify a correct one using --ac-db-name=[dbname]"
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
    if (current_db ~ /^'${table_prefix}'(__ACQUIA_MONITORING|accesslog|batch|boost_cache|cache|cache_.*|feedback|field_data_field_accessed_categories|field_revision_field_accessed_categories|history|migrate_.*|panels_hash_database_cache|queue|search_index|search_dataset|search_total|sessions|watchdog|webform_sub.*)$/ || current_db ~ /'$skip_data_tables'/) {
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
    echo "Error! Could not import data into database $dbname"
    echo "  If you got a 'Key too long' error, try running again using these flags:"
    echo "   --myisam-latin-charset"
    echo "   --skip-convert-myisam"
    exit 1
  fi
  
  echo "  Importing done!"
  
  # Scrub the users in the DB
  echo "  Scrubbing the users table in the DB..."
  echo "UPDATE users SET mail=CONCAT('user', uid, '@example.com') WHERE uid > 0" |mysql -u$dbuser --password=$dbpassword $dbname
  echo "  Scrubbing done!"
  
  echo "Done!"
  echo ""
else
  echo "Skipping DB download/import. Using database: $dbname"
  echo ""
fi

# Get some variables
docroot="${dest_dir_site}/${repofolder}/docroot"
sitefolderpath="${docroot}/sites/${site_folder}"
if [ ! -r $sitefolderpath ]
then
  echo "ERROR: Could not find the '${site_folder}' site folder at $sitefolderpath"
  exit 1
fi


echo "add_varwwwsitephp '$dest_dir_site' '$docroot' '$dbname' '$hostname' '$site_folder' '$dbuser' '$dbpassword' '$sitename' '$ac_db_name' '$table_prefix'"
add_varwwwsitephp $dest_dir_site $docroot $dbname $hostname $site_folder $dbuser $dbpassword $sitename $ac_db_name $table_prefix

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

add_etchosts $hostname

#
# Create files folder!
#
echo "Creating EMPTY files folder at $sitefolderpath/files"
mkdir $sitefolderpath/files 2>/dev/null 
chmod a+w $sitefolderpath/files
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
# Test that Drush runs.
#
echo "Reconfiguring site using drush"
cd $sitefolderpath
$drush status >/dev/null 2>&1
drush_ran=0
if [ $? -gt 0 ]
then
  echo "  WARNING: Drush failed to run!"
else 
  #
  # Issue some drush commands
  #
  #modules_to_disable="memcache memcache_admin securelogin shield securepages"
  modules_to_disable="securelogin shield securepages"
  echo "  Disabling some modules: $modules_to_disable"
  $drush dis -y $modules_to_disable
  echo ""
  echo "  Activating user 1 in case it is disabled"
  echo "UPDATE users SET status=1 WHERE uid=1" | $drush sql-cli
  echo "  Done!"
  drush_ran=1
fi
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
# Add in a pre-made PHPStorm project
#
if [ -r $phpstorm_idea_template_folder ]
then
  echo "Adding PHPStorm project for this site..."
  cp -R $phpstorm_idea_template_folder $docroot/.idea
  # Change some variables in the project files
  if [ `grep -c "core *= *7.x" $docroot/modules/node/node.info` -eq 1 ]
  then
    DRUPAL_VERSION=7
  else
    DRUPAL_VERSION=6
  fi
  settings_filename=${ac_db_name}-settings.inc
  settings_filepath=$dest_dir_site/${settings_filename}
  cd $docroot/.idea
  cat workspace.xml |sed \
    -e "s/{{DRUPAL_VERSION}}/$DRUPAL_VERSION/"\
    -e "s/{{VAR_WWW_PHP_SETTINGS_FILENAME}}/$settings_filename/" >$tmpout && cp $tmpout workspace.xml
  cat deployment.xml | sed -e "s%{{SITE_URL}}%$hostname%" >$tmpout && cp $tmpout deployment.xml
  echo "  Done!"
  echo "  You can open the project directly in PhpStorm by running:"
  echo "    storm \"$docroot\""
  echo ""
fi

cd $docroot

# Done!
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
