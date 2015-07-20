# Wrapper for aht
function ahtaht() {
  #echo "** Aht command:    aht $STAGE @$SITENAME $URI $@" 1>&2
  aht $STAGE @${sitename}.${env} $@
}

#
# Add entry for vhosts
#
function add_vhosts() {
  vhosts_includes_dir=$1
  dest_dir_site=$2
  docroot=$3
  hostname=$4
  
  datetime=`date +"%D %T"`
  
  echo "Adding entry for apache vhosts at $vhosts_includes_dir/$hostname.conf ..."
  if [ ! -r $vhosts_includes_dir/$hostname.conf ]
  then
    echo "  Adding vhosts entry: $hostname => $dest_dir_site"
    #cat <<EOF |tee -a $vhosts_includes_dir/$hostname.conf
    cat <<EOF >> $vhosts_includes_dir/$hostname.conf
# Entry for $hostname, added $datetime
<VirtualHost *:${apache_http_port_number}>
    DocumentRoot $docroot
    ServerName $hostname
    ErrorLog "${dest_dir_site}/error.log"
    CustomLog "${dest_dir_site}/access.log" combinedio
    php_value error_log ${dest_dir_site}/php-errors.log
</VirtualHost>

# SSL Version. Same except for last 3 lines starting with SSL*
<VirtualHost *:${apache_https_port_number}>
    DocumentRoot $docroot
    ServerName $hostname
    ErrorLog "${dest_dir_site}/error.log"
    CustomLog "${dest_dir_site}/access.log" combinedio
    php_value error_log ${dest_dir_site}/php-errors.log
    # Here come the SSL config lines :)
    SSLEngine on
    SSLCertificateFile "/opt/lampp/etc/ssl.crt/server.crt"
    SSLCertificateKeyFile "/opt/lampp/etc/ssl.key/server.key"
</VirtualHost>

EOF
  else
    echo "  WARNING: Apache vhosts entry for $hostname already exists."
  fi
  echo "Done!"
  echo ""
}

#
# Add entry to /etc/hosts
#
function add_etchosts() {
  hostname=$1
  ip=${2:-127.0.0.1}
  datetime=`date +"%D %T"`
  echo "Adding entry for $hostname to /etc/hosts"
  if [ `grep -c "$hostname" /etc/hosts` -eq 0 ]
  then
    cat <<EOF |sudo tee -a /etc/hosts
# Entry for $hostname, added $datetime
$ip $hostname
EOF
  else
    echo "  WARNING: Entry for $hostname already exists on /etc/hosts:"
    #grep -A 1 "# Entry for $hostname, added.*" /etc/hosts |awk '{ print "  " $0 }'
    grep -B 1 $hostname /etc/hosts |awk '{ print "  " $0 }'
  fi
  echo "Done!"
  echo ""
}

