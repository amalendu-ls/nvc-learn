#!/bin/bash
# Moodle 5.2 install for CT 102 (nvc-moodle, <MOODLE_IP>), Ubuntu 24.04.
# Nginx + PHP 8.3-FPM + MariaDB 10.11 + Redis. TLS ends at the proxy (CT 103, <PROXY_IP>).
# Resumable: each finished stage leaves a marker in /root/.msi/ -- just re-run after a failure.
# Log: /root/moodle-install.log
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
M=/root/.msi; mkdir -p $M
PHPV=8.3; BRANCH=502
MD=/var/www/moodle; DATA=/var/moodledata
WWW=https://learn.nvc.ac.in
step(){ echo; echo "===== $(date '+%F %T') STAGE $1 ====="; }
has(){ [ -f $M/$1 ]; }
fin(){ touch $M/$1; echo "----- $(date '+%F %T') done: $1"; }

if ! has 01-apt; then step "01 apt packages (Nginx, PHP $PHPV-FPM, MariaDB, Redis)"
  apt-get update
  apt-get -y install nginx mariadb-server redis-server cron curl unzip ghostscript openssl \
    php$PHPV-fpm php$PHPV-cli php$PHPV-mysql php$PHPV-xml php$PHPV-mbstring php$PHPV-curl \
    php$PHPV-zip php$PHPV-gd php$PHPV-intl php$PHPV-soap php$PHPV-bcmath php$PHPV-readline \
    php$PHPV-opcache php$PHPV-redis
  php -m | grep -i '^sodium$' >/dev/null || { echo "ERROR: PHP sodium extension missing"; exit 1; }
  fin 01-apt; fi

if ! has 02-php; then step "02 PHP settings"
  for sapi in fpm cli; do
    cat > /etc/php/$PHPV/$sapi/conf.d/99-moodle.ini <<'X'
max_input_vars = 5000
memory_limit = 256M
upload_max_filesize = 256M
post_max_size = 256M
max_execution_time = 300
opcache.enable = 1
opcache.memory_consumption = 256
opcache.max_accelerated_files = 20000
opcache.revalidate_freq = 60
X
  done
  P=/etc/php/$PHPV/fpm/pool.d/www.conf
  sed -i -E 's/^pm.max_children = .*/pm.max_children = 40/; s/^pm.start_servers = .*/pm.start_servers = 8/; s/^pm.min_spare_servers = .*/pm.min_spare_servers = 4/; s/^pm.max_spare_servers = .*/pm.max_spare_servers = 12/' $P
  systemctl restart php$PHPV-fpm
  fin 02-php; fi

if ! has 03-db; then step "03 MariaDB database 'moodle' (random password)"
  cat > /etc/mysql/mariadb.conf.d/99-moodle.cnf <<'X'
[mysqld]
innodb_buffer_pool_size = 1G
innodb_file_per_table = 1
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
bind-address = 127.0.0.1
X
  systemctl restart mariadb
  DBPASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
  mariadb <<X
CREATE DATABASE moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'moodle'@'localhost' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON moodle.* TO 'moodle'@'localhost';
FLUSH PRIVILEGES;
X
  umask 077; echo "$DBPASS" > /root/.moodle-db-password
  fin 03-db; fi
DBPASS=$(cat /root/.moodle-db-password)

if ! has 04-code; then step "04 Moodle code (latest $BRANCH)"
  curl -fL --retry 5 --retry-delay 15 -o /tmp/moodle.tgz \
    https://download.moodle.org/download.php/direct/stable$BRANCH/moodle-latest-$BRANCH.tgz
  rm -rf $MD && mkdir -p /var/www && tar xzf /tmp/moodle.tgz -C /var/www
  mkdir -p $DATA && chown -R www-data:www-data $DATA && chmod 0770 $DATA
  fin 04-code; fi

# Moodle 5.1+ keeps web files in public/; CLI scripts may live in either place
WEBROOT=$MD; [ -d $MD/public ] && WEBROOT=$MD/public
CLI=$(ls -d $MD/admin/cli $MD/public/admin/cli 2>/dev/null | head -1 || true)
echo "web root: $WEBROOT   cli: $CLI"

