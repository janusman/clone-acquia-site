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

### Start of D8 Stuff
if (!function_exists('conf_path')) {
  function conf_path(\$require_settings = TRUE, \$reset = FALSE, \Symfony\Component\HttpFoundation\Request \$request = NULL) {
    if (!isset(\$request)) {
      if (\Drupal::hasRequest()) {
        \$request = \Drupal::request();
      }
      // @todo Remove once external CLI scripts (Drush) are updated.
      else {
        \$request = \Symfony\Component\HttpFoundation\Request::createFromGlobals();
      }
    }
    if (\Drupal::hasService('kernel')) {
      \$site_path = \Drupal::service('kernel')->getSitePath();
    }
    if (!isset(\$site_path) || empty(\$site_path)) {
      \$site_path = \Drupal\Core\DrupalKernel::findSitePath(\$request, \$require_settings);
    }
    return \$site_path;
  }
}
\$settings['hash_salt'] = '$hash_salt';
\$my_config_dir = "/files/config_1111111111111111111111111111111111111111";
\$settings["config_sync_directory"] = conf_path() . \$my_config_dir . '/sync';
\$config_directories['active'] = conf_path() . \$my_config_dir . '/active';
\$config_directories['staging'] = conf_path() . \$my_config_dir . '/staging';
// Make local.* hostnames into the trusted host patterns
// TODO: Maybe add these instead of overriding them!
\$settings['trusted_host_patterns'] = array('^local..*');
\$settings['system.logging']['error_level'] = 'all';
### End of D8 Stuff


# Force some variables so as not to wreak havok on real site!
# Force apachesolr to be read-only!
\$conf['apachesolr_read_only'] = 1;
# Drupal should not run cron automatically
\$conf['cron_safe_threshold'] = 0;

# Add more memory, just in case!
ini_set('memory_limit', '256M');

# Fix file paths
\$conf['file_public_path'] = 'sites/$sitefolder/files';
\$conf['file_private_path'] = '$dest_dir_site/files-private';
\$conf['file_temporary_path'] = '/tmp/$hostname';
\$settings['file_temp_path'] = '/tmp/$hostname';
\$config['system.file']['path']['temporary'] = '/tmp/$hostname'; 

# Fix for local domain.
\$base_url = "http://$hostname";
\$cookie_domain = "$hostname";
\$conf['securepages_basepath'] = "http://$hostname";
\$conf['securepages_basepath_ssl'] = "https://$hostname";
\$conf['securepages_enable'] = FALSE;

# Report all PHP errors (except "Deprecated" Warnings)
error_reporting(E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED);
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
\$conf['memcache_servers'] = array('127.0.0.1:11211' => 'default');
\$conf['memcache_key_prefix'] = '${dbname}' . '_';
\$settings['memcache']['servers'] = \$conf['memcache_servers'];
\$settings['memcache']['key_prefix'] = \$conf['memcache_key_prefix'];


# To DISABLE memcahe on a site that already has it, uncomment the following:
#unset(\$conf['cache_inc']);
#\$settings["cache"]["default"] = "cache.backend.database";

# To ENABLE memcache on a site that does not already has it enabled, uncomment this:
#\$conf['cache_backends'][] = './sites/all/modules/contrib/memcache/memcache.inc';
#\$conf['cache_default_class'] = 'MemCacheDrupal';
#\$conf['cache_class_cache_form'] = 'DrupalDatabaseCache';

# Completely disable APCU/Memcache caching in D8 by uncommenting the following:
#\$settings['cache']['default'] = 'cache.backend.database';
#\$settings['cache']['bins']['bootstrap'] = 'cache.backend.database';
#\$settings['cache']['bins']['discovery'] = 'cache.backend.database';
#\$settings['cache']['bins']['config'] = 'cache.backend.database';
#\$settings['class_loader_auto_detect'] = FALSE;
#####################

######################
# Connect site to another Acquia Subscription
# Uncomment following and Call this to refresh sub:
#   drush ev 'acquia_agent_check_subscription(); print_r(acquia_agent_get_subscription());'
# @eeagarza 's subscription
#\$conf['acquia_identifier'] = 'ABIR-36398';
#\$conf['acquia_key'] = '86a93199c349139595cb17f2a04dbfa2';
######################

######################
# Devel email
#
# $conf['mail_system'] = array('default-system' => 'DevelMailLog');
######################

######################
# Acquia environment
#\$_ENV["AH_SITE_ENVIRONMENT"] = "dev";
#\$_ENV["AH_SITE_GROUP"] = "${sitename}";

######################
# Acquia Search override
#
\$solr_conf = [ 'host' => 'useast1-c26.acquia-search.com', 'id' => 'ABIR-36398.dev.solr4', 'key' => '039fea043277909a084bba937a22e0b4d2ccd296' ];
### D7 Apachesolr
#\$conf['apachesolr_environments']['acquia_search_server_1']['url'] = 'http://' . $solr_conf['host'] . '/solr/' . $solr_conf['id'];
#\$conf['apachesolr_environments']['acquia_search_server_1']['conf']['acquia_search_key'] = $solr_conf['key'];
#
### D8 Search API Solr
#\$config['acquia_search.settings']['connection_override'] = [
#  'host' => \$solr_conf['host'],
#  'index_id' => \$solr_conf['id'],
#  'derived_key' => \$solr_conf['key'],
#  'scheme' => 'http',
#  'port' => 80,
#];
### V3 Search
#\$config['acquia_search_solr.settings']['override_search_core'] = 'ABIR-36398.dev.eeagarza';
######################

////////////////////////////////////////////////////////////////

EOF

  # If BLT exists, make some adjustments
  if [ -r $docroot/../blt ]
  then
    echo "${COLOR_YELLOW}BLT install found, configuring files in $docroot/sites/${sitefolder}/settings...${COLOR_NONE}"
    if [ -r $docroot/sites/$sitefolder/settings/trusted_host.settings.php ]
    then
      echo '$settings["trusted_host_patterns"][] = "^local..*";' >>$docroot/sites/$sitefolder/settings/trusted_host.settings.php
    fi
    if [ -r $docroot/sites/$sitefolder/settings/local.settings.php ]
    then
      mv $docroot/sites/$sitefolder/settings/local.settings.php $docroot/sites/$sitefolder/settings/local.settings.php-RENAMED-BY-CLONE-ACQUIA-SITE
    fi
    # Make sites/[site]/settings/local.settings.php link to the file we just wrote above.
    ln -s $dest_dir_site/${ac_db_name}-settings.inc $docroot/sites/$sitefolder/settings/local.settings.php
    echo "  $docroot/sites/$sitefolder/settings/local.settings.php points to ${ac_db_name}-settings.inc"
  fi
  
  echo "Done!"
  echo ""
}

function header() {
  echo ""
  echo "${COLOR_GRAY}._____________________________________________________________________________"
  echo "|${COLOR_GREEN}  $1${COLOR_NONE}"
}
