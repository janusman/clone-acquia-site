Clones an acquia site locally using aht and your local AMP stack. Some things it does:

* checks out the code repo
* copies the latest daily DB backup locally
* creates the /etc/hosts and vhosts entry
* optionally converts some DB tables into MyISAM for ~3x quicker import, and sanitizes the user data
* it creates a skeleton PHPStorm project within the docroot with the necessary run configuration for debugging
* automatically disables a few access control modules (like shield) and sets apachesolr read-only mode to avoid accidents

# Installation

**NOTE:** You will need to know a bit about how your AMP stack is set up to configure it for the
first time.

You can place the folder anywhere. To be able to run this you can either:

* add the folder to your PATH environment variable in .bashrc
* or, add an alias to the full path where clone-acquia-site.sh lives

You will also need to copy the correct config.sh.default-* file to a config.sh
file and edit it to match your current LAMP/AMP stack config. This is a bit adva

# Usage

`clone-acquia-mc-site.sh [options] sitename env`

Options:


```
  -h or --help          : Shows this help text and exits.
  --mc  or  --dc        : Force devcloud/managed cloud site.
  --skip-repo           : Skip repo checkout
  --skip-db             : Skip DB download/creation
  --site-folder=default : name of folder within docroot/sites/* to use. Defaults to 'default'
  --site-db=sitename    : Database name to use. Use same string as from the Acquia require line:
                            require('/var/www/site-php/[sitename]/[sitedb]-settings.inc');
                         (Defaults to the same value as the sitename argument.)
  --local-hostname=...  : Local hostname to use. Defaults to "local.[env].[sitename]"
  --local-dbname=...    : Local DB name to use.  Defaults to "local.[env].[sitename].[site-folder]"
  --local-dbfile=...    : Local DB file to use. If present, it skips downloading the DB from the site.
  --skip-convert-myisam : Do *NOT* convert all DB tables to MyISAM (for perf. purposes)
  --delete              : DELETE a local site completely *** DANGER ***
```