if ! has 05-install; then step "05 Moodle CLI install (creates tables -- takes a while)"
  ADMPASS=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 20)
  umask 077; echo "$ADMPASS" > /root/.moodle-admin-initial-password; umask 022
  chown -R www-data:www-data $MD
  runuser -u www-data -- php $CLI/install.php --non-interactive --agree-license --lang=en \
    --wwwroot=$WWW --dataroot=$DATA --dbtype=mariadb --dbhost=localhost \
    --dbname=moodle --dbuser=moodle --dbpass="$DBPASS" --prefix=mdl_ \
    --fullname="Nabadwip Vidyasagar College LMS" --shortname="NVC LMS" \
    --adminuser=<ADMIN_USER> --adminpass="$ADMPASS" --adminemail=librarian@example.edu \
    --supportemail=librarian@example.edu
  fin 05-install; fi

CFG=$(ls $MD/config.php $MD/public/config.php 2>/dev/null | head -1 || true)
if ! has 06-config; then step "06 config.php: HTTPS proxy, X-Accel-Redirect, Redis sessions"
  cat > /tmp/moodle-extra.php <<'X'
// --- added by moodle-install.sh ---
$CFG->sslproxy = true;                       // TLS terminates at the reverse proxy (CT 103)
$CFG->xsendfile = 'X-Accel-Redirect';        // let Nginx serve files from moodledata
$CFG->xsendfilealiases = ['/dataroot/' => $CFG->dataroot];
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '127.0.0.1';
$CFG->session_redis_port = 6379;
$CFG->session_redis_prefix = 'mdl_sess_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;
// --- end ---
X
  awk -v f=/tmp/moodle-extra.php '/^require_once/{while((getline l<f)>0)print l} {print}' $CFG > /tmp/cfg.new && cat /tmp/cfg.new > $CFG
  php -l $CFG
  # Trust X-Forwarded-For only from the proxy, so logs show real visitor IPs
  runuser -u www-data -- php $CLI/cfg.php --name=getremoteaddrconf --set=1
  runuser -u www-data -- php $CLI/cfg.php --name=reverseproxyignore --set=<PROXY_IP>
  chown -R root:www-data $MD && chmod -R g-w,o-rwx $MD && chmod 640 $CFG
  fin 06-config; fi

if ! has 07-nginx; then step "07 Nginx site (port 80, behind the proxy)"
  cat > /etc/nginx/sites-available/moodle <<X
server {
    listen 80 default_server;
    server_name learn.nvc.ac.in;
    root $WEBROOT;
    index index.php;
    client_max_body_size 256M;
    fastcgi_read_timeout 300s;

    location ~ \.php(/|\$) {
        fastcgi_split_path_info ^(.+\.php)(/.*)?\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name \$fastcgi_script_name/ /r.php\$is_args\$args;
        fastcgi_pass unix:/run/php/php$PHPV-fpm.sock;
        include fastcgi_params;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
    }
    location / {
        try_files \$uri \$uri/ /r.php\$is_args\$args;
    }
    location /dataroot/ {
        internal;
        alias $DATA/;
    }
    location ~ /\.(?!well-known).* { return 404; }
    location ~ (/vendor/|/node_modules/|composer\.json|/readme|/README) { deny all; return 404; }
}
X
  ln -sf /etc/nginx/sites-available/moodle /etc/nginx/sites-enabled/moodle
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
  fin 07-nginx; fi

if ! has 08-cron; then step "08 Cron (every minute)"
  echo "* * * * * www-data /usr/bin/php $CLI/cron.php >/dev/null 2>&1" > /etc/cron.d/moodle
  chmod 644 /etc/cron.d/moodle
  fin 08-cron; fi

step "09 Checks"
systemctl enable nginx php$PHPV-fpm mariadb redis-server cron >/dev/null 2>&1
for s in nginx php$PHPV-fpm mariadb redis-server cron; do echo "$s: $(systemctl is-active $s)"; done
echo "Moodle version: $(runuser -u www-data -- php -r "define('CLI_SCRIPT',1); require '$CFG'; echo \$CFG->release;" 2>/dev/null)"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: learn.nvc.ac.in' -H 'X-Forwarded-Proto: https' http://127.0.0.1/login/index.php)
echo "Login page via Nginx: HTTP $code (200 = OK)"
runuser -u www-data -- php $CLI/cron.php >/tmp/cron-test.log 2>&1 && echo "Cron run: OK" || echo "Cron run: FAILED (see /tmp/cron-test.log)"
echo "INSTALL-FINISHED"