#
# Add connection string to Drupal
#
function add_varwwwsitephp() {
  dest_dir_site=$1 #full path to repo folder
  docroot=$2
  dbname=$3        #local mysql dbname
  hostname=$4      #hostname
  sitefolder=${5:-default} #folder within sites/[sitefolder]
  dbuser=${6:-root}
  dbpassword=${7}
  table_prefix=${10}
  hash_salt=${11}

  tmpout=/tmp/tmp$$.1
  settings=$docroot/sites/$sitefolder/settings.php
  
  sitename=$8      #@[this].env, e.g. 'eeagarza'
  ac_db_name=$9    #db name in acquia cloud, e.g. 'eeagarza'
      
  if [ -r $settings ]
  then
    if [ `grep -c "require.*['\"].var.www.site-php.[a-z0-9A-Z_-]*.inc['\"]" $settings` -eq 1 ]
    then
      #Extract the sitename and ac_db_name from the existing require line
      grep -o "require.*['\"].var.www.site-php.[a-z0-9A-Z_-]*.inc['\"]" $settings |awk -F/ '{ print "  ac_db_name=" substr($6, 1, index($6, "-")-1); print "  sitename=" $5 }' >$tmpout
      echo "NOTE: Detected sitename and ac_db_name from require line in $settings:"
      cat $tmpout
      . $tmpout
    fi
  fi    
  datetime=`date +"%D %T"`
  if [ ! -r /var/www/site-php/${sitename} ]
  then
    echo "Linking /var/www/site-php/${sitename} to $dest_dir_site"
    sudo ln -s ${dest_dir_site} /var/www/site-php/$sitename
  fi
  echo "Adding DB connection string and other overrides to $dest_dir_site/${ac_db_name}-settings.inc"
  cat <<EOF >$dest_dir_site/${ac_db_name}-settings.inc
<?php

/**
 * Created by clone-acquia-mc-site.sh
 * For host: $hostname
 *       on: $datetime
 */

// Connection to local DB.
// D7 and D8 Version
\$databases['default']['default'] = array(
  'driver' => 'mysql',
  'database' => '$dbname',
  'username' => '$dbuser',
  'password' => '$dbpassword',
  'host' => 'localhost',
  'port' => $mysql_port_number,
  'prefix' => '$table_prefix',
  #'collation' => 'utf8_general_ci',
  'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',  #D8
);
// D6 Version
\$db_url='mysqli://$dbuser:$dbpassword@localhost/$dbname';

// D8 stuff
\$settings['hash_salt'] = '$hash_salt';
\$config_directories['active'] = conf_path() . '/files/config_1111111111111111111111111111111111111111/active';
\$config_directories['staging'] = conf_path() . '/files/config_1111111111111111111111111111111111111111/staging';

# Force some variables so as not to wreak havok on real site!
# Force apachesolr to be read-only!
\$conf['apachesolr_read_only'] = 1;
# Drupal should not run cron automatically
\$conf['cron_safe_threshold'] = 0;

# Add more memory, just in case!
ini_set('memory_limit', '256M');

# Fix file paths
\$conf['file_public_path'] = 'sites/$sitefolder/files';
\$conf['file_private_path'] = 'sites/$sitefolder/files';
\$conf['file_temporary_path'] = '/tmp';

# Fix for local domain.
\$base_url = "http://$hostname:${apache_http_port_number}";
\$cookie_domain = "$hostname";

# Report all PHP errors
error_reporting(E_ALL);
# Show errors on the HTML output sent to browsers.
ini_set('display_errors', TRUE);
# Show any errors that happen during PHP startup
ini_set('display_startup_errors', TRUE);
# Force-override the Drupal variable for error levels to show, to show "All messages"
# Setting is at: Administration > Configuration > Development > logging and errors
# Value 2 == ERROR_REPORTING_DISPLAY_ALL
\$conf['error_level'] = 2;

####################
# Memcache stuff::
# - Set the key to something sane for your local memcache.
\$conf['memcache_key_prefix'] = '${dbname}';

# To DISABLE memcahe on a site that already has it, uncomment the following:
#unset(\$conf['cache_inc']);

# To ENABLE memcache on a site that does not already has it enabled, uncomment this:
#\$conf['cache_backends'][] = './sites/all/modules/contrib/memcache/memcache.inc';
#\$conf['cache_default_class'] = 'MemCacheDrupal';
#\$conf['cache_class_cache_form'] = 'DrupalDatabaseCache';
#####################

######################
# Connect site to another Acquia Subscription
# Uncomment following and Call this to refresh sub:
#   drush ev 'acquia_agent_check_subscription(); print_r(acquia_agent_get_subscription());'
# @eeagarza 's subscription
#\$conf['acquia_identifier'] = 'ABIR-36398';
#\$conf['acquia_key'] = '86a93199c349139595cb17f2a04dbfa2';
######################


////////////////////////////////////////////////////////////////

EOF
  echo "Done!"
  echo ""
}
